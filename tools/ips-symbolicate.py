#!/usr/bin/env python3
"""Symbolicate an iOS .ips crash report on Linux.

usage: ips-symbolicate.py REPORT.ips [--binary PATH]...

Line 1 of the report is a JSON header; the rest is one JSON body. The tool
prints the app, version, OS, incident id, exception, termination, the faulting
thread, and each frame of the faulting thread and of lastExceptionBacktrace.
A frame the device already symbolicated keeps its name. A frame without a
symbol resolves against a --binary whose LC_UUID matches the frame's image
(thin arm64, or the arm64 slice of a fat file), using the nearest preceding
LC_SYMTAB function symbol. Swift names stay mangled unless swift-demangle is
on PATH. Pure Python 3 standard library; writes to stdout (errors to stderr)
and nowhere else.
"""
import argparse
import json
import shutil
import struct
import subprocess
import sys

MH_MAGIC_64, FAT_MAGIC = 0xFEEDFACF, 0xCAFEBABE
CPU_ARM64 = 0x0100000C
LC_SYMTAB, LC_SEGMENT_64, LC_UUID = 0x2, 0x19, 0x1B


def parse_thin(data):
    """Return (uuid_hex, sorted [(image_offset, name)]) for a thin arm64
    Mach-O, or None when it is not one."""
    if len(data) < 32 or struct.unpack_from("<I", data, 0)[0] != MH_MAGIC_64:
        return None
    if struct.unpack_from("<i", data, 4)[0] != CPU_ARM64:
        return None
    ncmds = struct.unpack_from("<I", data, 16)[0]
    uuid = symtab = text_vm = None
    off = 32
    for _ in range(ncmds):
        if off + 8 > len(data) or struct.unpack_from("<I", data, off + 4)[0] < 8:
            break
        cmd, size = struct.unpack_from("<II", data, off)
        if cmd == LC_UUID and off + 24 <= len(data):
            uuid = data[off + 8:off + 24].hex()
        elif cmd == LC_SYMTAB and off + 24 <= len(data):
            symtab = struct.unpack_from("<IIII", data, off + 8)
        elif (cmd == LC_SEGMENT_64 and off + 56 <= len(data)
              and data[off + 8:off + 16].rstrip(b"\0") == b"__TEXT"):
            text_vm = struct.unpack_from("<Q", data, off + 24)[0]
        off += size
    syms = []
    if uuid and symtab:
        symoff, nsyms, stroff, _strsize = symtab
        for i in range(nsyms):
            if symoff + 16 * (i + 1) > len(data):
                break
            n_strx, n_type, _sect, _desc, n_value = struct.unpack_from(
                "<IBBHQ", data, symoff + 16 * i)
            if n_type & 0x0E != 0x0E:
                continue
            start = stroff + n_strx
            if start >= len(data):
                continue
            end = data.find(b"\0", start)
            name = data[start:end if end >= 0 else len(data)].decode("utf-8", "replace")
            if name.startswith("_"):
                name = name[1:]
            syms.append((n_value - (text_vm or 0), name))
        syms.sort()
    return uuid, syms


def parse_binary(path):
    """Return (uuid_hex, symbols) for a thin or fat arm64 Mach-O, else None."""
    with open(path, "rb") as f:
        data = f.read()
    if len(data) >= 8 and struct.unpack_from(">I", data, 0)[0] == FAT_MAGIC:
        narch = struct.unpack_from(">I", data, 4)[0]
        for i in range(narch):
            entry = 8 + 20 * i
            if entry + 20 > len(data):
                break
            cpu, _sub, aoff, asize, _align = struct.unpack_from(">IIIII", data, entry)
            if cpu == CPU_ARM64 and aoff + asize <= len(data):
                return parse_thin(data[aoff:aoff + asize])
        return None
    return parse_thin(data)


def demangle(name):
    if "$s" not in name or demangler is None:
        return name
    r = subprocess.run([demangler], input=name, capture_output=True,
                       text=True, check=False)
    return r.stdout.strip() or name


def resolve(frame, images, bins):
    """Render one frame as '<image>  <symbol+offset>[ [markers]]'."""
    idx = frame.get("imageIndex")
    img = images[idx] if isinstance(idx, int) and 0 <= idx < len(images) and \
        isinstance(images[idx], dict) else None
    name = img.get("name", "?") if img else "?"
    sym = frame.get("symbol")
    if sym is not None:
        loc = frame.get("symbolLocation")
        return f"{name}  {sym}+{loc if loc is not None else '?'}"
    if img is None or frame.get("imageOffset") is None:
        return f"{name}  ?"
    want = norm_uuid(img.get("uuid", ""))
    b = bins.get(want)
    if b is None:
        return f"{name}  [no local binary for {name} {img.get('uuid', '?')}]"
    off = frame["imageOffset"]
    best = None
    for val, sym_name in b:
        if val <= off:
            best = (val, sym_name)
        else:
            break
    if best is None:
        return f"{name}  {off:#x} [no local symbol]"
    return f"{name}  {demangle(best[1])}+{off - best[0]:#x} [resolved locally]"


def norm_uuid(u):
    return str(u).replace("-", "").lower()


def main():
    global demangler
    ap = argparse.ArgumentParser(
        description="Symbolicate an iOS .ips crash report against local Mach-O files.")
    ap.add_argument("report", help="path to the .ips report")
    ap.add_argument("--binary", action="append", default=[], metavar="PATH",
                    help="local Mach-O to resolve frames against; repeatable")
    args = ap.parse_args()
    try:
        with open(args.report, encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError as e:
        sys.exit(f"error: cannot read {args.report}: {e.strerror or e}")
    first, _sep, rest = text.partition("\n")
    try:
        hdr = json.loads(first)
    except ValueError:
        sys.exit(f"error: {args.report}: line 1 is not JSON; not a valid .ips report")
    try:
        body = json.loads(rest)
    except ValueError:
        sys.exit(f"error: {args.report}: the report body after line 1 is not "
                 "valid JSON (report truncated or corrupt)")

    print(f"App: {hdr.get('app_name', '?')} {hdr.get('app_version', '?')}"
          f" ({hdr.get('bundleID', '?')})")
    print(f"OS: {hdr.get('os_version', '?')}")
    if hdr.get("incident_id"):
        print(f"Incident: {hdr['incident_id']}")
    exc = body.get("exception") or {}
    if exc:
        parts = [str(exc.get("type", "?"))]
        if exc.get("signal"):
            parts.append(f"({exc['signal']})")
        if exc.get("subtype"):
            parts.append(str(exc["subtype"]))
        print("Exception: " + " ".join(parts))
    term = body.get("termination") or {}
    if term:
        line = " ".join(str(term[k]) for k in ("namespace", "code") if term.get(k))
        if term.get("indicator"):
            line += f" ({term['indicator']})"
        print("Termination: " + (line or "?"))

    demangler = shutil.which("swift-demangle")
    bins = {}
    for path in args.binary:
        try:
            r = parse_binary(path)
        except OSError as e:
            sys.exit(f"error: cannot read {path}: {e.strerror or e}")
        if r is None:
            print(f"warning: {path}: no arm64 Mach-O slice with LC_UUID, ignored",
                  file=sys.stderr)
            continue
        bins[r[0]] = r[1]

    images = [im for im in body.get("usedImages") or [] if isinstance(im, dict)]
    threads = body.get("threads") or []
    ct = body.get("faultingThread")
    if not isinstance(ct, int):
        ct = next((i for i, t in enumerate(threads)
                   if isinstance(t, dict) and t.get("triggered")), None)
    if ct is None:
        print(f"Faulting thread: none of {len(threads)}")
    else:
        print(f"Faulting thread: {ct} of {len(threads)}")
        for i, fr in enumerate(threads[ct].get("frames") or []):
            print(f"  {i}  {resolve(fr, images, bins)}")
    last = body.get("lastExceptionBacktrace")
    if last:
        print("Last exception backtrace:")
        for i, fr in enumerate(last):
            print(f"  {i}  {resolve(fr, images, bins)}")


demangler = None
if __name__ == "__main__":
    main()
