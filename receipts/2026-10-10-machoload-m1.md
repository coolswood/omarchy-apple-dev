# M1: an arm64 Mach-O hello runs on Linux through our loader

2026-10-10. `machoload/` on branch `machoload-m1`: a freestanding arm64
Linux loader for iOS Mach-O executables built by the no-xcode toolchain.

## What ran

On the build container (Linux x64), under `qemu-aarch64-static`:

```sh
qemu-aarch64-static machoload/.build/loader machoload/.build/Hello
Hello from an iOS Mach-O on Linux
exit 0
```

The pair: `machoload/.build/loader` (ELF 64-bit ARM aarch64, statically
linked) and `machoload/.build/Hello` (Mach-O 64-bit arm64, MH_EXECUTE,
platform iOS 17.0, linked with `ld64.lld -undefined dynamic_lookup
-no_fixup_chains`). The hello calls `puts`, `getpid`, `clock_gettime`,
`memcpy`, `memset`; all five are undefined in the binary and the loader
binds each by name before the entry runs (an unresolved name stops the
load with the name on stderr, and the hello self-checks the resolved
results before printing).

## How the loader works

- Maps each `LC_SEGMENT_64` at its link-time vmaddr, copies the file
  bytes, and restores initprot after binding. No slide, so no rebases.
- Interprets the classic dyld bind and lazy-bind opcode streams
  (`llvm/BinaryFormat/MachO.h` opcode table) and writes resolved Linux
  addresses into `__got` and `__la_symbol_ptr` slots; stubs then work
  untouched.
- Entry from `LC_MAIN` (`__TEXT` vmaddr + entryoff), called with
  argc/argv/envp from the Linux initial stack.

## Native aarch64 run

2026-10-11, native run on an M1 Max laptop running Linux (kernel
`7.1.12-2-12.6-sep-ARCH`, `uname -m` = `aarch64`), CPU only, `nice -n 19`, no emulator:

```sh
$ sha256sum loader Hello      # same prefixes as sha256sum printed on the build container before the copy
8a89701176c50b549f2e...  loader
c897c05d4f7f8c89d031...  Hello
$ ./loader ./Hello
Hello from an iOS Mach-O on Linux
$ echo $?
0
```

A second run, `./loader ./Hello >/dev/null; echo $?`, printed `0`. The two files are the pair staged on 2026-10-10 from the M1 build; the hashes above are
the first 20 hex digits of each. They were copied to `/tmp` on the laptop for the run and deleted afterwards. A rebuild
from main on the build container failed on that host's `ld64.lld` ("does not support linking for platform iOS"), so the
pair was not rebuilt from the merged sources and the hashes were not compared to a fresh build.

## Not in this step

Objective-C and Swift: they need an objc4 / Swift core port before any
loader work pays off, so the loader proves C first (machoload/README.md
lists the limits: no rebases needed, no chained fixups, no TLS).
