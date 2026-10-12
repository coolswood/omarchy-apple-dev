# Crash symbolication from Linux

A crashed iOS app leaves an `.ips` report on the phone. Pull the reports to
Linux, then read them without a Mac:

    pymobiledevice3 crash pull ./crashes
    python3 tools/ips-symbolicate.py ./crashes/Report-<date>.ips \
        --binary Payload/App.app/App

Line 1 of the report is a JSON header. The rest is one JSON body. The body
holds the exception, the termination reason, the loaded images, and the
backtraces. The tool prints:

- the app name, version, bundle id, and OS;
- the exception type, signal, and subtype;
- the termination namespace, code, and indicator;
- the faulting thread number;
- each frame of that thread and of `lastExceptionBacktrace`, as
  `image  symbol+offset`.

## Local resolution

A stripped build leaves frames in the app binary without symbols. Pass each
local Mach-O with `--binary`. Repeat the flag for each file. The tool matches
by `LC_UUID`, never by file name. For a fat file it takes the arm64 slice.

A matched frame resolves against the binary's `LC_SYMTAB`. The nearest
preceding function symbol wins. The frame prints as `symbol+delta` and gets
the marker `[resolved locally]`. A frame with no matching binary prints
`[no local binary for <image> <uuid>]`.

## Limits

- No dSYM and no DWARF. There are no source file names and no line numbers.
  Function symbols only.
- The tool reads the modern JSON report form only. An old plain-text report
  exits non-zero with a message.
- A frame resolves at its `imageOffset` as given. There is no return-address
  minus 1 adjustment.
- Swift names stay mangled unless `swift-demangle` is on PATH.
- System library frames rely on the symbols the device already wrote into the
  report. The tool ships no system symbol files.
- The tool reads the report and the given binaries only. The report text goes
  to stdout and errors go to stderr. It creates no files.
