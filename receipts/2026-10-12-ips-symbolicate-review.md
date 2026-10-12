# Review fixes for ips-symbolicate

2026-10-12. Four review comments on the merged symbolication PR got fixes.
The work is one commit. The fixtures are synthetic. The app, the incident
ids, and the UUIDs are invented. No phone and no Mac take part.

The fixes:

1. Frames resolve only against symbols in sections flagged as holding
   machine instructions. The flags are S_ATTR_PURE_INSTRUCTIONS and
   S_ATTR_SOME_INSTRUCTIONS. STAB entries are dropped. `N_SECT` alone no
   longer makes a data symbol a candidate.
2. A fat file can carry arm64 and arm64e slices. Both share cputype
   `CPU_ARM64`. They differ in cpusubtype. The tool now returns every arm64
   slice and matches the report UUID against each slice's own.
3. `swift-demangle` output is cached per distinct name in the process. A
   missing demangler still passes mangled names through.
4. The bare `open()` calls in the fixture builder stayed as they are. The
   smallest honest fix wraps five statements. A helper adds five call sites.
   Both exceed the two-line budget set for this suggestion.

## Failing first

New fixtures first: a `__text` and a `__data` section, a constant symbol in
`__data` between `appmain` and `appfunc`, a fat file with arm64 and arm64e
slices, and a stub `swift-demangle` that counts its calls. The tool was
still at the merged state:

    $ bash tests/ips-symbolicate/run.sh
    FAIL data symbol in __data skipped, nearest function resolves
    FAIL data symbol name never reported
    FAIL fat file: frame resolves against the second arm64 slice
    ok   mangled symbol resolves through the stub demangler
    FAIL same mangled symbol demangles exactly once
    ok   absent swift-demangle keeps the mangled name
    FAIL mutation 5 (no cache) breaks the single-call row
    rc=1

The old tool printed the wrong answers named in the two P2 comments:

    $ python3 tools/ips-symbolicate.py crash.ips --binary DemoAppData
      3  DemoApp  appconst+0x28 [resolved locally]

    $ python3 tools/ips-symbolicate.py fat2.ips --binary fat2-DemoApp
      0  DemoApp  [no local binary for DemoApp BBCCDDEE-1122-3344-5566-778899AABBCC]

## Passing

After the tool fix, the new rows:

    $ bash tests/ips-symbolicate/run.sh
    ok   data symbol in __data skipped, nearest function resolves
    ok   data symbol name never reported
    ok   fat file: frame resolves against the second arm64 slice
    ok   mangled symbol resolves through the stub demangler
    ok   unmangled neighbor still resolves beside the mangled one
    ok   same mangled symbol demangles exactly once
    ok   absent swift-demangle keeps the mangled name
    ok   mutation 3 (data symbol accepted) breaks the data-symbol row
    ok   mutation 4 (first slice only) breaks the second-slice row
    ok   mutation 5 (no cache) breaks the single-call row
    tests/ips-symbolicate: all checks passed

The 25 pre-existing rows stay green. The whole repo suite on a Swift-less
Linux host:

    $ bash tests/run.sh
    tests/run.sh: all checks passed

Each new row has one mutation check. Mutation 3 reverts the section filter.
The data symbol then comes back. Mutation 4 matches only the first arm64
slice. Mutation 5 skips the demangle cache; the stub then counts two calls.

## Not checked

- No real device report ran through the changed tool. The evidence comes
  from synthetic fixtures only.
- No binary from a real toolchain was parsed. The section flag handling is
  checked against hand-packed sections only.
- The cache holds decoded output per process. No report with hundreds of
  distinct Swift symbols was measured.
- The arm64e fixture uses cpusubtype 2. No real arm64e binary was parsed.
