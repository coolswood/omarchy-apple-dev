#!/usr/bin/env bash
# Take a Flutter app built by flutter/build.sh through the App Store path:
# stamp, dylib wrapping, distribution identity, inside-out signing, packaging,
# offline validation and (unless SHIP_SKIP_UPLOAD=1) the App Store Connect
# upload. Produces <app>/build/ios-linux/ship/Runner-<version>-<N>.ipa.
#
#   flutter/build.sh <app dir>                  # first: the unsigned build
#   flutter/ship.sh <app dir> <build number>    # then: this script
#
# Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (required; same as ship.sh),
# ASC_ENTITLEMENTS_PATH and APP_GROUPS (optional, passed to asc.py identity —
# the app's .entitlements file and its app groups, e.g. "group.example"),
# SHIP_SKIP_UPLOAD=1 to stop after validation, RELEASE_NOTES_JSON pointing at a
# Play-style release_notes.json: after the upload asc.py publish fills "What's
# New" in every store locale, attaches the build to the app version (creating
# the version if needed) and submits it for App Review.
set -euo pipefail

app=$(readlink -f "${1:?usage: ship.sh <flutter app dir> <build number>}")
build=${2:?usage: ship.sh <flutter app dir> <build number>}
here=$(dirname "$(readlink -f "$0")")
PY="$HOME/pymobile3-venv/bin/python"
ASC="$here/../tools/asc.py"
export PATH="$HOME/.local/bin:$PATH"
: "${ASC_KEY_ID:?ship.sh needs ASC_KEY_ID}" "${ASC_ISSUER_ID:?ship.sh needs ASC_ISSUER_ID}"
: "${ASC_KEY_PATH:?ship.sh needs ASC_KEY_PATH (the .p8 file)}"
export ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH

src=$app/build/ios-linux/Payload/Runner.app
[ -d "$src" ] || { echo "no $src; run flutter/build.sh first" >&2; exit 1; }

echo "== 1. Stage a writable copy =="
out=$app/build/ios-linux/ship
rm -rf "$out"
mkdir -p "$out"
cp -a "$src" "$out/Runner.app"
# SwiftPM build outputs are read-only; every later step writes into the bundle.
chmod -R u+w "$out/Runner.app"
app_dir=$out/Runner.app

echo "== 2. Stamp and wrap =="
"$PY" "$ASC" stamp "$app_dir" "$build"
"$PY" "$ASC" frameworks "$app_dir"

echo "== 3. Distribution identity =="
"$PY" "$ASC" identity "$app_dir" "$out/signing"

echo "== 4. Sign inside-out =="
team=$("$PY" -c 'import plistlib,sys; print(plistlib.load(open(sys.argv[1],"rb"))["com.apple.developer.team-identifier"])' \
  "$out/signing/entitlements.plist")
[[ "$team" =~ ^[A-Z0-9]{10}$ ]] || { echo "team id '$team' is not a bare 10-character team id" >&2; exit 1; }
"$PY" "$here/../tools/fill-team-prefix.py" --team "$team" "$app_dir"
sign_args=(--pem-file "$out/signing/key.pem" --certificate-der-file "$out/signing/cert.der" --team-name "$team")
for framework in "$app_dir"/Frameworks/*.framework; do
  [ -d "$framework" ] || continue
  rcodesign sign "${sign_args[@]}" "$framework"
done
rcodesign sign "${sign_args[@]}" --entitlements-xml-file "$out/signing/entitlements.plist" "$app_dir"

echo "== 5. Package =="
version=$("$PY" -c 'import plistlib,sys; print(plistlib.load(open(sys.argv[1],"rb"))["CFBundleShortVersionString"])' "$app_dir/Info.plist")
ipa="$out/Runner-$version-$build.ipa"
rm -f "$ipa"   # zip on an existing archive updates it: deleted files would linger
stage=$(mktemp -d)
mkdir "$stage/Payload"
cp -a "$app_dir" "$stage/Payload/"
(cd "$stage" && zip -qry "$(realpath -m "$ipa")" Payload)
rm -rf "$stage"
echo "wrote $ipa"

echo "== 6. Offline App Store validation =="
"$PY" "$ASC" validate "$ipa"

if [ -z "${SHIP_SKIP_UPLOAD:-}" ]; then
  echo "== 7. Upload to App Store Connect =="
  "$PY" "$ASC" upload "$ipa"
  if [ -n "${RELEASE_NOTES_JSON:-}" ]; then
    echo "== 8. Publish: whatsnew + build attach + review submission =="
    # If the build is still processing (publish dies on it), rerun
    #   asc.py publish <ipa> <notes.json>
    # once TestFlight shows it VALID — not this script (it would re-upload).
    "$PY" "$ASC" publish "$ipa" "$RELEASE_NOTES_JSON"
  else
    echo "RELEASE_NOTES_JSON not set: skipping whatsnew / review submission"
  fi
else
  echo "SHIP_SKIP_UPLOAD set: stopping after validation"
fi
