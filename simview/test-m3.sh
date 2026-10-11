#!/usr/bin/env bash
# simview M3 test: the eight rows of docs/SIM-INPUT-MODEL.md, the demo app
# tap, a negative control, and determinism. Expected results, written before
# the code, live in simview/TESTS-M3.md. Exit 0 only when every row passes.
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
  echo "SKIP  simview/test-m3.sh: no swiftc and no SIMVIEW_CHROOT_RUN wrapper"
  exit 0
fi

bash "$here/build.sh" || exit 1
bh=$here/build  # host view of the build dir
mkdir -p "$bh"
b=$P/simview/build  # view used by the binaries
fail=0
log() { echo "$@"; }

# Frames files take tap points from the rects the runner prints, so no test
# hard codes a layout offset. The probe run touches empty space at (1,1).
probe_rects() {  # $1 = binary; prints one "x y w h" line per button
  cat > "$bh/probe.json" <<'EOF'
[{"t_ms": 0, "fingers": [{"finger": 0, "phase": "stationary", "x": 1, "y": 1}]}]
EOF
  run "$P/$1" --frames "$b/probe.json" --out "$b/probe.png" \
    | grep '^button ' | sed 's/^button id=[0-9]* rect=//; s/,/ /g'
}
rect_center() {  # $1 = rects line; sets cx cy
  read -r rx ry rw rh <<<"$1"
  cx=$((rx + rw / 2))
  cy=$((ry + rh / 2))
}
write_tap() {  # $1 = file, $2 = cx, $3 = cy, $4 = lift dy (0 or an offset)
  cat > "$1" <<EOF
[
  {"t_ms": 0,  "fingers": [{"finger": 0, "phase": "began", "x": $2, "y": $3}]},
  {"t_ms": 80, "fingers": [{"finger": 0, "phase": "ended", "x": $2, "y": $(($3 + $4))}]}
]
EOF
}

# One action, fired on the ended record: exactly one line with state=count:1,
# every other line at count:0. Used by rows 1 and 3, and by the negative
# control, which feeds it a no-action log and requires a failure.
check_one_action() {  # $1 = log file
  python3 - "$1" <<'EOF'
import re
import sys

lines = [l for l in open(sys.argv[1]).read().splitlines() if l.startswith("t=")]
ones = [l for l in lines if re.search(r"state=count:1\b", l)]
rest_ok = all(re.search(r"state=count:0\b", l) for l in lines
              if not re.search(r"state=count:1\b", l))
if len(lines) > 0 and len(ones) == 1 and rest_ok and " ended " in ones[0]:
    print("ok   one action, fired on the ended record")
    sys.exit(0)
print(f"FAIL expected one action on ended, saw {len(ones)} "
      f"count:1 line(s) of {len(lines)}")
sys.exit(1)
EOF
}

echo "== probe button rects"
m3rects=$(probe_rects m3app)
demorects=$(probe_rects simview-demo)
[ -n "$m3rects" ] && [ -n "$demorects" ] || { echo "FAIL probe printed no rects"; exit 1; }
log "$m3rects" | sed 's/^/ok   m3app rect /'
log "$demorects" | sed 's/^/ok   demo rect /'

echo "== row 0: demo app tap"
rect_center "$(log "$demorects" | sed -n 1p)"
write_tap "$bh/row0.json" "$cx" "$cy" 0
run "$P/simview-demo" --frames "$b/row0.json" --out "$b/row0.png" >"$bh/row0.log" 2>"$bh/row0.err"
rc=$?
if [ $rc -eq 0 ] && grep -q 'target=Button#1' "$bh/row0.log" \
  && grep -q 'state=count:1' "$bh/row0.log"; then
  log "ok   demo tap hit Button#1 and fired the action"
else
  log "FAIL demo tap: exit $rc"; cat "$bh/row0.log"; cat "$bh/row0.err"; fail=1
fi
if grep '^t=' "$bh/row0.log" | grep -qvE '^t=[0-9]+ finger=[0-9] (began|moved|ended|cancelled|stationary) \(-?[0-9]+,-?[0-9]+\) target=(Button#[0-9]+|none) state=[a-z]+:-?[0-9]+ render=ok$'; then
  log "FAIL demo log line shape"; grep '^t=' "$bh/row0.log" | grep -vE '^t=[0-9]+ finger=[0-9] (began|moved|ended|cancelled|stationary) \(-?[0-9]+,-?[0-9]+\) target=(Button#[0-9]+|none) state=[a-z]+:-?[0-9]+ render=ok$'; fail=1
else
  log "ok   every demo log line matches the documented shape"
fi
python3 "$here/compare.py" "$bh/row0.png" "$here/golden/after-tap.png" || fail=1

echo "== row 1: tap inside a button"
rect_center "$(log "$m3rects" | sed -n 1p)"
run "$P/m3app" --out "$b/row1-before.png" >/dev/null
write_tap "$bh/row1.json" "$cx" "$cy" 0
run "$P/m3app" --frames "$b/row1.json" --out "$b/row1-after.png" >"$bh/row1.log" 2>&1
if [ $? -eq 0 ] && check_one_action "$bh/row1.log"; then :; else
  log "FAIL row 1 action check"; cat "$bh/row1.log"; fail=1
fi
if python3 - "$bh/row1.log" "$bh/row1-before.png" "$bh/row1-after.png" "$here" <<'EOF'
import re
import sys

sys.path.insert(0, sys.argv[4])
from compare import read_png

rect = None
for l in open(sys.argv[1]):
    m = re.match(r"button id=1 rect=(\d+),(\d+),(\d+),(\d+)", l)
    if m:
        rect = [int(v) for v in m.groups()]
(_, _), a = read_png(sys.argv[3])
(_, _), b = read_png(sys.argv[2])
diff = sum(1 for i in range(0, len(a), 4) if a[i:i + 4] != b[i:i + 4])
x, y, w, h = rect
inbox = sum(1 for i in range(0, len(a), 4)
            if a[i:i + 4] != b[i:i + 4]
            and x <= (i // 4) % 390 < x + w and y <= (i // 4) // 390 < y + h)
if inbox >= 1:
    print(f"ok   {inbox} of {diff} differing pixels inside the button box")
    sys.exit(0)
print(f"FAIL no differing pixel inside the button box ({diff} differ overall)")
sys.exit(1)
EOF
then :; else fail=1; fi

echo "== row 2: press inside, move out, lift outside"
rect_center "$(log "$m3rects" | sed -n 1p)"
cat > "$bh/row2.json" <<EOF
[
  {"t_ms": 0,   "fingers": [{"finger": 0, "phase": "began", "x": $cx, "y": $cy}]},
  {"t_ms": 40,  "fingers": [{"finger": 0, "phase": "moved", "x": $(($cx - 60)), "y": $cy}]},
  {"t_ms": 80,  "fingers": [{"finger": 0, "phase": "ended", "x": $(($cx - 60)), "y": $cy}]}
]
EOF
run "$P/m3app" --frames "$b/row2.json" --out "$b/row2.png" >"$bh/row2.log" 2>&1
n=$(grep -c 'target=Button#1' "$bh/row2.log")
z=$(grep -c 'state=count:0' "$bh/row2.log")
if [ $? -eq 0 ] && [ "$n" -eq 3 ] && [ "$z" -eq 3 ] && ! grep -q 'state=count:1' "$bh/row2.log"; then
  log "ok   target stays Button#1, no action"
else
  log "FAIL row 2"; cat "$bh/row2.log"; fail=1
fi

echo "== row 3: out and back, lift inside"
cat > "$bh/row3.json" <<EOF
[
  {"t_ms": 0,   "fingers": [{"finger": 0, "phase": "began", "x": $cx, "y": $cy}]},
  {"t_ms": 30,  "fingers": [{"finger": 0, "phase": "moved", "x": $(($cx - 60)), "y": $cy}]},
  {"t_ms": 60,  "fingers": [{"finger": 0, "phase": "moved", "x": $cx, "y": $cy}]},
  {"t_ms": 80,  "fingers": [{"finger": 0, "phase": "ended", "x": $cx, "y": $cy}]}
]
EOF
run "$P/m3app" --frames "$b/row3.json" --out "$b/row3.png" >"$bh/row3.log" 2>&1
if [ $? -eq 0 ] && check_one_action "$bh/row3.log"; then :; else
  log "FAIL row 3"; cat "$bh/row3.log"; fail=1
fi

echo "== row 4: drag across the second button"
rect_center "$(log "$m3rects" | sed -n 2p)"
cx2=$cx; cy2=$cy
rect_center "$(log "$m3rects" | sed -n 1p)"
cat > "$bh/row4.json" <<EOF
[
  {"t_ms": 0,   "fingers": [{"finger": 0, "phase": "began", "x": $cx, "y": $cy}]},
  {"t_ms": 40,  "fingers": [{"finger": 0, "phase": "moved", "x": $cx2, "y": $cy2}]},
  {"t_ms": 80,  "fingers": [{"finger": 0, "phase": "ended", "x": $cx2, "y": $cy2}]}
]
EOF
run "$P/m3app" --frames "$b/row4.json" --out "$b/row4.png" >"$bh/row4.log" 2>&1
n1=$(grep -c 'target=Button#1' "$bh/row4.log")
n2=$(grep -c 'target=Button#2' "$bh/row4.log")
z=$(grep -c 'state=count:0' "$bh/row4.log")
if [ $? -eq 0 ] && [ "$n1" -eq 3 ] && [ "$n2" -eq 0 ] && [ "$z" -eq 3 ]; then
  log "ok   first button owns the touch, no action on either"
else
  log "FAIL row 4"; cat "$bh/row4.log"; fail=1
fi

echo "== row 5: tap on empty space"
cat > "$bh/row5.json" <<'EOF'
[
  {"t_ms": 0,  "fingers": [{"finger": 0, "phase": "began", "x": 30, "y": 30}]},
  {"t_ms": 80, "fingers": [{"finger": 0, "phase": "ended", "x": 30, "y": 30}]}
]
EOF
run "$P/m3app" --frames "$b/row5.json" --out "$b/row5.png" >"$bh/row5.log" 2>&1
nn=$(grep -c 'target=none' "$bh/row5.log")
z=$(grep -c 'state=count:0' "$bh/row5.log")
if [ $? -eq 0 ] && [ "$nn" -eq 2 ] && [ "$z" -eq 2 ]; then
  log "ok   no target, no state change"
else
  log "FAIL row 5"; cat "$bh/row5.log"; fail=1
fi

echo "== negative control: the one-action checker must reject a no-action log"
if check_one_action "$bh/row5.log" >/dev/null 2>&1; then
  log "FAIL negative control passed the one-action check"
  fail=1
else
  log "ok   negative control failed the check as required"
fi

echo "== row 6: two fingers, one lifts"
cat > "$bh/row6.json" <<'EOF'
[
  {"t_ms": 0,   "fingers": [{"finger": 0, "phase": "began", "x": 100, "y": 100},
                            {"finger": 1, "phase": "began", "x": 290, "y": 100}]},
  {"t_ms": 60,  "fingers": [{"finger": 0, "phase": "ended", "x": 100, "y": 100},
                            {"finger": 1, "phase": "stationary", "x": 290, "y": 100}]},
  {"t_ms": 120, "fingers": [{"finger": 1, "phase": "stationary", "x": 290, "y": 100}]},
  {"t_ms": 180, "fingers": [{"finger": 1, "phase": "ended", "x": 290, "y": 100}]}
]
EOF
run "$P/m3app" --frames "$b/row6.json" --out "$b/row6.png" >"$bh/row6.log" 2>&1
if [ $? -eq 0 ] && python3 - "$bh/row6.log" <<'EOF'
import re
import sys

lines = [l for l in open(sys.argv[1]).read().splitlines() if l.startswith("t=")]
by_t = {}
for l in lines:
    by_t.setdefault(re.match(r"t=(\d+) ", l).group(1), []).append(l)


def has(t, sub):
    return any(sub in l for l in by_t.get(t, []))


if (len(by_t.get("0", [])) == 2
        and len(by_t.get("60", [])) == 2
        and has("60", "finger=0 ended") and has("60", "finger=1 stationary")
        and len(by_t.get("120", [])) == 1 and has("120", "finger=1 stationary")
        and len(by_t.get("180", [])) == 1 and has("180", "finger=1 ended")
        and all("target=none" in l and "state=count:0" in l for l in lines)):
    print("ok   lift frame lists both fingers, next frame lists one")
    sys.exit(0)
print("FAIL row 6 log:", lines)
sys.exit(1)
EOF
then :; else log "FAIL row 6"; cat "$bh/row6.log"; fail=1; fi

echo "== row 7: frames out of time order"
cat > "$bh/row7.json" <<'EOF'
[
  {"t_ms": 400, "fingers": [{"finger": 0, "phase": "began", "x": 30, "y": 30}]},
  {"t_ms": 200, "fingers": [{"finger": 0, "phase": "ended", "x": 30, "y": 30}]}
]
EOF
rm -f "$bh/row7.png"
run "$P/m3app" --frames "$b/row7.json" --out "$b/row7.png" >"$bh/row7.log" 2>"$bh/row7.err"
rc=$?
if [ $rc -ne 0 ] && grep -q 'frame 1' "$bh/row7.err" \
  && grep -q '200' "$bh/row7.err" && grep -q '400' "$bh/row7.err" \
  && [ ! -e "$bh/row7.png" ]; then
  log "ok   refused the file, named the index and both times, no PNG"
else
  log "FAIL row 7: exit $rc"; cat "$bh/row7.err"; fail=1
fi

echo "== row 8: same file twice"
run "$P/m3app" --frames "$b/row1.json" --out "$b/row8a.png" >"$bh/row8a.log" 2>&1
run "$P/m3app" --frames "$b/row1.json" --out "$b/row8b.png" >"$bh/row8b.log" 2>&1
grep -v '^wrote ' "$bh/row8a.log" >"$bh/row8a.cmp"
grep -v '^wrote ' "$bh/row8b.log" >"$bh/row8b.cmp"
if cmp -s "$bh/row8a.cmp" "$bh/row8b.cmp" && cmp -s "$bh/row8a.png" "$bh/row8b.png"; then
  log "ok   identical log bytes and identical PNG bytes"
else
  log "FAIL row 8: runs differ"; fail=1
fi

echo "== row 9: nested child state survives the rebuild"
nestrects=$(probe_rects nestedapp)
rect_center "$(log "$nestrects" | sed -n 1p)"
write_tap "$bh/row9.json" "$cx" "$cy" 0
run "$P/nestedapp" --frames "$b/row9.json" --out "$b/row9.png" >"$bh/row9.log" 2>&1
if [ $? -eq 0 ] && grep -q 'state=taps:1,rounds:0' "$bh/row9.log"; then
  log "ok   child button state kept its box across the rebuild"
else
  log "FAIL row 9"; cat "$bh/row9.log"; fail=1
fi

echo "== row 10: app state re-renders"
run "$P/nestedapp" --out "$b/row10-before.png" >/dev/null
rect_center "$(log "$nestrects" | sed -n 2p)"
write_tap "$bh/row10.json" "$cx" "$cy" 0
run "$P/nestedapp" --frames "$b/row10.json" --out "$b/row10.png" >"$bh/row10.log" 2>&1
rc=$?
if [ $rc -eq 0 ] && grep -q 'state=taps:0,rounds:1' "$bh/row10.log"; then
  log "ok   app state survives, action fired"
else
  log "FAIL row 10 action"; cat "$bh/row10.log"; fail=1
fi
if ! python3 "$here/compare.py" "$bh/row10.png" "$bh/row10-before.png" >/dev/null 2>&1; then
  log "ok   re-render differs from the no-tap render"
else
  log "FAIL row 10: render did not change"; fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "simview/test-m3.sh: FAILED"
  exit 1
fi
echo "simview/test-m3.sh: all rows passed"
