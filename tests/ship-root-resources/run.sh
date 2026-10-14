#!/usr/bin/env bash
# Checks ship.sh step 2 (the for-target loop) against a synthetic SwiftPM
# project: <App>.app with <Pkg>_<Target>.bundle resource bundles and one appex
# under PlugIns. The loop is extracted verbatim from ship.sh; nothing else of
# the script runs (steps 1, 3-8 need xtool, actool and rcodesign).
#
# Rows (expected results written before the code):
#   1  default:   with ROOT_RESOURCES unset, the bundle's PrivacyInfo.xcprivacy
#     moves to the app and appex roots, Base.lproj/Main.storyboardc to the app
#     root, Inject.js to the appex root; en.lproj, es.lproj, sound.wav,
#     data.json and the nested Sub/ tree stay in the bundle
#   2  opt-in:    ROOT_RESOURCES='*.lproj *.wav' moves en.lproj, es.lproj,
#     sound.wav and Base.lproj (storyboardc inside) to the app root; the
#     nested Sub/en.lproj and Sub/PrivacyInfo.xcprivacy stay in the bundle
#     (a find -path pattern must not match below the bundle top)
#   3  set -f:    a stray foo.lproj in the project dir must not shrink the
#     pattern; *.lproj still moves en.lproj
#   4  empty:     ROOT_RESOURCES='' behaves like unset
#   5  appex:     the extension's bundle gets the same ROOT_RESOURCES moves
#     (tone.wav lands at the appex root)
# Mutants (each must fail its row):
#   M1  drop the set -f line -> row 3 no longer moves en.lproj (the pattern
#       expands against the project dir)
#   M2  drop the -path ./PrivacyInfo.xcprivacy term -> row 1 no longer moves
#       the manifest
#   M3  replace ${ROOT_RESOURCES:-} with $ROOT_RESOURCES -> row 1 (variable
#       unset) fails: ship.sh runs under set -u, so an unguarded use aborts
# usage: run.sh [path-to-ship.sh]   default: ../../ship.sh (repo checkout)
set -uo pipefail
here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
SHIP=${1:-$here/../../ship.sh}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
# drive <projdir> [ROOT_RESOURCES]: runs the step-2 loop of $SHIP in projdir. Without the second
# argument ROOT_RESOURCES is UNSET (ship.sh runs under set -u, so unset must work); an empty second
# argument sets it to the empty string.
drive() {
  local proj=$1
  [ -d "$proj" ] || { bad "drive: no project at $proj"; return 1; }
  (
    set -euo pipefail
    loop=$(mktemp)
    awk '/^for target in "\$app" "\$app"\/PlugIns\/\*\.appex; do$/,/^done$/' "$SHIP" >"$loop"
    [ -s "$loop" ] || { echo "no step-2 loop found in $SHIP" >&2; exit 9; }
    cd "$proj"
    PY=python3
    app=xtool/Demo.app
    if [ "$#" -ge 2 ]; then
      ROOT_RESOURCES=$2
      export ROOT_RESOURCES
    else
      unset ROOT_RESOURCES
    fi
    source "$loop"
  )
}
# mkproj <projdir>: the synthetic project. One app bundle and one appex.
mkproj() {
  local root=$1
  rm -rf "$root"
  local app="$root/xtool/Demo.app"
  local appex="$app/PlugIns/DemoExt.appex"
  local b="$app/Pkg_Demo.bundle"
  local eb="$appex/Pkg_DemoExt.bundle"
  mkdir -p "$app/PlugIns" \
    "$b/en.lproj" "$b/es.lproj" "$b/Base.lproj/Main.storyboardc" \
    "$b/Sub/en.lproj" "$appex" "$eb/en.lproj"
  cat >"$app/Info.plist" <<'P'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.example.demo</string></dict></plist>
P
  cat >"$appex/Info.plist" <<'P'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.example.demo.ext</string>
  <key>NSExtension</key><dict><key>NSExtensionAttributes</key><dict>
    <key>NSExtensionJavaScriptPreprocessingFile</key><string>Inject</string>
  </dict></dict></dict></plist>
P
  echo manifest-main >"$b/PrivacyInfo.xcprivacy"
  echo strings-en >"$b/en.lproj/Localizable.strings"
  echo infoplist-es >"$b/es.lproj/InfoPlist.strings"
  echo wav-data >"$b/sound.wav"
  echo '{"json": true}' >"$b/data.json"
  echo storyboardc-info >"$b/Base.lproj/Main.storyboardc/Info.plist"
  echo nested-strings >"$b/Sub/en.lproj/x.strings"
  echo manifest-nested >"$b/Sub/PrivacyInfo.xcprivacy"
  echo manifest-ext >"$eb/PrivacyInfo.xcprivacy"
  echo js-inject >"$eb/Inject.js"
  echo strings-ext-en >"$eb/en.lproj/Localizable.strings"
  echo wav-tone >"$eb/tone.wav"
}
at() { # at <projdir> <path-under-proj> <label>
  [ -e "$1/$2" ] && ok "$3" || bad "$3 (missing $2)"
}
not_at() {
  [ -e "$1/$2" ] && bad "$3 (unexpected $2)" || ok "$3"
}
app() { echo "$tmp/$1/xtool/Demo.app"; }
bnd() { echo "$tmp/$1/xtool/Demo.app/Pkg_Demo.bundle"; }
appex() { echo "$tmp/$1/xtool/Demo.app/PlugIns/DemoExt.appex"; }
ebnd() { echo "$tmp/$1/xtool/Demo.app/PlugIns/DemoExt.appex/Pkg_DemoExt.bundle"; }

echo "== row 1: default (ROOT_RESOURCES unset)"
mkproj "$tmp/r1"
drive "$tmp/r1" || bad "row 1 loop exited nonzero"
at "$(app r1)" PrivacyInfo.xcprivacy "row 1 manifest at the app root"
at "$(appex r1)" PrivacyInfo.xcprivacy "row 1 manifest at the appex root"
at "$(app r1)" Base.lproj/Main.storyboardc "row 1 storyboardc at the app root"
at "$(appex r1)" Inject.js "row 1 extension js at the appex root"
not_at "$(bnd r1)" PrivacyInfo.xcprivacy "row 1 manifest gone from the bundle"
not_at "$(ebnd r1)" PrivacyInfo.xcprivacy "row 1 manifest gone from the ext bundle"
not_at "$(bnd r1)" Base.lproj/Main.storyboardc "row 1 storyboardc gone from the bundle"
at "$(bnd r1)" en.lproj/Localizable.strings "row 1 en.lproj stays in the bundle"
at "$(bnd r1)" es.lproj/InfoPlist.strings "row 1 es.lproj stays in the bundle"
at "$(bnd r1)" sound.wav "row 1 sound.wav stays in the bundle"
at "$(bnd r1)" data.json "row 1 data.json stays in the bundle"
at "$(bnd r1)" Sub/PrivacyInfo.xcprivacy "row 1 nested manifest stays in the bundle"
at "$(bnd r1)" Sub/en.lproj/x.strings "row 1 nested strings stay in the bundle"

echo "== row 2: ROOT_RESOURCES='*.lproj *.wav'"
mkproj "$tmp/r2"
drive "$tmp/r2" '*.lproj *.wav'
at "$(app r2)" en.lproj/Localizable.strings "row 2 en.lproj at the app root"
at "$(app r2)" es.lproj/InfoPlist.strings "row 2 es.lproj at the app root"
at "$(app r2)" sound.wav "row 2 sound.wav at the app root"
at "$(app r2)" Base.lproj/Main.storyboardc "row 2 Base.lproj moves with the storyboardc"
at "$(bnd r2)" Sub/en.lproj/x.strings "row 2 nested lproj stays in the bundle"
not_at "$(app r2)" Sub/en.lproj/x.strings "row 2 no mirrored Sub tree at the app root"
at "$(bnd r2)" Sub/PrivacyInfo.xcprivacy "row 2 nested manifest stays in the bundle"
not_at "$(bnd r2)" en.lproj "row 2 top-level en.lproj gone from the bundle"

echo "== row 3: a stray *.lproj file in the project dir (set -f)"
mkproj "$tmp/r3"
: >"$tmp/r3/foo.lproj"
drive "$tmp/r3" '*.lproj'
at "$(app r3)" en.lproj/Localizable.strings "row 3 pattern stayed literal: en.lproj moved"
at "$(app r3)" es.lproj/InfoPlist.strings "row 3 es.lproj moved too"

echo "== row 4: ROOT_RESOURCES empty behaves like unset"
mkproj "$tmp/r4"
drive "$tmp/r4" ''
at "$(app r4)" PrivacyInfo.xcprivacy "row 4 manifest at the app root"
at "$(bnd r4)" en.lproj/Localizable.strings "row 4 en.lproj stays in the bundle"
at "$(bnd r4)" sound.wav "row 4 sound.wav stays in the bundle"

echo "== row 5: the extension bundle gets the same ROOT_RESOURCES moves"
mkproj "$tmp/r5"
drive "$tmp/r5" '*.wav'
at "$(appex r5)" tone.wav "row 5 tone.wav at the appex root"
not_at "$(ebnd r5)" tone.wav "row 5 tone.wav gone from the ext bundle"

echo "== mutant M1: drop the set -f line (row 3 must fail)"
sed '/set -f  #/d; /^  set +f$/d' "$SHIP" >"$tmp/m1.sh"
if [ "$(grep -c 'set -f' "$SHIP")" -gt 0 ] && [ "$(grep -c 'set -f' "$tmp/m1.sh")" = 0 ]; then
  mkproj "$tmp/m1p"
  : >"$tmp/m1p/foo.lproj"
  old=$SHIP
  SHIP=$tmp/m1.sh
  drive "$tmp/m1p" '*.lproj'
  SHIP=$old
  not_at "$(app m1p)" en.lproj "M1 without set -f the pattern expands and nothing moves"
else
  bad "M1 could not build the mutant (no set -f in $SHIP?)"
fi

echo "== mutant M2: drop the -path ./PrivacyInfo.xcprivacy term (row 1 must fail)"
sed 's/ -o -path \.\/PrivacyInfo\.xcprivacy//' "$SHIP" >"$tmp/m2.sh"
if [ "$(grep -c 'PrivacyInfo.xcprivacy' "$tmp/m2.sh")" -lt "$(grep -c 'PrivacyInfo.xcprivacy' "$SHIP")" ]; then
  mkproj "$tmp/m2p"
  old=$SHIP
  SHIP=$tmp/m2.sh
  drive "$tmp/m2p"
  SHIP=$old
  at "$(bnd m2p)" PrivacyInfo.xcprivacy "M2 without the term the manifest stays in the bundle"
else
  bad "M2 could not build the mutant"
fi

echo "== mutant M3: \${ROOT_RESOURCES:-} becomes \$ROOT_RESOURCES (row 1, unset, must fail under set -u)"
sed 's/\${ROOT_RESOURCES:-}/$ROOT_RESOURCES/' "$SHIP" >"$tmp/m3.sh"
if ! cmp -s "$tmp/m3.sh" "$SHIP"; then
  mkproj "$tmp/m3p"
  old=$SHIP
  SHIP=$tmp/m3.sh
  if drive "$tmp/m3p" >/dev/null 2>&1; then
    bad "M3 an unguarded \$ROOT_RESOURCES passed with the variable unset"
  else
    ok "M3 an unguarded \$ROOT_RESOURCES aborts the unset run"
  fi
  SHIP=$old
else
  bad "M3 could not build the mutant (no \${ROOT_RESOURCES:-} in $SHIP?)"
fi

[ "$fail" = 0 ] && echo "ship-root-resources: all checks passed"
exit "$fail"
