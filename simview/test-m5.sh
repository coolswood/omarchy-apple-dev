#!/usr/bin/env bash
# M5 checks vertical drag scrolling, bounds, row cancellation and mutations.
set -uo pipefail
here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
if command -v swiftc >/dev/null 2>&1; then
  P=$(cd "$here/.." && pwd)
  run() { "$@"; }
elif [ -n "${SIMVIEW_CHROOT_RUN:-}" ]; then
  P=/work
  run() { "$SIMVIEW_CHROOT_RUN" --user "$*"; }
else
  echo "SKIP  simview/test-m5.sh: no swiftc and no SIMVIEW_CHROOT_RUN wrapper"
  exit 0
fi
bash "$here/build.sh" || exit 1
bh=$here/build
b=$P/simview/build
mkdir -p "$bh"
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
run_frames() { run "$P/scrolldemo" --frames "$1" --out "$2"; }

cat > "$bh/probe5.json" <<'EOF'
[{"t_ms":0,"fingers":[{"finger":0,"phase":"stationary","x":1,"y":1}]}]
EOF
run_frames "$b/probe5.json" "$b/probe5.png" >"$bh/probe5.log" 2>&1 || exit 1
first=$(grep '^button id=1 ' "$bh/probe5.log" | head -1 | sed 's/.*rect=//')
[ -n "$first" ] || { echo "FAIL no first row"; exit 1; }
read -r x y w h <<<"$(echo "$first" | tr ',' ' ')"
rx=$((x + w / 2)); ry=$((y + h / 2))

cat > "$bh/empty5.json" <<'EOF'
[]
EOF
run_frames "$b/empty5.json" "$b/root.png" >"$bh/root.log" 2>&1
cat > "$bh/up5.json" <<'EOF'
[{"t_ms":0,"fingers":[{"finger":0,"phase":"began","x":300,"y":400}]},{"t_ms":20,"fingers":[{"finger":0,"phase":"moved","x":300,"y":200}]},{"t_ms":40,"fingers":[{"finger":0,"phase":"ended","x":300,"y":200}]}]
EOF
run_frames "$b/up5.json" "$b/up.png" >"$bh/up.log" 2>&1
cat > "$bh/bottom5.json" <<'EOF'
[{"t_ms":0,"fingers":[{"finger":0,"phase":"began","x":300,"y":700}]},{"t_ms":20,"fingers":[{"finger":0,"phase":"moved","x":300,"y":-9300}]},{"t_ms":40,"fingers":[{"finger":0,"phase":"ended","x":300,"y":-9300}]}]
EOF
run_frames "$b/bottom5.json" "$b/bottom.png" >"$bh/bottom.log" 2>&1
cat > "$bh/down5.json" <<'EOF'
[{"t_ms":0,"fingers":[{"finger":0,"phase":"began","x":300,"y":100}]},{"t_ms":20,"fingers":[{"finger":0,"phase":"moved","x":300,"y":600}]},{"t_ms":40,"fingers":[{"finger":0,"phase":"ended","x":300,"y":600}]}]
EOF
run_frames "$b/down5.json" "$b/down.png" >"$bh/down.log" 2>&1
cat > "$bh/tap5.json" <<EOF
[{"tap":[$rx,$ry]}]
EOF
run_frames "$b/tap5.json" "$b/tap.png" >"$bh/tap.log" 2>&1
cat > "$bh/row-drag5.json" <<EOF
[{"t_ms":0,"fingers":[{"finger":0,"phase":"began","x":$rx,"y":$ry}]},{"t_ms":20,"fingers":[{"finger":0,"phase":"moved","x":$rx,"y":$((ry - 200))}]},{"t_ms":40,"fingers":[{"finger":0,"phase":"ended","x":$rx,"y":$((ry - 200))}]}]
EOF
run_frames "$b/row-drag5.json" "$b/row-drag.png" >"$bh/row-drag.log" 2>&1

if python3 "$here/compare.py" "$bh/root.png" "$here/golden/scroll-root.png"; then ok "row 0 root render"; else bad "row 0 root render"; fi
if python3 "$here/compare.py" "$bh/up.png" "$here/golden/scroll-mid.png" && grep -q 'state=selected:-1' "$bh/up.log"; then ok "row 1 upward drag changes content offset by 200 points"; else bad "row 1 upward drag"; fi
if python3 "$here/compare.py" "$bh/bottom.png" "$here/golden/scroll-bottom.png"; then ok "row 2 bottom clamp stops at 259 points"; else bad "row 2 bottom clamp"; fi
if python3 "$here/compare.py" "$bh/down.png" "$here/golden/scroll-root.png"; then ok "row 3 top clamp stops at zero"; else bad "row 3 top clamp"; fi
if grep -q 'state=selected:0' "$bh/tap.log"; then ok "row 4 tap activates a row"; else bad "row 4 tap"; fi
if grep -q 'state=selected:-1' "$bh/row-drag.log" && python3 "$here/compare.py" "$bh/row-drag.png" "$here/golden/scroll-mid.png" >/dev/null; then ok "row 5 drag on row scrolls and cancels tap"; else bad "row 5 drag cancellation"; fi
run_frames "$b/up5.json" "$b/up-again.png" >"$bh/up-again.log" 2>&1
grep -v '^wrote ' "$bh/up.log" >"$bh/up.cmp"
grep -v '^wrote ' "$bh/up-again.log" >"$bh/up-again.cmp"
if cmp -s "$bh/up.cmp" "$bh/up-again.cmp" && cmp -s "$bh/up.png" "$bh/up-again.png"; then ok "row 6 deterministic frames and PNG"; else bad "row 6 determinism"; fi

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
  run swiftc -swift-version 5 -parse-as-library -c -module-name SwiftUI -o "$b/mut-$name.o" "$b/mut-$name.swift" || return 1
  run swiftc -swift-version 5 -parse-as-library -I "$b" -o "$P/scrolldemo-mut-$name" "$b/mut-$name.o" "$P/simview/Sources/ScrollDemo/ScrollDemo.swift" || return 1
  run "$P/scrolldemo-mut-$name" --frames "$frames" --out "$b/mut-$name.png" >"$bh/mut-$name.log" 2>&1 || return 1
  if "$check" "$bh/mut-$name.log" "$bh/mut-$name.png"; then
    bad "mutant $name survived"
  else
    ok "mutant $name failed its expected row"
  fi
}
check_mid() { python3 "$here/compare.py" "$2" "$here/golden/scroll-mid.png" >/dev/null; }
check_bottom() { python3 "$here/compare.py" "$2" "$here/golden/scroll-bottom.png" >/dev/null; }
check_tap_cancel() { ! grep -q 'state=selected:0' "$1"; }
check_lower() { grep -q 'state=selected:-1' "$1" && python3 "$here/compare.py" "$2" "$here/golden/scroll-root.png" >/dev/null; }
if ! mutant wrong-direction 'startOffset - dy' 'startOffset + dy' "$b/up5.json" check_mid; then bad 'wrong-direction mutant failed to build'; fi
if ! mutant ignored-offset 'y: -offset.get()' 'y: 0' "$b/up5.json" check_mid; then bad 'ignored-offset mutant failed to build'; fi
if ! mutant no-cancel 'cancelled = true\n          binding.set' 'cancelled = false\n          binding.set' "$b/row-drag5.json" check_tap_cancel; then bad 'no-cancel mutant failed to build'; fi
if ! mutant no-upper-clamp 'min(max(startOffset - dy, 0), maximum)' 'max(startOffset - dy, 0)' "$b/bottom5.json" check_bottom; then bad 'no-upper-clamp mutant failed to build'; fi
if ! mutant no-lower-clamp 'min(max(startOffset - dy, 0), maximum)' 'min(startOffset - dy, maximum)' "$b/down5.json" check_lower; then bad 'no-lower-clamp mutant failed to build'; fi

if [ "$fail" -ne 0 ]; then echo "simview/test-m5.sh: FAILED"; exit 1; fi
echo "simview/test-m5.sh: all 7 rows and 5 mutation checks passed"
