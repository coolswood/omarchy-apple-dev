# Crash symbolication from a pulled .ips report

2026-10-12. `tools/ips-symbolicate.py` is new. It reads a pulled `.ips`
crash report on Linux and prints a readable summary with the backtraces. No
phone and no Mac take part in the reading. `docs/CRASH-SYMBOLICATION.md`
documents the pull, the flags, and the limits.

The tool parses the JSON header and the JSON body. It prints the app,
version, OS, exception, and termination. It picks the faulting thread. Each
frame of that thread and of `lastExceptionBacktrace` prints as
`image  symbol+offset`. A frame without a device symbol resolves against a
local Mach-O given with `--binary`. The match key is `LC_UUID`, not the file
name. The resolution is the nearest preceding `LC_SYMTAB` function symbol.
It prints as `symbol+delta` with the marker `[resolved locally]`. The arm64
slice of a fat file is selected by cputype. Bad input exits non-zero with a
message. The tool writes to stdout and stderr and creates no files.

## Failing first

The test suite ran before the tool existed:

    $ bash tests/ips-symbolicate/run.sh
    FAIL tools/ips-symbolicate.py does not exist
    rc=1

## Passing

The same suite after the tool landed. The fixtures are synthetic. The app is
invented. The incident id and the OS build string are invented. The Mach-O
files are assembled with `struct.pack` from Python. No Xcode or cross linker
exists on the Linux test host.

    $ bash tests/ips-symbolicate/run.sh
    ok   exit 0 on a valid report
    ok   summary line: App: DemoApp 1.2 (dev.omarchy.demoapp)
    ok   summary line: OS: iOS 27.0.1 (99Z9999)
    ok   summary line: Exception: EXC_BAD_ACCESS (SIGSEGV) KERN_INVALID_ADDRESS at 0x0000000000000008
    ok   summary line: Termination: SIGNAL SIGSEGV (Segmentation fault)
    ok   summary line: Faulting thread: 0 of 1
    ok   stripped frame resolves via LC_UUID match
    ok   second stripped frame resolves
    ok   row appears in faulting thread and last exception backtrace
    ok   device symbol kept on system frame
    ok   last exception device symbol kept
    ok   no stderr noise on success
    ok   wrong binary does not resolve the frame
    ok   no local binary line names image and UUID
    ok   truncated body exits non-zero with a JSON message
    ok   non-JSON header exits non-zero with a JSON message
    ok   fat file: arm64 slice used
    ok   exit 0 on malformed frames
    ok   non-object frame renders a note
    ok   non-integer imageOffset renders a note
    ok   good frame after malformed ones still resolves
    ok   duplicate LC_UUID warns on stderr
    ok   resolution still works after duplicate warning
    ok   mutation 1 (off-by-one nearest symbol) breaks the resolution row
    ok   mutation 2 (wrong image) breaks the resolution row
    tests/ips-symbolicate: all checks passed
    rc=0

The two mutation checks edit a copy of the tool inside the test run. One
moves the nearest-symbol comparison from `<=` to `<`. The delta zero frame
then prints `appmain+0x100` instead of `appfunc+0x0`, and the row fails. The
other breaks the UUID lookup. Every local resolution then turns into the
no-local-binary line, and the row fails. The full suite passes too:

    $ bash tests/run.sh
    tests/run.sh: all checks passed

## Review follow-ups

The reviewer asked for four changes. Each got a failing first run and then a
pass.

A frame of the wrong type raised a raw traceback before the fix:

    $ python3 tools/ips-symbolicate.py weird.ips --binary DemoApp
      File "tools/ips-symbolicate.py", line 99, in resolve
        idx = frame.get("imageIndex")
    AttributeError: 'str' object has no attribute 'get'
    rc=1

The new rows failed before the fix and pass after it:

    FAIL exit 0 on malformed frames
    FAIL non-object frame renders a note
    FAIL non-integer imageOffset renders a note
    FAIL duplicate LC_UUID warns on stderr

    ok   exit 0 on malformed frames
    ok   non-object frame renders a note
    ok   non-integer imageOffset renders a note
    ok   good frame after malformed ones still resolves
    ok   duplicate LC_UUID warns on stderr
    ok   resolution still works after duplicate warning

A non-object frame, a non-integer `imageOffset`, and an out-of-range
`imageIndex` now render as short notes on stdout. Deeply nested JSON exits
with the plain JSON error. It no longer raises a traceback. A second
`--binary` with a `LC_UUID` already seen warns on stderr. The tool keeps the
first file. The invented fixture build string is now `99Z9999`. The docs and
the tool help state the input limits. The tool reads the modern JSON report
form only. Frames resolve at `imageOffset` as given. There is no
return-address minus 1 adjustment.

## Real-format check

Six stored real `.ips` reports from an earlier lane of the private lab
notebook parsed with exit code 0. Their frames carried device symbols. The
frames rendered directly, so the local resolution path did not run on them.
No report content went into this file. The five RNProbe crash reports were
not available. The machine that holds them is offline, and the notebook keeps
only summaries of them. The tool has not run on those five.

## Not checked

- The five real RNProbe reports never ran through the tool.
- No local app binary was resolved against a real report. The real reports
  carried device symbols.
- dSYM files, DWARF line information, and `swift-demangle` output were not
  exercised. The docs describe them as limits.
- Fat binaries with an arm64e slice and 32-bit Mach-O files were not tested.
