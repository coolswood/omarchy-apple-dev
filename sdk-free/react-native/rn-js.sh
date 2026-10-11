#!/usr/bin/env bash
# Host side: bundle JS with Metro, compile to Hermes bytecode, run RN codegen.
# Outputs go to local disk (per Main 2026-10-09: no small-file writes to QNAP).
#   rn-js.sh <RNProbe dir> <OUT dir> [ENTRY]
# ENTRY defaults to rn-legacy-event-shim.js (copied from this dir into the app
# when missing). It registers a no-op legacy RCTEventEmitter callable JS module
# after the app entry loads, unless the app registered its own. Pass index.js
# to skip it. See the shim header; not verified on a phone yet.
set -euo pipefail
APP=${1:?RNProbe dir}
OUT=${2:?local out dir}
ENTRY=${3:-rn-legacy-event-shim.js}
HERE=$(cd "$(dirname "$0")" && pwd)
if [ "$ENTRY" != "index.js" ] && [ ! -f "$APP/$ENTRY" ] && [ -f "$HERE/$ENTRY" ]; then
  ionice -c3 nice -n 19 cp "$HERE/$ENTRY" "$APP/$ENTRY"
fi
mkdir -p "$OUT"
cd "$APP"

echo "== metro bundle"
ionice -c3 nice -n 19 npx react-native bundle \
  --platform ios --dev false --entry-file "$ENTRY" \
  --bundle-output "$OUT/main.jsbundle" \
  --assets-dest "$OUT/assets" 2>&1 | tail -3

echo "== hermes bytecode"
HERMESC=${HERMESC:-/mnt/qnap-public/omp-studio-offload/apple-dev/flutter-work/rn/artifacts/package/hermesc/linux64-bin/hermesc}
"$HERMESC" -O -emit-binary -out "$OUT/main.hbc" "$OUT/main.jsbundle"

echo "== codegen"
ionice -c3 nice -n 19 node node_modules/react-native/scripts/generate-codegen-artifacts.js \
  -p . -t ios -o "$OUT/codegen" 2>&1 | tail -3
echo done
