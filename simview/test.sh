#!/usr/bin/env bash
# simview M2 test: rebuild, render the demo twice, compare both against the
# golden image, and prove the negative control fails the compare.
# Exit 0 only when every check passes.
#
# The chroot wrapper sees this checkout at /work; host tools see it at its
# real path. Both name the same directories, so renders written inside the
# chroot are compared on the host through $here.
set -uo pipefail
here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)

if command -v swiftc >/dev/null 2>&1; then
  P=$here
  run() { "$@"; }
elif [ -n "${SIMVIEW_CHROOT_RUN:-}" ]; then
  P=/work
  run() { "$SIMVIEW_CHROOT_RUN" --user "$*"; }
else
  echo "SKIP  simview/test.sh: no swiftc and no SIMVIEW_CHROOT_RUN wrapper"
  exit 0
fi

bash "$here/build.sh" || exit 1
bh=$here/build  # host view of the build dir
mkdir -p "$bh"

fail=0

echo "== render twice, bytes must be identical"
run "$P/simview-demo" --out "$P/simview/build/demo1.png" || fail=1
run "$P/simview-demo" --out "$P/simview/build/demo1-again.png" || fail=1
if cmp -s "$bh/demo1.png" "$bh/demo1-again.png"; then
  echo "ok   identical bytes across two renders"
else
  echo "FAIL the two renders differ"; fail=1
fi

echo "== compare with golden (simview/compare.py states the tolerance)"
python3 "$here/compare.py" "$bh/demo1.png" "$here/golden/demo1.png" || fail=1

echo "== negative control: changed initial state must fail the compare"
sed 's/count = 0/count = 3/' "$here/../sdk-free/swiftui/HelloApp.swift" > "$bh/NegApp.swift"
run swiftc -swift-version 5 -parse-as-library -I "$P/simview/build" \
  -o "$P/simview-demo-neg" "$P/simview/build/SwiftUI.o" "$P/simview/build/NegApp.swift" || exit 1
run "$P/simview-demo-neg" --out "$P/simview/build/demo-neg.png" || exit 1
if python3 "$here/compare.py" "$bh/demo-neg.png" "$here/golden/demo1.png" >/dev/null 2>&1; then
  echo "FAIL negative control passed the golden compare"; fail=1
else
  echo "ok   negative control failed the compare as required"
fi

if [ "$fail" -ne 0 ]; then
  echo "simview/test.sh: FAILED"
  exit 1
fi
echo "simview/test.sh: all checks passed"
