#!/usr/bin/env bash
# M6 checks key records, text insertion, focus on tap, blur, drop warnings,
# return behavior and mutations. Expected results: simview/TESTS-M6.md.
set -uo pipefail
here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
if command -v swiftc >/dev/null 2>&1; then
  P=$(cd "$here/.." && pwd)
  run() { "$@"; }
elif [ -n "${SIMVIEW_CHROOT_RUN:-}" ]; then
  P=/work
  run() { "$SIMVIEW_CHROOT_RUN" --user "$*"; }
else
  echo "SKIP  simview/test-m6.sh: no swiftc and no SIMVIEW_CHROOT_RUN wrapper"
  exit 0
fi
bash "$here/build.sh" || exit 1
bh=$here/build
b=$P/simview/build
mkdir -p "$bh"
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
run_frames() { run "$P/keysdemo" --frames "$1" --out "$2"; }
gc() { python3 "$here/compare.py" "$2" "$here/golden/$1" >/dev/null; }

run swiftc -swift-version 5 -parse-as-library -I "$b" \
  -o "$P/keysdemo" \
  "$b/SwiftUI.o" "$P/simview/Sources/KeysDemo/KeysDemo.swift" || {
  echo "FAIL keysdemo did not build"; exit 1; }

cat > "$bh/probe6.json" <<'EOF'
[{"t_ms":0,"fingers":[{"finger":0,"phase":"stationary","x":1,"y":1}]}]
EOF
run_frames "$b/probe6.json" "$b/probe6.png" >"$bh/probe6.log" 2>&1 || exit 1
f1=$(grep '^field id=1 ' "$bh/probe6.log" | head -1 | sed 's/.*rect=//')
f2=$(grep '^field id=2 ' "$bh/probe6.log" | head -1 | sed 's/.*rect=//')
[ -n "$f1" ] && [ -n "$f2" ] || { echo "FAIL no field rects in probe log"; exit 1; }
read -r x1 y1 w1 h1 <<<"$(echo "$f1" | tr ',' ' ')"
read -r x2 y2 w2 h2 <<<"$(echo "$f2" | tr ',' ' ')"
fx1=$((x1 + w1 / 2)); fy1=$((y1 + h1 / 2))
fx2=$((x2 + w2 / 2)); fy2=$((y2 + h2 / 2))

cat > "$bh/empty6.json" <<'EOF'
[]
EOF
run_frames "$b/empty6.json" "$b/root6.png" >"$bh/root6.log" 2>&1
cat > "$bh/focus6.json" <<EOF
[{"tap":[$fx1,$fy1]}]
EOF
run_frames "$b/focus6.json" "$b/focus6.png" >"$bh/focus6.log" 2>&1
cat > "$bh/hi6.json" <<EOF
[{"tap":[$fx1,$fy1]},
 {"t_ms":200,"text":"H"},
 {"t_ms":220,"text":"i"}]
EOF
run_frames "$b/hi6.json" "$b/hi6.png" >"$bh/hi6.log" 2>&1
cat > "$bh/hey6.json" <<EOF
[{"tap":[$fx1,$fy1]},
 {"t_ms":200,"text":"H"},
 {"t_ms":220,"text":"i"},
 {"t_ms":240,"key":42},
 {"t_ms":260,"text":"e"},
 {"t_ms":280,"text":"y"}]
EOF
run_frames "$b/hey6.json" "$b/hey6.png" >"$bh/hey6.log" 2>&1
cat > "$bh/blur6.json" <<EOF
[{"tap":[$fx1,$fy1]},
 {"t_ms":200,"text":"A"},
 {"tap":[300,700]},
 {"t_ms":500,"text":"x"}]
EOF
run_frames "$b/blur6.json" "$b/blur6.png" >"$bh/blur6.log" 2>&1
cat > "$bh/two6.json" <<EOF
[{"tap":[$fx1,$fy1]},
 {"t_ms":200,"text":"H"},
 {"t_ms":220,"text":"i"},
 {"tap":[$fx2,$fy2]},
 {"t_ms":500,"text":"o"},
 {"t_ms":520,"text":"k"}]
EOF
run_frames "$b/two6.json" "$b/two6.png" >"$bh/two6.log" 2>&1
cat > "$bh/return6.json" <<EOF
[{"tap":[$fx1,$fy1]},
 {"t_ms":200,"text":"H"},
 {"t_ms":220,"text":"i"},
 {"t_ms":240,"key":40},
 {"t_ms":400,"text":"x"}]
EOF
run_frames "$b/return6.json" "$b/return6.png" >"$bh/return6.log" 2>&1
cat > "$bh/nofocus6.json" <<'EOF'
[{"t_ms":0,"key":42},
 {"t_ms":100,"text":"q"}]
EOF
run_frames "$b/nofocus6.json" "$b/nofocus6.png" >"$bh/nofocus6.log" 2>&1
cat > "$bh/cancel6.json" <<EOF
[{"tap":[$fx1,$fy1]},
 {"t_ms":200,"text":"A"},
 {"t_ms":300,"fingers":[{"finger":0,"phase":"began","x":$fx2,"y":$fy2}]},
 {"t_ms":350,"fingers":[{"finger":0,"phase":"cancelled","x":$fx2,"y":$fy2}]},
 {"t_ms":400,"text":"B"}]
EOF
run_frames "$b/cancel6.json" "$b/cancel6.png" >"$bh/cancel6.log" 2>&1
cat > "$bh/demo6.json" <<EOF
[{"tap":[$fx1,$fy1]},
 {"t_ms":200,"text":"H"},
 {"t_ms":220,"text":"i"},
 {"t_ms":240,"key":42},
 {"t_ms":260,"text":"e"},
 {"t_ms":280,"text":"y"},
 {"tap":[$fx2,$fy2]},
 {"t_ms":600,"text":"o"},
 {"t_ms":620,"text":"k"},
 {"t_ms":640,"key":40}]
EOF
run_frames "$b/demo6.json" "$b/demo6.png" >"$bh/demo6.log" 2>&1

if gc keys-root.png "$bh/root6.png"; then ok "row 0 root render"; else bad "row 0 root render"; fi
if grep -q 'target=Field#1' "$bh/focus6.log" && gc keys-focus1.png "$bh/focus6.png"; then
  ok "row 1 tap focuses field one"; else bad "row 1 tap focuses field one"; fi
if grep -q 'state=first:Hi,second:' "$bh/hi6.log" && gc keys-hi.png "$bh/hi6.png"; then
  ok "row 2 typed characters append"; else bad "row 2 typed characters append"; fi
if grep -q 'state=first:Hey,second:' "$bh/hey6.log" && gc keys-hey.png "$bh/hey6.png"; then
  ok "row 3 backspace removes one and stops at empty"; else bad "row 3 backspace"; fi
if grep -q 'warning: text x dropped (no focus)' "$bh/blur6.log" \
  && grep -q 'text=x field=none state=first:A,second:' "$bh/blur6.log" \
  && gc keys-blurred.png "$bh/blur6.png"; then
  ok "row 4 tap elsewhere blurs and drops keys"; else bad "row 4 blur"; fi
if grep -q 'state=first:Hi,second:ok' "$bh/two6.log" && gc keys-two.png "$bh/two6.png"; then
  ok "row 5 two fields keep separate text"; else bad "row 5 two fields"; fi
if grep -q 'text=x field=none state=first:Hi,second:,echo:Hi' "$bh/return6.log" \
  && grep -q 'warning: text x dropped (no focus)' "$bh/return6.log" \
  && gc keys-echo.png "$bh/return6.png"; then
  ok "row 6 return fires onSubmit and blurs"; else bad "row 6 return"; fi
if grep -q 'warning: key 42 dropped (no focus)' "$bh/nofocus6.log" \
  && grep -q 'warning: text q dropped (no focus)' "$bh/nofocus6.log" \
  && grep -q 'state=first:,second:,echo:' "$bh/nofocus6.log" \
  && cmp -s "$bh/nofocus6.png" "$bh/root6.png"; then
  ok "row 7 keys without focus are dropped with a warning"; else bad "row 7 drop"; fi
if grep -q 'state=first:AB,second:' "$bh/cancel6.log" && gc keys-cancel.png "$bh/cancel6.png"; then
  ok "row 8 cancelled tap does not focus"; else bad "row 8 cancelled tap"; fi
if grep -q 'state=first:Hey,second:ok,echo:' "$bh/demo6.log" && gc keys-demo.png "$bh/demo6.png"; then
  ok "row 9 demo flow"; else bad "row 9 demo flow"; fi
run_frames "$b/demo6.json" "$b/demo6-again.png" >"$bh/demo6-again.log" 2>&1
grep -v '^wrote ' "$bh/demo6.log" >"$bh/demo6.cmp"
grep -v '^wrote ' "$bh/demo6-again.log" >"$bh/demo6-again.cmp"
if cmp -s "$bh/demo6.cmp" "$bh/demo6-again.cmp" && cmp -s "$bh/demo6.png" "$bh/demo6-again.png"; then
  ok "row 10 deterministic log and PNG"; else bad "row 10 determinism"; fi

mutant() {
  name=$1 old=$2 new=$3 frames=$4 check=$5
  src="$bh/mut-$name.swift"
  python3 - "$here/Sources/SwiftUI/SwiftUI.swift" "$src" "$old" "$new" <<'PY'
import sys
source, target, old, new = sys.argv[1:]
old = old.replace(r"\n", "\n")
new = new.replace(r"\n", "\n")
data = open(source).read()
if data.count(old) != 1:
    raise SystemExit(f"mutation source match count {data.count(old)}, expected 1")
open(target, "w").write(data.replace(old, new))
PY
  run swiftc -swift-version 5 -parse-as-library -c -module-name SwiftUI \
    -o "$b/mut-$name.o" "$b/mut-$name.swift" || return 1
  run swiftc -swift-version 5 -parse-as-library -I "$b" \
    -o "$P/keysdemo-mut-$name" "$b/mut-$name.o" "$P/simview/Sources/KeysDemo/KeysDemo.swift" || return 1
  run "$P/keysdemo-mut-$name" --frames "$frames" --out "$b/mut-$name.png" >"$bh/mut-$name.log" 2>&1 || return 1
  if "$check" "$bh/mut-$name.log" "$bh/mut-$name.png"; then
    bad "mutant $name survived"
  else
    ok "mutant $name failed its expected row"
  fi
}
check_row2() { grep -q 'state=first:Hi,second:' "$1"; }
check_row3() { grep -q 'state=first:Hey,second:' "$1"; }
check_row4() { grep -q 'text=x field=none state=first:A,second:' "$1"; }
check_row6() { grep -q 'text=x field=none state=first:Hi,second:,echo:Hi' "$1"; }
check_row7() { grep -q 'warning: key 42 dropped (no focus)' "$1" \
  && grep -q 'warning: text q dropped (no focus)' "$1"; }
check_row8() { grep -q 'state=first:AB,second:' "$1"; }
if ! mutant keys-last-field \
  'static func routeText(_ ch: Character, fields: [Int: FieldTarget], tMs: Int) -> String {
    guard let id = focusField, let field = fields[id] else {' \
  'static func routeText(_ ch: Character, fields: [Int: FieldTarget], tMs: Int) -> String {
    guard let id = fields.keys.max(), let field = fields[id] else {' \
  "$b/hi6.json" check_row2; then bad 'keys-last-field mutant failed to build'; fi
if ! mutant backspace-front \
  'String(field.text.get().dropLast())' \
  'String(field.text.get().dropFirst())' \
  "$b/hey6.json" check_row3; then bad 'backspace-front mutant failed to build'; fi
if ! mutant no-blur \
  '} else {\n          focusField = nil\n        }' \
  '} else {\n          _ = targetField\n        }' \
  "$b/blur6.json" check_row4; then bad 'no-blur mutant failed to build'; fi
if ! mutant cancelled-focus \
  'case .cancelled:\n        down.remove(rec.finger)\n        cancelled = true' \
  'case .cancelled:\n        down.remove(rec.finger)\n        cancelled = true\n        focusField = targetField' \
  "$b/cancel6.json" check_row8; then bad 'cancelled-focus mutant failed to build'; fi
if ! mutant no-return-blur \
  'field.onSubmit?()\n      focusField = nil' \
  'field.onSubmit?()' \
  "$b/return6.json" check_row6; then bad 'no-return-blur mutant failed to build'; fi
if ! mutant no-drop-warning \
  'static func warn(_ msg: String) {\n    print("warning: \(msg)")\n  }' \
  'static func warn(_ msg: String) {\n    _ = msg\n  }' \
  "$b/nofocus6.json" check_row7; then bad 'no-drop-warning mutant failed to build'; fi

if [ "$fail" -ne 0 ]; then echo "simview/test-m6.sh: FAILED"; exit 1; fi
echo "simview/test-m6.sh: all 11 rows and 6 mutation checks passed"
