#!/usr/bin/env python3
"""Build the fixtures for the ips-symbolicate test.

Writes, into one directory:
- crash.ips: a hand-written synthetic report (invented app, invented incident
  id, no device data).
- DemoApp: a minimal thin arm64 Mach-O (LC_SEGMENT_64 __TEXT with __text and
  __data sections, LC_UUID, LC_SYMTAB).
- WrongApp: same shape with a different LC_UUID.
- DemoAppData: DemoApp plus a constant symbol in __data below appfunc.
- SwiftApp: DemoApp with the appfunc symbol named as a Swift mangled string.
- fat-DemoApp: a fat Mach-O with one junk x86 slice and the arm64 DemoApp slice.
- fat2-DemoApp and fat2.ips: a fat file with arm64 and arm64e slices (distinct
  LC_UUIDs), and a report against the arm64e slice.

The Mach-O images are assembled from Python (struct.pack) because no Xcode or
cross linker exists on the Linux test host. Only tools/ips-symbolicate.py reads
them, so a minimal load-command set is enough.
"""
import json
import struct
import sys

UUID_APP = "aabbccdd112233445566778899aabbcc"
UUID_APP2 = "bbccddee112233445566778899aabbcc"
UUID_WRONG = "deadbeefdeadbeefdeadbeefdeadbeef"
TEXT_VM = 0x100000000
S_ATTR_PURE_INSTRUCTIONS = 0x80000000
S_ATTR_SOME_INSTRUCTIONS = 0x00000400
SYMBOLS = [("appstart", 0x0, 1), ("appmain", 0x100, 1), ("appfunc", 0x200, 1)]
# A constant in __data, not in a code section. Its address sits between
# appmain and appfunc, so a resolver that ignores sections reports it.
DATA_SYMBOL = ("appconst", 0x1C0, 2)
SWIFT_SYMBOL = ("$s7DemoApp3runF", 0x200, 1)


def section(name, flags):
    return struct.pack("<16s16sQQIIIIIIII", name, b"__TEXT", TEXT_VM, 0x1000,
                       0, 0, 0, 0, flags, 0, 0, 0)


def thin(uuid_hex, with_symbols=True, extra=None):
    seg = (struct.pack("<II16sQQQQiiII", 0x19, 232, b"__TEXT",
                       TEXT_VM, 0x4000, 0, 0x4000, 7, 5, 2, 0)
           + section(b"__text",
                     S_ATTR_PURE_INSTRUCTIONS | S_ATTR_SOME_INSTRUCTIONS)
           + section(b"__data", 0))
    uuid_cmd = struct.pack("<II", 0x1B, 24) + bytes.fromhex(uuid_hex)
    symoff = 32 + len(seg) + len(uuid_cmd) + 24
    strtab = bytearray(b"\0")
    entries = bytearray()
    syms = list(SYMBOLS) if with_symbols else []
    if extra is not None:
        # A symbol at the same address replaces the stock one (SwiftApp).
        syms = [s for s in syms if s[1] != extra[1]]
        syms.append(extra)
    for name, value, sect in syms:
        entries += struct.pack("<IBBHQ", len(strtab), 0x0F, sect, 0,
                               TEXT_VM + value)
        strtab += name.encode() + b"\0"
    symtab = struct.pack("<IIIIII", 0x2, 24, symoff, len(entries) // 16,
                         symoff + len(entries), len(strtab))
    header = struct.pack("<IiiIIIII", 0xFEEDFACF, 0x0100000C, 0, 2, 3,
                         len(seg) + len(uuid_cmd) + len(symtab), 0, 0)
    return header + seg + uuid_cmd + symtab + entries + strtab


def fat():
    arm = thin(UUID_APP)
    junk = b"\xaa" * 64
    off_junk, off_arm = 0x1000, 0x2000
    out = bytearray(struct.pack(">II", 0xCAFEBABE, 2))
    out += struct.pack(">IIIII", 7, 3, off_junk, len(junk), 12)
    out += struct.pack(">IIIII", 0x0100000C, 0, off_arm, len(arm), 12)
    out += bytes(off_junk - len(out)) + junk
    out += bytes(off_arm - len(out)) + arm
    return bytes(out)


def fat2():
    """One junk x86 slice, one arm64 slice, one arm64e slice (same cputype,
    cpusubtype 2), each arm64-family slice with its own LC_UUID."""
    arm64 = thin(UUID_APP)
    arm64e = thin(UUID_APP2)
    junk = b"\xaa" * 64
    off_junk, off_1, off_2 = 0x1000, 0x2000, 0x3000
    out = bytearray(struct.pack(">II", 0xCAFEBABE, 3))
    out += struct.pack(">IIIII", 7, 3, off_junk, len(junk), 12)
    out += struct.pack(">IIIII", 0x0100000C, 0, off_1, len(arm64), 12)
    out += struct.pack(">IIIII", 0x0100000C, 2, off_2, len(arm64e), 12)
    out += bytes(off_junk - len(out)) + junk
    out += bytes(off_1 - len(out)) + arm64
    out += bytes(off_2 - len(out)) + arm64e
    return bytes(out)


USED_IMAGES = [
    {"name": "DemoApp", "uuid": "AABBCCDD-1122-3344-5566-778899AABBCC",
     "base": 4329488384, "size": 65536, "arch": "arm64",
     "path": "/private/var/containers/Bundle/Application/"
             "11111111-2222-3333-4444-555555555555/DemoApp.app/DemoApp"},
    {"name": "libsystem_kernel.dylib", "uuid": "11223344-5566-7788-99AA-BBCCDDEEFF00",
     "base": 4331000000, "size": 16384, "arch": "arm64",
     "path": "/usr/lib/system/libsystem_kernel.dylib"},
]


def crash_report():
    header = {
        "app_name": "DemoApp", "app_version": "1.2",
        "bundleID": "dev.omarchy.demoapp",
        "os_version": "iOS 27.0.1 (99Z9999)",
        "incident_id": "00000000-1111-2222-3333-444444444444",
        "timestamp": "2026-10-12 12:00:00.00 +0000",
    }
    body = {
        "uptime": 600,
        "exception": {"type": "EXC_BAD_ACCESS", "signal": "SIGSEGV",
                      "subtype": "KERN_INVALID_ADDRESS at 0x0000000000000008"},
        "termination": {"namespace": "SIGNAL", "code": "SIGSEGV",
                        "indicator": "Segmentation fault"},
        "faultingThread": 0,
        "usedImages": USED_IMAGES,
        "threads": [{"triggered": True, "frames": [
            {"imageIndex": 1, "symbol": "mach_msg_trap", "symbolLocation": 8},
            {"imageIndex": 0, "imageOffset": 512},
            {"imageIndex": 0, "imageOffset": 280},
            {"imageIndex": 0, "imageOffset": 488},
        ]}],
        "lastExceptionBacktrace": [
            {"imageIndex": 1, "symbol": "mach_msg_trap", "symbolLocation": 4},
            {"imageIndex": 0, "imageOffset": 512},
        ],
    }
    return json.dumps(header) + "\n" + json.dumps(body) + "\n"


def weird_report():
    """A report with malformed frames: a non-object frame, an out-of-range
    imageIndex, a string imageOffset, and one good frame after them."""
    header = {
        "app_name": "DemoApp", "app_version": "1.2",
        "bundleID": "dev.omarchy.demoapp",
        "os_version": "iOS 27.0.1 (99Z9999)",
        "incident_id": "00000000-1111-2222-3333-444444444444",
    }
    body = {
        "exception": {"type": "EXC_BAD_ACCESS", "signal": "SIGSEGV"},
        "faultingThread": 0,
        "usedImages": USED_IMAGES,
        "threads": [{"triggered": True, "frames": [
            "a string where a frame object belongs",
            {"imageIndex": 99},
            {"imageIndex": 0, "imageOffset": "512"},
            {"imageIndex": 0, "imageOffset": 512},
        ]}],
    }
    return json.dumps(header) + "\n" + json.dumps(body) + "\n"


def fat2_report():
    """A report whose frame belongs to the arm64e slice, the second
    CPU_ARM64 entry in the fat file."""
    header = {
        "app_name": "DemoApp", "app_version": "1.2",
        "bundleID": "dev.omarchy.demoapp",
        "os_version": "iOS 27.0.1 (99Z9999)",
        "incident_id": "22222222-3333-4444-5555-666666666666",
        "timestamp": "2026-10-12 12:00:00.00 +0000",
    }
    body = {
        "faultingThread": 0,
        "usedImages": [
            {"name": "DemoApp", "uuid": "BBCCDDEE-1122-3344-5566-778899AABBCC",
             "base": 4329488384, "size": 65536, "arch": "arm64e",
             "path": "/private/var/containers/Bundle/Application/"
                     "11111111-2222-3333-4444-555555555555/DemoApp.app/DemoApp"},
        ],
        "threads": [{"triggered": True, "frames": [
            {"imageIndex": 0, "imageOffset": 512},
        ]}],
    }
    return json.dumps(header) + "\n" + json.dumps(body) + "\n"


out = sys.argv[1]
open(out + "/crash.ips", "w").write(crash_report())
open(out + "/weird.ips", "w").write(weird_report())
open(out + "/fat2.ips", "w").write(fat2_report())
open(out + "/DemoApp", "wb").write(thin(UUID_APP))
open(out + "/DemoAppData", "wb").write(thin(UUID_APP, extra=DATA_SYMBOL))
open(out + "/SwiftApp", "wb").write(thin(UUID_APP, extra=SWIFT_SYMBOL))
open(out + "/WrongApp", "wb").write(thin(UUID_WRONG))
open(out + "/fat-DemoApp", "wb").write(fat())
open(out + "/fat2-DemoApp", "wb").write(fat2())
print("fixtures written to " + out)
