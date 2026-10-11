#!/usr/bin/env bash
# Build the simview module and the SwiftUI demo app with it.
# Uses native swiftc when present; otherwise runs every command through the
# chroot wrapper named by SIMVIEW_CHROOT_RUN, which must bind this checkout
# at /work (see simview/README.md).
set -euo pipefail
here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)

P=$(cd "$here/.." && pwd)  # repo root
if command -v swiftc >/dev/null 2>&1; then
  run() { "$@"; }
elif [ -n "${SIMVIEW_CHROOT_RUN:-}" ]; then
  P=/work
  run() { "$SIMVIEW_CHROOT_RUN" --user "$*"; }
else
  echo "SKIP  simview build: no swiftc and no SIMVIEW_CHROOT_RUN wrapper" >&2
  exit 1
fi

b=$P/simview/build
mkdir -p "$here/build"

run swiftc -swift-version 5 -parse-as-library -c -module-name SwiftUI \
  -emit-module-path "$b/SwiftUI.swiftmodule" \
  -o "$b/SwiftUI.o" \
  "$P/simview/Sources/SwiftUI/SwiftUI.swift"
run swiftc -swift-version 5 -parse-as-library -I "$b" \
  -o "$P/simview-demo" \
  "$b/SwiftUI.o" "$P/sdk-free/swiftui/HelloApp.swift"
run swiftc -swift-version 5 -parse-as-library -I "$b" \
  -o "$P/m3app" \
  "$b/SwiftUI.o" "$P/simview/Sources/M3App/M3App.swift"
run swiftc -swift-version 5 -parse-as-library -I "$b" \
  -o "$P/nestedapp" \
  "$b/SwiftUI.o" "$P/simview/Sources/NestedApp/NestedApp.swift"
run swiftc -swift-version 5 -parse-as-library -I "$b" \
  -o "$P/overlapapp" \
  "$b/SwiftUI.o" "$P/simview/Sources/OverlapApp/OverlapApp.swift"
run swiftc -swift-version 5 -parse-as-library -I "$b" \
  -o "$P/navdemo" \
  "$b/SwiftUI.o" "$P/simview/Sources/NavDemo/NavDemo.swift"
run swiftc -swift-version 5 -parse-as-library -I "$b" \
  -o "$P/scrolldemo" \
  "$b/SwiftUI.o" "$P/simview/Sources/ScrollDemo/ScrollDemo.swift"
echo "built $P/simview-demo, $P/m3app, $P/nestedapp, $P/overlapapp, $P/navdemo and $P/scrolldemo"
