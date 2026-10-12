#!/usr/bin/env bash
# Test for tools/ips-symbolicate.py on synthetic data only.
# Builds a hand-written .ips report and minimal Python-assembled arm64 Mach-O
# fixtures, then checks: summary lines, local resolution by LC_UUID, the
# mismatch message, bad-file exit codes, fat slice selection, skipping of
# data and STAB symbols, matching every arm64 slice of a fat file, single
# spawn of swift-demangle per distinct symbol, and five mutation checks.
set -uo pipefail
here=$(dirname "$(readlink -f "$0")")
repo=$here/../..
tool=$repo/tools/ips-symbolicate.py
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
row() { if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

if [ ! -f "$tool" ]; then
  echo "FAIL tools/ips-symbolicate.py does not exist"
  exit 1
fi

python3 "$here/make-fixtures.py" "$tmp" >/dev/null || { echo "FAIL fixtures"; exit 1; }

# 1. Summary and frames with both binaries present.
python3 "$tool" "$tmp/crash.ips" --binary "$tmp/DemoApp" --binary "$tmp/WrongApp" \
  >"$tmp/out.txt" 2>"$tmp/err.txt"
rc=$?
row "exit 0 on a valid report" "$rc"
for want in \
  "App: DemoApp 1.2 (dev.omarchy.demoapp)" \
  "OS: iOS 27.0.1 (99Z9999)" \
  "Exception: EXC_BAD_ACCESS (SIGSEGV) KERN_INVALID_ADDRESS at 0x0000000000000008" \
  "Termination: SIGNAL SIGSEGV (Segmentation fault)" \
  "Faulting thread: 0 of 1"; do
  grep -qxF "$want" "$tmp/out.txt"
  row "summary line: $want" $?
done
grep -qxF "  1  DemoApp  appfunc+0x0 [resolved locally]" "$tmp/out.txt"
row "stripped frame resolves via LC_UUID match" $?
grep -qxF "  2  DemoApp  appmain+0x18 [resolved locally]" "$tmp/out.txt"
row "second stripped frame resolves" $?
[ "$(grep -cxF "  1  DemoApp  appfunc+0x0 [resolved locally]" "$tmp/out.txt")" -eq 2 ]
row "row appears in faulting thread and last exception backtrace" $?
grep -qxF "  0  libsystem_kernel.dylib  mach_msg_trap+8" "$tmp/out.txt"
row "device symbol kept on system frame" $?
grep -qxF "  0  libsystem_kernel.dylib  mach_msg_trap+4" "$tmp/out.txt"
row "last exception device symbol kept" $?
[ ! -s "$tmp/err.txt" ]
row "no stderr noise on success" $?

# 2. Only a binary with the wrong UUID: no local binary line, no local symbol.
python3 "$tool" "$tmp/crash.ips" --binary "$tmp/WrongApp" >"$tmp/out2.txt" 2>/dev/null
if grep -qxF "  1  DemoApp  appfunc+0x0 [resolved locally]" "$tmp/out2.txt"; then
  row "wrong binary does not resolve the frame" 1
else
  row "wrong binary does not resolve the frame" 0
fi
grep -qF "[no local binary for DemoApp AABBCCDD-1122-3344-5566-778899AABBCC]" "$tmp/out2.txt"
row "no local binary line names image and UUID" $?

# 3. Truncated and non-JSON files exit non-zero with a clear message.
printf '%s\n' '{"app_name":"DemoApp"}' >"$tmp/truncated.ips"
python3 "$tool" "$tmp/truncated.ips" >"$tmp/t.out" 2>"$tmp/t.err"
[ $? -ne 0 ] && grep -qi "json" "$tmp/t.err" "$tmp/t.out"
row "truncated body exits non-zero with a JSON message" $?
printf 'not json at all\n' >"$tmp/nonjson.ips"
python3 "$tool" "$tmp/nonjson.ips" >"$tmp/t.out" 2>"$tmp/t.err"
[ $? -ne 0 ] && grep -qi "json" "$tmp/t.err" "$tmp/t.out"
row "non-JSON header exits non-zero with a JSON message" $?

# 4. The arm64 slice of a fat Mach-O is chosen by cputype.
python3 "$tool" "$tmp/crash.ips" --binary "$tmp/fat-DemoApp" >"$tmp/out3.txt" 2>/dev/null
grep -qxF "  1  DemoApp  appfunc+0x0 [resolved locally]" "$tmp/out3.txt"
row "fat file: arm64 slice used" $?

# 5. Malformed frames render as notes instead of a traceback.
python3 "$tool" "$tmp/weird.ips" --binary "$tmp/DemoApp" \
  >"$tmp/out4.txt" 2>"$tmp/err4.txt"
row "exit 0 on malformed frames" $?
grep -qxF "  0  [unreadable frame]" "$tmp/out4.txt"
row "non-object frame renders a note" $?
grep -qxF "  2  DemoApp  [unreadable imageOffset]" "$tmp/out4.txt"
row "non-integer imageOffset renders a note" $?
grep -qxF "  3  DemoApp  appfunc+0x0 [resolved locally]" "$tmp/out4.txt"
row "good frame after malformed ones still resolves" $?

# 6. Two --binary files with one LC_UUID: stderr warning, first file kept.
python3 "$tool" "$tmp/crash.ips" --binary "$tmp/DemoApp" --binary "$tmp/DemoApp" \
  >"$tmp/out5.txt" 2>"$tmp/err5.txt"
grep -q "LC_UUID aabbccdd112233445566778899aabbcc already covered by an earlier --binary" "$tmp/err5.txt"
row "duplicate LC_UUID warns on stderr" $?
grep -qxF "  1  DemoApp  appfunc+0x0 [resolved locally]" "$tmp/out5.txt"
row "resolution still works after duplicate warning" $?

# 7. Mutation checks: each must make a passing row fail.
mutate() {
  python3 - "$@" <<'PY'
import sys
path, old, new = sys.argv[1:4]
text = open(path).read()
assert text.count(old) == 1, "mutation anchor not unique: " + repr(old)
open(path, "w").write(text.replace(old, new))
PY
}

# 5a. Off-by-one in the nearest-symbol search.
cp "$tool" "$tmp/mut1.py"
mutate "$tmp/mut1.py" "if val <= off:" "if val < off:"
python3 "$tmp/mut1.py" "$tmp/crash.ips" --binary "$tmp/DemoApp" >"$tmp/mut1.txt" 2>/dev/null
if ! grep -qxF "  1  DemoApp  appfunc+0x0 [resolved locally]" "$tmp/mut1.txt" \
   && grep -qxF "  1  DemoApp  appmain+0x100 [resolved locally]" "$tmp/mut1.txt"; then
  row "mutation 1 (off-by-one nearest symbol) breaks the resolution row" 0
else
  row "mutation 1 (off-by-one nearest symbol) breaks the resolution row" 1
fi

# 5b. Resolve against the wrong image.
cp "$tool" "$tmp/mut2.py"
mutate "$tmp/mut2.py" "b = bins.get(want)" 'b = bins.get(want + "x")'
python3 "$tmp/mut2.py" "$tmp/crash.ips" --binary "$tmp/DemoApp" >"$tmp/mut2.txt" 2>/dev/null
if ! grep -q "resolved locally" "$tmp/mut2.txt" \
   && grep -qF "[no local binary for DemoApp AABBCCDD-1122-3344-5566-778899AABBCC]" "$tmp/mut2.txt"; then
  row "mutation 2 (wrong image) breaks the resolution row" 0
else
  row "mutation 2 (wrong image) breaks the resolution row" 1
fi

# 8. A data symbol below the frame is not a resolve candidate. The frame sits
# between appmain (0x100) and the __data constant appconst (0x1c0); only the
# function may win.
python3 "$tool" "$tmp/crash.ips" --binary "$tmp/DemoAppData" >"$tmp/out6.txt" 2>/dev/null
grep -qxF "  3  DemoApp  appmain+0xe8 [resolved locally]" "$tmp/out6.txt"
row "data symbol in __data skipped, nearest function resolves" $?
if grep -q "appconst" "$tmp/out6.txt"; then r=1; else r=0; fi
row "data symbol name never reported" $r

# 9. A fat file with arm64 and arm64e slices: both LC_UUIDs are searchable.
python3 "$tool" "$tmp/fat2.ips" --binary "$tmp/fat2-DemoApp" >"$tmp/out7.txt" 2>/dev/null
grep -qxF "  0  DemoApp  appfunc+0x0 [resolved locally]" "$tmp/out7.txt"
row "fat file: frame resolves against the second arm64 slice" $?

# 11. maxprot is below nsects. The frame sits in the third code section.
# Reading nsects from the maxprot slot drops that section, so the frame
# resolves to an earlier function plus a large delta.
python3 "$tool" "$tmp/maxprot.ips" --binary "$tmp/DemoAppMaxprot" \
  >"$tmp/out10.txt" 2>/dev/null
grep -qxF "  0  DemoApp  func3+0x0 [resolved locally]" "$tmp/out10.txt"
row "third section kept when maxprot is below nsects" $?


# 10. swift-demangle runs once per distinct symbol; absent demangler passes
# the mangled name through.
mkdir "$tmp/bin"
printf '#!/bin/sh\necho ran >> "$DEMCOUNT"\ncat\n' >"$tmp/bin/swift-demangle"
chmod +x "$tmp/bin/swift-demangle"
python3_bin=$(command -v python3)
DEMCOUNT="$tmp/demcount" PATH="$tmp/bin:$PATH" \
  python3 "$tool" "$tmp/crash.ips" --binary "$tmp/SwiftApp" >"$tmp/out8.txt" 2>/dev/null
grep -qxF '  1  DemoApp  $s7DemoApp3runF+0x0 [resolved locally]' "$tmp/out8.txt"
row "mangled symbol resolves through the stub demangler" $?
grep -qxF '  3  DemoApp  appmain+0xe8 [resolved locally]' "$tmp/out8.txt"
row "unmangled neighbor still resolves beside the mangled one" $?
[ -f "$tmp/demcount" ] && [ "$(wc -l <"$tmp/demcount")" -eq 1 ]
row "same mangled symbol demangles exactly once" $?
PATH=/usr/bin:/bin "$python3_bin" "$tool" "$tmp/crash.ips" \
  --binary "$tmp/SwiftApp" >"$tmp/out9.txt" 2>/dev/null
grep -qxF '  1  DemoApp  $s7DemoApp3runF+0x0 [resolved locally]' "$tmp/out9.txt"
row "absent swift-demangle keeps the mangled name" $?

# 7c. Mutation: accept every sectioned symbol (the old behavior).
cp "$tool" "$tmp/mut3.py"
mutate "$tmp/mut3.py" \
  "or not sections[n_sect - 1] & EXE_SECTION_FLAGS:" "or not n_value:"
python3 "$tmp/mut3.py" "$tmp/crash.ips" --binary "$tmp/DemoAppData" \
  >"$tmp/mut3.txt" 2>/dev/null
if grep -q "appconst" "$tmp/mut3.txt" \
   && ! grep -qxF "  3  DemoApp  appmain+0xe8 [resolved locally]" "$tmp/mut3.txt"; then
  row "mutation 3 (data symbol accepted) breaks the data-symbol row" 0
else
  row "mutation 3 (data symbol accepted) breaks the data-symbol row" 1
fi

# 7d. Mutation: match only the first arm64 slice.
cp "$tool" "$tmp/mut4.py"
mutate "$tmp/mut4.py" "for uuid, syms in results:" "for uuid, syms in results[:1]:"
python3 "$tmp/mut4.py" "$tmp/fat2.ips" --binary "$tmp/fat2-DemoApp" \
  >"$tmp/mut4.txt" 2>/dev/null
if grep -qF "[no local binary for DemoApp BBCCDDEE-1122-3344-5566-778899AABBCC]" "$tmp/mut4.txt" \
   && ! grep -q "resolved locally" "$tmp/mut4.txt"; then
  row "mutation 4 (first slice only) breaks the second-slice row" 0
else
  row "mutation 4 (first slice only) breaks the second-slice row" 1
fi

# 7e. Mutation: skip the demangle cache.
cp "$tool" "$tmp/mut5.py"
mutate "$tmp/mut5.py" "hit = _demangle_cache.get(name)" "hit = None"
DEMCOUNT="$tmp/demcount2" PATH="$tmp/bin:$PATH" \
  python3 "$tmp/mut5.py" "$tmp/crash.ips" --binary "$tmp/SwiftApp" \
  >"$tmp/mut5.txt" 2>/dev/null
[ -f "$tmp/demcount2" ] && [ "$(wc -l <"$tmp/demcount2")" -eq 2 ]
row "mutation 5 (no cache) breaks the single-call row" $?

# 7f. Mutation: read nsects from the maxprot slot (the old offset).
cp "$tool" "$tmp/mut6.py"
mutate "$tmp/mut6.py" "data, off + 64" "data, off + 56"
python3 "$tmp/mut6.py" "$tmp/maxprot.ips" --binary "$tmp/DemoAppMaxprot" \
  >"$tmp/mut6.txt" 2>/dev/null
if grep -qxF "  0  DemoApp  func1+0x2000 [resolved locally]" "$tmp/mut6.txt" \
   && ! grep -q "func3" "$tmp/mut6.txt"; then
  row "mutation 6 (nsects from maxprot) breaks the third-section row" 0
else
  row "mutation 6 (nsects from maxprot) breaks the third-section row" 1
fi


[ "$fail" -eq 0 ] && echo "tests/ips-symbolicate: all checks passed"
exit "$fail"
