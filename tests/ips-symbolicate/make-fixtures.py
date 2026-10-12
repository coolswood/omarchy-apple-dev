#!/usr/bin/env python3
"""Build the fixtures for the ips-symbolicate test.

Writes, into one directory:
- crash.ips: a hand-written synthetic report (invented app, invented incident
  id, no device data).
- DemoApp: a minimal thin arm64 Mach-O (LC_SEGMENT_64 __TEXT, LC_UUID, LC_SYMTAB).
- WrongApp: same shape with a different LC_UUID.
- fat-DemoApp: a fat Mach-O with one junk x86 slice and the arm64 DemoApp slice.

The Mach-O images are assembled from Python (struct.pack) because no Xcode or
cross linker exists on the Linux test host. Only tools/ips-symbolicate.py reads
them, so a minimal load-command set is enough.
"""
import json
import struct
import sys

UUID_APP = "aabbccdd112233445566778899aabbcc"
UUID_WRONG = "deadbeefdeadbeefdeadbeefdeadbeef"
TEXT_VM = 0x100000000
SYMBOLS = [("appstart", 0x0), ("appmain", 0x100), ("appfunc", 0x200)]


def thin(uuid_hex, with_symbols=True):
    seg = struct.pack("<II16sQQQQiiII", 0x19, 72, b"__TEXT",
                      TEXT_VM, 0x4000, 0, 0x4000, 7, 5, 0, 0)
    uuid_cmd = struct.pack("<II", 0x1B, 24) + bytes.fromhex(uuid_hex)
    symoff = 32 + len(seg) + len(uuid_cmd) + 24
    strtab = bytearray(b"\0")
    entries = bytearray()
    for name, value in (SYMBOLS if with_symbols else []):
        entries += struct.pack("<IBBHQ", len(strtab), 0x0F, 1, 0, TEXT_VM + value)
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


def crash_report():
    header = {
        "app_name": "DemoApp", "app_version": "1.2",
        "bundleID": "dev.omarchy.demoapp",
        "os_version": "iOS 27.0.1 (24A446)",
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
        "usedImages": [
            {"name": "DemoApp", "uuid": "AABBCCDD-1122-3344-5566-778899AABBCC",
             "base": 4329488384, "size": 65536, "arch": "arm64",
             "path": "/private/var/containers/Bundle/Application/"
                     "11111111-2222-3333-4444-555555555555/DemoApp.app/DemoApp"},
            {"name": "libsystem_kernel.dylib", "uuid": "11223344-5566-7788-99AA-BBCCDDEEFF00",
             "base": 4331000000, "size": 16384, "arch": "arm64",
             "path": "/usr/lib/system/libsystem_kernel.dylib"},
        ],
        "threads": [{"triggered": True, "frames": [
            {"imageIndex": 1, "symbol": "mach_msg_trap", "symbolLocation": 8},
            {"imageIndex": 0, "imageOffset": 512},
            {"imageIndex": 0, "imageOffset": 280},
        ]}],
        "lastExceptionBacktrace": [
            {"imageIndex": 1, "symbol": "mach_msg_trap", "symbolLocation": 4},
            {"imageIndex": 0, "imageOffset": 512},
        ],
    }
    return json.dumps(header) + "\n" + json.dumps(body) + "\n"


out = sys.argv[1]
open(out + "/crash.ips", "w").write(crash_report())
open(out + "/DemoApp", "wb").write(thin(UUID_APP))
open(out + "/WrongApp", "wb").write(thin(UUID_WRONG))
open(out + "/fat-DemoApp", "wb").write(fat())
print("fixtures written to " + out)
