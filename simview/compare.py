#!/usr/bin/env python3
"""Compare two PNGs under the simview golden tolerance.

Tolerance, stated here and enforced below:
  - at most MAX_DIFFERING_PIXELS pixels may differ at all
  - every channel of every pixel may differ by at most MAX_CHANNEL_DIFF

Standard library only: the decoder here handles 8-bit RGBA PNGs with the
five standard scanline filters, which covers everything this repo renders.
Exit 0 when within tolerance, 1 otherwise (or on any size mismatch).
"""
import struct
import sys
import zlib

MAX_CHANNEL_DIFF = 0
MAX_DIFFERING_PIXELS = 0


def fail(msg: str) -> None:
    print(f"FAIL {msg}")
    sys.exit(1)


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def read_png(path: str):
    """Return ((width, height), pixels) for an 8-bit RGBA PNG."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        fail(f"{path}: not a PNG file")
    pos = 8
    size = None
    idat = bytearray()
    while pos + 8 <= len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        ctype = data[pos + 4:pos + 8]
        payload = data[pos + 8:pos + 8 + length]
        if ctype == b"IHDR":
            width, height, depth, color = struct.unpack(">IIBB", payload[:10])
            size = (width, height, depth, color)
        elif ctype == b"IDAT":
            idat += payload
        elif ctype == b"IEND":
            break
        pos += 12 + length
    if size is None:
        fail(f"{path}: missing IHDR chunk")
    width, height, depth, color = size
    if depth != 8 or color != 6:
        fail(f"{path}: depth {depth} color type {color}, want 8 and 6")
    raw = zlib.decompress(bytes(idat))
    stride = width * 4
    if len(raw) != height * (stride + 1):
        fail(f"{path}: decompressed {len(raw)} bytes, want {height * (stride + 1)}")
    pixels = bytearray(height * stride)
    prev = bytearray(stride)
    for y in range(height):
        base = y * (stride + 1)
        ftype = raw[base]
        line = bytearray(raw[base + 1:base + 1 + stride])
        for i in range(stride):
            a = line[i - 4] if i >= 4 else 0
            b = prev[i]
            c = prev[i - 4] if i >= 4 else 0
            if ftype == 1:
                line[i] = (line[i] + a) & 0xFF
            elif ftype == 2:
                line[i] = (line[i] + b) & 0xFF
            elif ftype == 3:
                line[i] = (line[i] + (a + b) // 2) & 0xFF
            elif ftype == 4:
                line[i] = (line[i] + _paeth(a, b, c)) & 0xFF
        pixels[y * stride:(y + 1) * stride] = line
        prev = line
    return (width, height), bytes(pixels)


def main() -> None:
    (wa, ha), pa = read_png(sys.argv[1])
    (wb, hb), pb = read_png(sys.argv[2])
    if (wa, ha) != (wb, hb):
        fail(f"size {wa}x{ha} != {wb}x{hb}")
    bad = 0
    max_diff = 0
    for i in range(0, len(pa), 4):
        px = 0
        for c in range(4):
            d = abs(pa[i + c] - pb[i + c])
            if d > max_diff:
                max_diff = d
            px = max(px, d)
        if px > 0:
            bad += 1
    if bad > MAX_DIFFERING_PIXELS or max_diff > MAX_CHANNEL_DIFF:
        fail(f"{wa}x{ha}: {bad} differing pixels "
             f"(limit {MAX_DIFFERING_PIXELS}), max channel diff {max_diff} "
             f"(limit {MAX_CHANNEL_DIFF})")
    print(f"ok   {wa}x{ha}: {bad} differing pixels "
          f"(limit {MAX_DIFFERING_PIXELS}), max channel diff {max_diff} "
          f"(limit {MAX_CHANNEL_DIFF})")


if __name__ == "__main__":
    main()
