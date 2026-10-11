#!/usr/bin/env bash
# simview M4 test: navigation. Root render against the golden, push via a
# list row, detail @State re-render, back popping one level, the back hit
# area, row two, determinism, and five mutation checks. Expected results,
# written before the code, live in simview/TESTS-M4.md. Exit 0 only when
# every row passes and every mutant fails its row.
#
# The chroot wrapper sees this checkout at /work; host tools see it at its
# real path. Renders written inside the chroot are compared on the host.
set -uo pipefail
here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)

if command -v swiftc >/dev/null 2>&1; then
  P=$(cd "$here/.." && pwd)  # repo root
  run() { "$@"; }
elif [ -n "${SIMVIEW_CHROOT_RUN:-}" ]; then
  P=/work
  run() { "$SIMVIEW_CHROOT_RUN" --user "$*"; }
else
  echo "SKIP  simview/test-m4.sh: no swiftc and no SIMVIEW_CHROOT_RUN wrapper"
  exit 0
fi

bash "$here/build.sh" || exit 1
bh=$here/build  # host view of the build dir
mkdir -p "$bh"
b=$P/simview/build  # view used by the binaries
fail=0
log() { echo "$@"; }

# Tap points on the root screen come from the rects the runner prints. Points
# on pushed screens come from the documented layout arithmetic in
# TESTS-M4.md, which the golden compares pin against the renders.
probe_rects() {  # $1 = binary; prints one "x y w h" line per button
  cat > "$bh/probe4.json" <<'EOF'
[{"t_ms": 0, "fingers": [{"finger": 0, "phase": "stationary", "x": 1, "y": 1}]}]
EOF
  run "$P/$1" --frames "$b/probe4.json" --out "$b/probe4.png" \
    | grep '^button ' | sed 's/^button id=[0-9]* rect=//; s/,/ /g'
}
rect_center() {  # $1 = rects line; sets cx cy
  read -r rx ry rw rh <<<"$1"
  cx=$((rx + rw / 2))
  cy=$((ry + rh / 2))
}

# Log shape: at least one t= line, and every t= line matches the documented
# line. The state field may contain spaces (an array of two builders prints
# ", " inside itself).
shape_ok() {  # $1 = log file
  grep -q '^t=' "$1" \
    && ! grep '^t=' "$1" | grep -qvE '^t=[0-9]+ finger=[0-9] (began|moved|ended|cancelled|stationary) \(-?[0-9]+,-?[0-9]+\) target=(Button#[0-9]+|none) state=.+ render=ok$'
}

# At least one differing pixel, and every differing pixel inside the rect.
inbox_check() {  # $1 = png, $2 = golden png, $3..$6 = x y w h
  PYTHONPATH="$here" python3 - "$1" "$2" "$3" "$4" "$5" "$6" <<'EOF'
import sys

from compare import read_png

da, a = read_png(sys.argv[1])
db, b = read_png(sys.argv[2])
if da != (390, 844) or db != (390, 844):
    print(f"FAIL sizes {da} and {db}, want (390, 844)")
    sys.exit(1)
x, y, w, h = (int(v) for v in sys.argv[3:7])
outside = 0
inside = 0
for i in range(0, len(a), 4):
    if a[i:i + 4] != b[i:i + 4]:
        px = (i // 4) % 390
        py = (i // 4) // 390
        if x <= px < x + w and y <= py < y + h:
            inside += 1
        else:
            outside += 1
if inside >= 1 and outside == 0:
    print(f"ok   {inside} differing pixels, all inside {x},{y},{w},{h}")
    sys.exit(0)
print(f"FAIL {inside} differing pixels inside, {outside} outside "
      f"{x},{y},{w},{h}")
sys.exit(1)
EOF
}

tlines() {  # $1 = log; prints its t= lines
  grep '^t=' "$1"
}
check_row0() {  # $1 = log (unused), $2 = png
  python3 "$here/compare.py" "$2" "$here/golden/nav-root.png" >/dev/null
}
check_row1() {  # $1 = log, $2 = png
  shape_ok "$1" \
    && [ "$(tlines "$1" | wc -l)" -eq 2 ] \
    && grep -q '^t=0 finger=0 began .* target=Button#1 state=path:\[\],' "$1" \
    && grep -q '^t=80 finger=0 ended .* target=Button#1 state=path:\[(Function)\],' "$1" \
    && python3 "$here/compare.py" "$2" "$here/golden/nav-one.png" >/dev/null
}
check_row2() {  # $1 = log, $2 = png
  shape_ok "$1" \
    && [ "$(tlines "$1" | wc -l)" -eq 4 ] \
    && grep -q '^t=0 finger=0 began .* target=Button#1 state=path:\[\],' "$1" \
    && grep -q '^t=80 finger=0 ended .* target=Button#1 .*taps:0' "$1" \
    && grep -q '^t=160 finger=0 began .* target=Button#2 .*taps:0' "$1" \
    && grep -q '^t=240 finger=0 ended .*target=Button#2 .*taps:1' "$1" \
    && inbox_check "$2" "$here/golden/nav-one.png" 174 426 41 9 >/dev/null
}
check_row3() {  # $1 = log, $2 = png
  shape_ok "$1" \
    && [ "$(tlines "$1" | wc -l)" -eq 6 ] \
    && grep -q '^t=80 finger=0 ended .* target=Button#1 ' "$1" \
    && grep -q '^t=240 finger=0 ended .* target=Button#3 ' "$1" \
    && grep -q '^t=400 finger=0 ended .* target=Button#1 state=path:\[(Function)\],' "$1" \
    && python3 "$here/compare.py" "$2" "$here/golden/nav-one.png" >/dev/null \
    && ! python3 "$here/compare.py" "$2" "$here/golden/nav-root.png" >/dev/null
}
check_row4() {  # $1 = log, $2 = png
  shape_ok "$1" \
    && [ "$(tlines "$1" | wc -l)" -eq 4 ] \
    && [ "$(grep -c 'target=none' "$1")" -eq 2 ] \
    && grep -q '^t=80 finger=0 ended .* target=Button#1 ' "$1" \
    && python3 "$here/compare.py" "$2" "$here/golden/nav-one.png" >/dev/null
}

echo "== probe button rects"
navrects=$(probe_rects navdemo)
[ -n "$navrects" ] || { echo "FAIL probe printed no rects"; exit 1; }
log "$navrects" | sed 's/^/ok   navdemo rect /'
# Documented layout arithmetic (TESTS-M4.md): two 47x7 rows, separators
# after each row, content centered below the 44 point bar. A regression in
# the bar height, the list separators, or the centering moves these.
if [ "$navrects" = "$(printf '171 412 47 7\n171 452 47 7')" ]; then
  log "ok   navdemo rects match the documented layout arithmetic"
else
  log "FAIL navdemo rects do not match the documented layout"
  fail=1
fi
rect_center "$(log "$navrects" | sed -n 1p)"
r1x=$cx; r1y=$cy
rect_center "$(log "$navrects" | sed -n 2p)"
r2x=$cx; r2y=$cy

echo "== row 0: root render and clean exit"
run "$P/navdemo" --out "$b/row0.png" >"$bh/row0.log" 2>&1
rc=$?
if [ $rc -eq 0 ] && python3 "$here/compare.py" "$bh/row0.png" "$here/golden/nav-root.png"; then
  log "ok   root render matches the golden, exit 0"
else
  log "FAIL row 0: exit $rc"; cat "$bh/row0.log"; fail=1
fi

echo "== row 1: tap pushes one level"
cat > "$bh/row1.json" <<EOF
[
  {"t_ms": 0,  "fingers": [{"finger": 0, "phase": "began", "x": $r1x, "y": $r1y}]},
  {"t_ms": 80, "fingers": [{"finger": 0, "phase": "ended", "x": $r1x, "y": $r1y}]}
]
EOF
run "$P/navdemo" --frames "$b/row1.json" --out "$b/row1.png" >"$bh/row1.log" 2>&1
rc=$?
if [ $rc -eq 0 ] && check_row1 "$bh/row1.log" "$bh/row1.png"; then
  log "ok   pushed screen matches golden/nav-one.png, shape holds"
else
  log "FAIL row 1: exit $rc"; cat "$bh/row1.log"; fail=1
fi

echo "== row 2: detail state re-renders"
cat > "$bh/row2.json" <<EOF
[
  {"t_ms": 0,   "fingers": [{"finger": 0, "phase": "began", "x": $r1x, "y": $r1y}]},
  {"t_ms": 80,  "fingers": [{"finger": 0, "phase": "ended", "x": $r1x, "y": $r1y}]},
  {"t_ms": 160, "fingers": [{"finger": 0, "phase": "began", "x": 194, "y": 455}]},
  {"t_ms": 240, "fingers": [{"finger": 0, "phase": "ended", "x": 194, "y": 455}]}
]
EOF
run "$P/navdemo" --frames "$b/row2.json" --out "$b/row2.png" >"$bh/row2.log" 2>&1
rc=$?
if [ $rc -eq 0 ] && check_row2 "$bh/row2.log" "$bh/row2.png"; then
  log "ok   taps:1 logged and every changed pixel inside the taps text"
else
  log "FAIL row 2: exit $rc"; cat "$bh/row2.log"; fail=1
fi

echo "== row 3: back pops one level of two"
cat > "$bh/row3.json" <<EOF
[
  {"t_ms": 0,   "fingers": [{"finger": 0, "phase": "began", "x": $r1x, "y": $r1y}]},
  {"t_ms": 80,  "fingers": [{"finger": 0, "phase": "ended", "x": $r1x, "y": $r1y}]},
  {"t_ms": 160, "fingers": [{"finger": 0, "phase": "began", "x": 194, "y": 480}]},
  {"t_ms": 240, "fingers": [{"finger": 0, "phase": "ended", "x": 194, "y": 480}]},
  {"t_ms": 320, "fingers": [{"finger": 0, "phase": "began", "x": 29, "y": 21}]},
  {"t_ms": 400, "fingers": [{"finger": 0, "phase": "ended", "x": 29, "y": 21}]}
]
EOF
run "$P/navdemo" --frames "$b/row3.json" --out "$b/row3.png" >"$bh/row3.log" 2>&1
rc=$?
if [ $rc -eq 0 ] && check_row3 "$bh/row3.log" "$bh/row3.png"; then
  log "ok   back removed the last level only; render is the one screen"
else
  log "FAIL row 3: exit $rc"; cat "$bh/row3.log"; fail=1
fi

echo "== row 4: back hit area is its label rect"
cat > "$bh/row4.json" <<EOF
[
  {"t_ms": 0,   "fingers": [{"finger": 0, "phase": "began", "x": $r1x, "y": $r1y}]},
  {"t_ms": 80,  "fingers": [{"finger": 0, "phase": "ended", "x": $r1x, "y": $r1y}]},
  {"t_ms": 160, "fingers": [{"finger": 0, "phase": "began", "x": 250, "y": 21}]},
  {"t_ms": 240, "fingers": [{"finger": 0, "phase": "ended", "x": 250, "y": 21}]}
]
EOF
run "$P/navdemo" --frames "$b/row4.json" --out "$b/row4.png" >"$bh/row4.log" 2>&1
rc=$?
if [ $rc -eq 0 ] && check_row4 "$bh/row4.log" "$bh/row4.png"; then
  log "ok   bar tap missed the back label; still on the pushed screen"
else
  log "FAIL row 4: exit $rc"; cat "$bh/row4.log"; fail=1
fi

echo "== row 5: row two pushes its own detail"
cat > "$bh/row5.json" <<EOF
[
  {"t_ms": 0,  "fingers": [{"finger": 0, "phase": "began", "x": $r2x, "y": $r2y}]},
  {"t_ms": 80, "fingers": [{"finger": 0, "phase": "ended", "x": $r2x, "y": $r2y}]}
]
EOF
run "$P/navdemo" --frames "$b/row5.json" --out "$b/row5.png" >"$bh/row5.log" 2>&1
rc=$?
if [ $rc -eq 0 ] && python3 "$here/compare.py" "$bh/row5.png" "$here/golden/nav-two.png" >/dev/null; then
  log "ok   row two render matches golden/nav-two.png"
else
  log "FAIL row 5: exit $rc"; cat "$bh/row5.log"; fail=1
fi

echo "== row 6: same file twice"
run "$P/navdemo" --frames "$b/row2.json" --out "$b/row6a.png" >"$bh/row6a.log" 2>&1
run "$P/navdemo" --frames "$b/row2.json" --out "$b/row6b.png" >"$bh/row6b.log" 2>&1
grep -v '^wrote ' "$bh/row6a.log" >"$bh/row6a.cmp"
grep -v '^wrote ' "$bh/row6b.log" >"$bh/row6b.cmp"
if cmp -s "$bh/row6a.cmp" "$bh/row6b.cmp" && cmp -s "$bh/row6a.png" "$bh/row6b.png"; then
  log "ok   identical log bytes and identical PNG bytes"
else
  log "FAIL row 6: runs differ"; fail=1
fi

# Mutation checks. Each applies one named implementation change to a copy of
# the module, rebuilds navdemo against it, reruns its row, and requires the
# row's check to fail. A surviving mutant fails the suite. TESTS-M4.md lists
# each mutant and why its row must bite.
printf '[]' > "$bh/empty.json"  # zero frames: one plain render, for row 0

mutant_src() {  # $1 = name; copies the module to $bh/mut-$1.swift
  cp "$here/Sources/SwiftUI/SwiftUI.swift" "$bh/mut-$1.swift" || return 1
}
mutant_edit() {  # $1 = name, $2 = old, $3 = new; fails when old is not unique
  python3 - "$bh/mut-$1.swift" "$2" "$3" <<'EOF'
import sys

path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path).read()
if src.count(old) != 1:
    print(f"FAIL mutant edit: pattern found {src.count(old)} times, want 1")
    sys.exit(1)
open(path, "w").write(src.replace(old, new))
EOF
}
mutant_build() {  # $1 = name
  run swiftc -swift-version 5 -parse-as-library -c -module-name SwiftUI \
    -o "$b/mut-$1.o" "$b/mut-$1.swift" || return 1
  run swiftc -swift-version 5 -parse-as-library -I "$b" \
    -o "$P/navdemo-mut-$1" "$b/mut-$1.o" "$P/simview/Sources/NavDemo/NavDemo.swift" || return 1
}
mutant_check() {  # $1 = name, $2 = check fn name, $3 = frames file ($b view)
  local name=$1 check=$2 frames=$3 logf="$bh/mut-$1.log"
  run "$P/navdemo-mut-$1" --frames "$frames" --out "$b/mut-$1.png" >"$logf" 2>&1
  if "$check" "$logf" "$bh/mut-$1.png"; then
    log "FAIL mutant $1 survived its row"
    cat "$logf"
    fail=1
  else
    log "ok   mutant $1 failed its row"
  fi
}

echo "== mutant pop-clears: back empties the stack (row 3 must fail)"
if mutant_src pop-clears \
  && mutant_edit pop-clears '{ self.path.removeLast() }' '{ self.path = [] }' \
  && mutant_build pop-clears; then
  mutant_check pop-clears check_row3 "$b/row3.json"
else
  log "FAIL mutant pop-clears did not build"; fail=1
fi

echo "== mutant bar-wide-back: back hit rect spans the bar (row 4 must fail)"
if mutant_src bar-wide-back \
  && mutant_edit bar-wide-back 'w: backSize.w, h: backSize.h, color: blue' 'w: screenWidth - backX, h: backSize.h, color: blue' \
  && mutant_build bar-wide-back; then
  mutant_check bar-wide-back check_row4 "$b/row4.json"
else
  log "FAIL mutant bar-wide-back did not build"; fail=1
fi

echo "== mutant root-title: bar title always from the root (row 1 must fail)"
if mutant_src root-title \
  && mutant_edit root-title 'Sim.firstTitle(screen), back, screen' 'Sim.firstTitle(root), back, screen' \
  && mutant_build root-title; then
  mutant_check root-title check_row1 "$b/row1.json"
else
  log "FAIL mutant root-title did not build"; fail=1
fi

echo "== mutant frozen-destination: pushed spec built once at push (row 2 must fail)"
if mutant_src frozen-destination \
  && mutant_edit frozen-destination 'return .button(label, { self.path.append(build) })' 'var cache: Spec?
      return .button(label, { self.path.append({
        if cache == nil { cache = build() }
        return cache!
      }) })' \
  && mutant_build frozen-destination; then
  mutant_check frozen-destination check_row2 "$b/row2.json"
else
  log "FAIL mutant frozen-destination did not build"; fail=1
fi

echo "== mutant no-separators: draw skips separator lines (row 0 must fail)"
if mutant_src no-separators \
  && mutant_edit no-separators 'case .hairline:
        for y in p.y..<p.y + p.h {
          for x in p.x..<p.x + p.w {
            c.set(x: x, y: y, p.color)
          }
        }' 'case .hairline:
        break' \
  && mutant_build no-separators; then
  mutant_check no-separators check_row0 "$b/empty.json"
else
  log "FAIL mutant no-separators did not build"; fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "simview/test-m4.sh: FAILED"
  exit 1
fi
echo "simview/test-m4.sh: all rows passed"
