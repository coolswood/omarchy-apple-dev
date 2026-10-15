#!/usr/bin/env bash
# M7 checks HStack, Spacer and padding: layout geometry, where text lands,
# taps inside rows, a NavigationLink inside a padded row, and mutations.
# Expected results: simview/TESTS-M7.md.
set -uo pipefail
here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
if command -v swiftc >/dev/null 2>&1; then
  P=$(cd "$here/.." && pwd)
  run() { "$@"; }
elif [ -n "${SIMVIEW_CHROOT_RUN:-}" ]; then
  P=/work
  run() { "$SIMVIEW_CHROOT_RUN" --user "$*"; }
else
  echo "SKIP  simview/test-m7.sh: no swiftc and no SIMVIEW_CHROOT_RUN wrapper"
  exit 0
fi
bash "$here/build.sh" || exit 1
bh=$here/build
b=$P/simview/build
mkdir -p "$bh"
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
rows() { run "$P/rowdemo" --frames "$1" --out "$2"; }
nav() { run "$P/rownavdemo" --frames "$1" --out "$2"; }
# The apps write under $b (a chroot path in chroot mode); python runs on the host, so map $b to $bh.
gc() { python3 "$here/compare.py" "${2/#$b/$bh}" "$here/golden/$1" >/dev/null; }
ink() { local f=${1/#$b/$bh}; shift; python3 "$here/inkbox.py" "$f" "$@"; }

echo '[]' > "$bh/empty7.json"
rows "$b/empty7.json" "$b/row-root.png" >"$bh/row-root.log" 2>&1

# Row 1: the rects the layout reports, from the arithmetic in TESTS-M7.md.
if grep -qx 'button id=1 rect=166,421,29,7' "$bh/row-root.log" \
  && grep -qx 'button id=2 rect=201,420,23,9' "$bh/row-root.log"; then
  ok "row 1 button rects: spacing 6 between buttons, shorter label centered on the row"
else bad "row 1 button rects"; fi

# Row 2: ink positions read from the PNG, independent of any golden.
l=$(ink "$b/row-root.png" 0 383 100 420)
r=$(ink "$b/row-root.png" 290 383 390 420)
m=$(ink "$b/row-root.png" 0 437 390 444)
read -r lx0 ly0 _ _ <<<"$l"
read -r _ ry0 rx1 _ <<<"$r"
read -r mx0 _ mx1 _ <<<"$m"
if [ "${lx0:-0}" -ge 10 ] && [ "${lx0:-0}" -le 12 ] && [ "${ly0:-0}" = 394 ] \
  && [ "${rx1:-0}" -ge 378 ] && [ "${rx1:-0}" -le 379 ] && [ "${ry0:-0}" = 393 ] \
  && [ "${mx0:-0}" = 186 ] && [ "${mx1:-0}" = 202 ]; then
  ok "row 2 ink: padding 10, Spacer pushes the right label to the padded edge, two Spacers center a label"
else bad "row 2 ink: left=[$l] right=[$r] mid=[$m]"; fi

# Row 0: the whole render, frozen after row 1 and row 2 passed.
if gc row-root.png "$b/row-root.png"; then ok "row 0 root render"; else bad "row 0 root render"; fi

cat > "$bh/plus7.json" <<'EOF'
[{"tap":[212,424]},{"tap":[212,424]}]
EOF
rows "$b/plus7.json" "$b/row-two.png" >"$bh/plus7.log" 2>&1
if grep -q 'state=taps:2' "$bh/plus7.log" && gc row-two.png "$b/row-two.png"; then
  ok "row 3 two taps on the second button give taps 2"
else bad "row 3 taps on the second button"; fi

cat > "$bh/minus7.json" <<'EOF'
[{"tap":[180,424]}]
EOF
rows "$b/minus7.json" "$b/row-minus.png" >"$bh/minus7.log" 2>&1
if grep -q 'state=taps:-1' "$bh/minus7.log" && gc row-minus.png "$b/row-minus.png"; then
  ok "row 4 tap on the first button gives taps -1"
else bad "row 4 tap on the first button"; fi

cat > "$bh/gap7.json" <<'EOF'
[{"tap":[198,424]}]
EOF
rows "$b/gap7.json" "$b/row-gap.png" >"$bh/gap7.log" 2>&1
if grep -q 'state=taps:0' "$bh/gap7.log" && gc row-root.png "$b/row-gap.png"; then
  ok "row 5 a tap in the spacing gap changes nothing"
else bad "row 5 tap in the gap"; fi

nav "$b/empty7.json" "$b/nav-root.png" >"$bh/nav-root.log" 2>&1
link=$(grep '^button id=1 ' "$bh/nav-root.log" | head -1 | sed 's/.*rect=//')
if [ -n "$link" ]; then
  read -r lkx lky lkw lkh <<<"$(echo "$link" | tr ',' ' ')"
  cat > "$bh/navtap7.json" <<EOF
[{"tap":[$((lkx + lkw / 2)),$((lky + lkh / 2))]}]
EOF
  nav "$b/navtap7.json" "$b/nav-pushed.png" >"$bh/nav-pushed.log" 2>&1
fi
if [ -n "$link" ] && gc row-nav-root.png "$b/nav-root.png" && gc row-nav-pushed.png "$b/nav-pushed.png" \
  && ! gc row-nav-root.png "$b/nav-pushed.png"; then
  ok "row 6 a NavigationLink inside a padded row still pushes"
else bad "row 6 link inside a padded row (link=[$link])"; fi

rows "$b/plus7.json" "$b/row-two-again.png" >"$bh/plus7-again.log" 2>&1
grep -v '^wrote ' "$bh/plus7.log" >"$bh/plus7.cmp"
grep -v '^wrote ' "$bh/plus7-again.log" >"$bh/plus7-again.cmp"
if cmp -s "$bh/plus7.cmp" "$bh/plus7-again.cmp" && cmp -s "$bh/row-two.png" "$bh/row-two-again.png"; then
  ok "row 7 deterministic logs and PNG"
else bad "row 7 determinism"; fi

mutant() {
  name=$1 old=$2 new=$3 check=$4
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
  [ $? -eq 0 ] || return 1
  run swiftc -swift-version 5 -parse-as-library -c -module-name SwiftUI -o "$b/mut-$name.o" "$b/mut-$name.swift" || return 1
  run swiftc -swift-version 5 -parse-as-library -I "$b" -o "$P/rowdemo-mut-$name" "$b/mut-$name.o" "$P/simview/Sources/RowDemo/RowDemo.swift" || return 1
  run "$P/rowdemo-mut-$name" --frames "$b/empty7.json" --out "$b/mut-$name.png" >"$bh/mut-$name.log" 2>&1 || return 1
  if "$check" "$bh/mut-$name.log" "$bh/mut-$name.png"; then
    bad "mutant $name survived"
  else
    ok "mutant $name failed its expected row"
  fi
}
# Each check returns success while the changed build still passes the row.
check_row1() { grep -qx 'button id=1 rect=166,421,29,7' "$1" && grep -qx 'button id=2 rect=201,420,23,9' "$1"; }
check_row0() { python3 "$here/compare.py" "$2" "$here/golden/row-root.png" >/dev/null; }
if ! mutant no-spacing 'if i > 0 { cx += spacing }' '' check_row1; then bad 'no-spacing mutant failed to build'; fi
if ! mutant no-centering 'y: y + (rowHeight - sizes[i].h) / 2, width: sizes[i].w' 'y: y, width: sizes[i].w' check_row1; then bad 'no-centering mutant failed to build'; fi
if ! mutant no-spacer-share 'let share = extra / left' 'let share = 0' check_row0; then bad 'no-spacer-share mutant failed to build'; fi
if ! mutant no-padding-offset 'layout(child, at: x + length, y: y + length,' 'layout(child, at: x, y: y,' check_row0; then bad 'no-padding-offset mutant failed to build'; fi
if ! mutant proposal-not-reduced 'proposedWidth -= 2 * length\n      defer { proposedWidth = saved }\n      let cs' 'defer { proposedWidth = saved }\n      let cs' check_row0; then bad 'proposal-not-reduced mutant failed to build'; fi

if [ "$fail" -ne 0 ]; then echo "simview/test-m7.sh: FAILED"; exit 1; fi
echo "simview/test-m7.sh: all 8 rows and 5 mutation checks passed"
