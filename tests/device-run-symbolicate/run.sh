#!/usr/bin/env bash
# Checks device-run.sh --symbolicate [DIR] with a stub pymobiledevice3 and the
# real tools/ips-symbolicate.py, with no phone attached. The stub records its
# argv, answers apps install and developer core-device launch-application, and
# copies canned .ips reports into the pull directory.
#
# Rows (expected results written before the code):
#   1  pull:    crash pull is called as "crash pull DIR --rsd 127.0.0.1 65002"
#   2  app bin: the app binary resolves a stripped frame ("appfunc+0x0
#      [resolved locally]") in the app's report
#   3  framing: the framework Mach-O resolves a frame too ("fwfunc+0x0
#      [resolved locally]"); fails when the Frameworks binaries are not passed
#   4  both:    every pulled .ips is symbolicated; each under a heading with
#      the file name, including the report of another app
#   5  ipa:     an .ipa package works the same way (unpacked first)
#   6  clean:   the .ipa temp unpack dir is removed again (TMPDIR left empty)
#   7  order:   the pull runs after the launch/console step (after dvt pkill)
#   8  nomatch: no report for this app prints the no-match line and exits 0
#   9  empty:   a pull with no .ips at all also says so and exits 0
#  10  dirdef:  without DIR the reports go to ./crash-<utc-timestamp> (created)
#  11  pullfail: a failing crash pull exits non-zero
#  12  guard:   --symbolicate without --rsd/--over-tailnet is refused, exit 2
#  13  eqform:  --symbolicate=DIR is accepted
#  14  usage:   the unknown-argument text lists --symbolicate
# Mutants (each must fail its row):
#   M1  drop the Frameworks collection -> row 3 no longer resolves
#   M2  skip the temp dir cleanup -> row 6 finds a leftover unpack dir
set -uo pipefail
here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
DEVICE_RUN=$here/../../device-run.sh
SYMTOOL=$here/../../tools/ips-symbolicate.py
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 (missing: $2)";; esac; }
not_has() { case "$1" in *"$2"*) bad "$3 (unexpected: $2)";; *) ok "$3";; esac; }

[ -f "$SYMTOOL" ] || { echo "FAIL tools/ips-symbolicate.py does not exist"; exit 1; }

# Fixtures: two arm64 Mach-O files (the app and one framework) with known
# symbols, two canned .ips reports (one for the app, one for another app),
# a fake .app bundle, and the same bundle zipped as an .ipa. Reuses the
# Mach-O assembler of tests/ips-symbolicate/make-fixtures.py.
mkdir -p "$tmp/art"
python3 - "$tmp" "$here/../ips-symbolicate/make-fixtures.py" <<'PY'
import importlib.util, json, os, plistlib, sys, zipfile
tmp, mf_path = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("mf", mf_path)
mf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mf)
fix, art = tmp + "/fix", tmp + "/art"
os.makedirs(fix, exist_ok=True)
app_bin, fw_bin = fix + "/DemoApp.bin", fix + "/MyFramework.bin"
mf.SYMBOLS = [("fwstart", 0), ("fwfunc", 0x80)]
open(fw_bin, "wb").write(mf.thin("00112233445566778899aabbccddeeff"))
mf.SYMBOLS = [("appstart", 0), ("appmain", 0x100), ("appfunc", 0x200)]
open(app_bin, "wb").write(mf.thin(mf.UUID_APP))
def report(app_name, images, frames):
    header = {"app_name": app_name, "app_version": "1.0",
              "bundleID": "com.example.app", "os_version": "iOS 27.0 (99Z)",
              "timestamp": "2026-10-12 12:00:00.00 +0000"}
    body = {"faultingThread": 0, "usedImages": images,
            "threads": [{"triggered": True, "frames": frames}]}
    return json.dumps(header) + "\n" + json.dumps(body) + "\n"
app_img = {"name": "DemoApp", "uuid": "AABBCCDD-1122-3344-5566-778899AABBCC"}
fw_img = {"name": "MyFramework", "uuid": "00112233-4455-6677-8899-AABBCCDDEEFF"}
sys_img = {"name": "libsystem_kernel.dylib",
           "uuid": "11223344-5566-7788-99AA-BBCCDDEEFF00"}
open(fix + "/DemoApp-2026-10-12-1.ips", "w").write(report(
    "DemoApp", [app_img, fw_img, sys_img],
    [{"imageIndex": 2, "symbol": "mach_msg_trap", "symbolLocation": 8},
     {"imageIndex": 0, "imageOffset": 512},
     {"imageIndex": 1, "imageOffset": 128}]))
open(fix + "/OtherApp-2026-10-12-2.ips", "w").write(report(
    "SpringBoard", [sys_img],
    [{"imageIndex": 0, "symbol": "mach_msg_trap", "symbolLocation": 4}]))
appdir = art + "/DemoApp.app"
fwdir = appdir + "/Frameworks/MyFramework.framework"
os.makedirs(fwdir, exist_ok=True)
open(appdir + "/Info.plist", "wb").write(plistlib.dumps(
    {"CFBundleExecutable": "DemoApp", "CFBundleIdentifier": "com.example.app"}))
open(appdir + "/DemoApp", "wb").write(open(app_bin, "rb").read())
open(fwdir + "/MyFramework", "wb").write(open(fw_bin, "rb").read())
with zipfile.ZipFile(art + "/App.ipa", "w") as z:
    z.write(appdir + "/Info.plist", "Payload/DemoApp.app/Info.plist")
    z.write(appdir + "/DemoApp", "Payload/DemoApp.app/DemoApp")
    z.write(fwdir + "/MyFramework",
            "Payload/DemoApp.app/Frameworks/MyFramework.framework/MyFramework")
print("fixtures ok")
PY
[ $? -eq 0 ] || { echo "FAIL fixtures"; exit 1; }

# The stub pymobiledevice3: log argv, install, launch, and crash pull.
mkdir -p "$tmp/bin" "$tmp/home"
cat >"$tmp/bin/pymobiledevice3" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${STUB_LOG:?}"
if [ "$1 $2" = "apps list" ]; then
  printf '{"com.example.app": {}}\n'
elif [ "$1 $2" = "apps install" ]; then
  echo "Install: $3"
elif [ "$1 $2 $3" = "developer dvt launch" ]; then
  echo "Process launched with pid 4242"
  cat "${STUB_STREAM:?}"
elif [ "$1 $2 $3" = "developer dvt proclist" ]; then
  echo "[{\"pid\": 4242}]"
elif [ "$1 $2 $3" = "developer dvt pkill" ]; then
  echo "Stopped process"
elif [ "$1 $2 $3" = "developer core-device launch-application" ]; then
  echo "Launched"
elif [ "$1 $2" = "crash pull" ]; then
  if [ "${STUB_CRASH_RC:-0}" != 0 ]; then exit "$STUB_CRASH_RC"; fi
  # A pull that finds no report still succeeds.
  cp "${STUB_REPORT_DIR:?}"/*.ips "$3"/ 2>/dev/null || true
else
  echo "stub: unexpected call: $*" >&2
  exit 99
fi
STUB
chmod +x "$tmp/bin/pymobiledevice3"

# A minimal xtool project: device-run.sh reads the bundle id from xtool.yml here.
mkdir -p "$tmp/proj"
printf 'bundleID: com.example.app\n' >"$tmp/proj/xtool.yml"
printf 'app output line\n' >"$tmp/stream.txt"

# drive SCRIPT PKG ARGS...: runs device-run.sh through the stub.
# Sets OUT and RC. STUB_* come from the caller. TMPDIR is a fresh empty dir so
# row 6 can check that the .ipa unpack dir is gone after the run.
OUT=; RC=0
drive() {
  local script=$1 pkg=$2; shift 2
  : >"$tmp/log"
  rm -rf "$tmp/tmpd"; mkdir -p "$tmp/tmpd"
  OUT=$(cd "$tmp/proj" && env HOME="$tmp/home" PATH="$tmp/bin:$PATH" \
    TMPDIR="$tmp/tmpd" STUB_LOG="$tmp/log" STUB_STREAM="$tmp/stream.txt" \
    STUB_REPORT_DIR="${STUB_REPORT_DIR:-$tmp/fix}" \
    STUB_CRASH_RC="${STUB_CRASH_RC:-0}" \
    timeout 60 bash "$script" --rsd 127.0.0.1 65002 "$pkg" "$@" 2>&1)
  RC=$?
}

echo "== row 1: crash pull is called with the dir and the rsd args"
drive "$DEVICE_RUN" "$tmp/art/DemoApp.app" --symbolicate "$tmp/pull"
has "$(cat "$tmp/log")" "crash pull $tmp/pull --rsd 127.0.0.1 65002" \
  "row 1 stub saw crash pull with dir and rsd args"

echo "== row 2: the app binary resolves the app's stripped frame"
has "$OUT" "DemoApp  appfunc+0x0 [resolved locally]" "row 2 app frame resolved"
has "$OUT" "== Crash report: DemoApp-2026-10-12-1.ips" "row 2 heading with file name"
[ "$RC" = 0 ] && ok "row 2 exit 0" || bad "row 2 exit $RC, want 0"

echo "== row 3: the framework Mach-O resolves its frame"
has "$OUT" "MyFramework  fwfunc+0x0 [resolved locally]" "row 3 framework frame resolved"

echo "== row 4: every pulled report is symbolicated, each under its file name"
has "$OUT" "== Crash report: OtherApp-2026-10-12-2.ips" "row 4 second report heading"
has "$OUT" "App: SpringBoard 1.0 (com.example.app)" "row 4 other app report printed"
not_has "$OUT" "no crash report matches" "row 4 no false no-match line"

echo "== row 5: an .ipa package works the same way"
drive "$DEVICE_RUN" "$tmp/art/App.ipa" --symbolicate "$tmp/pull2"
has "$OUT" "DemoApp  appfunc+0x0 [resolved locally]" "row 5 ipa app frame resolved"
has "$OUT" "MyFramework  fwfunc+0x0 [resolved locally]" "row 5 ipa framework frame resolved"
[ "$RC" = 0 ] && ok "row 5 exit 0" || bad "row 5 exit $RC, want 0"

echo "== row 6: the .ipa temp unpack dir is removed again"
[ -z "$(ls -A "$tmp/tmpd" 2>/dev/null)" ] && ok "row 6 TMPDIR left empty" \
  || bad "row 6 leftover files in TMPDIR: $(ls -A "$tmp/tmpd" 2>/dev/null)"

echo "== row 7: the pull runs after the launch/console step"
drive "$DEVICE_RUN" "$tmp/art/DemoApp.app" --console 3 --symbolicate "$tmp/pull3"
pull_line=$(grep -n '^crash pull ' "$tmp/log" | head -n1 | cut -d: -f1)
kill_line=$(grep -n 'developer dvt pkill' "$tmp/log" | head -n1 | cut -d: -f1)
if [ -n "$pull_line" ] && [ -n "$kill_line" ] && [ "$pull_line" -gt "$kill_line" ]; then
  ok "row 7 pull after console"
else
  bad "row 7 pull line $pull_line not after pkill line $kill_line"
fi

echo "== row 8: no report for this app says so and exits 0"
mkdir -p "$tmp/only-other"
cp "$tmp/fix/OtherApp-2026-10-12-2.ips" "$tmp/only-other/"
STUB_REPORT_DIR=$tmp/only-other drive "$DEVICE_RUN" "$tmp/art/DemoApp.app" --symbolicate "$tmp/pull4"
[ "$RC" = 0 ] && ok "row 8 exit 0" || bad "row 8 exit $RC, want 0"
has "$OUT" "no crash report matches app DemoApp in $tmp/pull4" "row 8 no-match line"
has "$OUT" "== Crash report: OtherApp-2026-10-12-2.ips" "row 8 other report still printed"

echo "== row 9: a pull with no .ips at all also says so and exits 0"
mkdir -p "$tmp/empty-pull"
STUB_REPORT_DIR=$tmp/empty-pull drive "$DEVICE_RUN" "$tmp/art/DemoApp.app" --symbolicate "$tmp/pull5"
[ "$RC" = 0 ] && ok "row 9 exit 0" || bad "row 9 exit $RC, want 0"
has "$OUT" "no .ips report in $tmp/pull5" "row 9 empty pull message"
has "$OUT" "no crash report matches app DemoApp in $tmp/pull5" "row 9 no-match line"

echo "== row 10: without DIR the reports go to ./crash-<utc-timestamp>"
rm -f "$tmp/proj"/crash-*
drive "$DEVICE_RUN" "$tmp/art/DemoApp.app" --symbolicate
made=$(cd "$tmp/proj" && ls -d crash-* 2>/dev/null | head -n1)
if [ -n "$made" ] && [ -f "$tmp/proj/$made/DemoApp-2026-10-12-1.ips" ]; then
  ok "row 10 default dir $made created and used"
else
  bad "row 10 no crash-* dir with reports under the project dir"
fi
has "$(cat "$tmp/log")" "crash pull ./crash-" "row 10 pull used the default dir"

echo "== row 11: a failing crash pull exits non-zero"
STUB_CRASH_RC=7 drive "$DEVICE_RUN" "$tmp/art/DemoApp.app" --symbolicate "$tmp/pull6"
[ "$RC" != 0 ] && ok "row 11 non-zero exit ($RC)" || bad "row 11 exit 0, want non-zero"
has "$OUT" "crash pull failed" "row 11 failure message"

echo "== row 12: --symbolicate without an rsd or tailnet mode is refused"
OUT=$(cd "$tmp/proj" && env HOME="$tmp/home" PATH="$tmp/bin:$PATH" STUB_LOG="$tmp/log" \
  timeout 10 bash "$DEVICE_RUN" --symbolicate 2>&1)
RC=$?
[ "$RC" = 2 ] && ok "row 12 refused exit 2" || bad "row 12 exit $RC, want 2"
has "$OUT" "--symbolicate works with --rsd or --over-tailnet" "row 12 mode guard message"

echo "== row 13: --symbolicate=DIR form"
drive "$DEVICE_RUN" "$tmp/art/DemoApp.app" "--symbolicate=$tmp/pull7"
has "$(cat "$tmp/log")" "crash pull $tmp/pull7 --rsd 127.0.0.1 65002" \
  "row 13 eq form used the given dir"
[ "$RC" = 0 ] && ok "row 13 exit 0" || bad "row 13 exit $RC, want 0"

echo "== row 14: usage text lists --symbolicate"
OUT=$(cd "$tmp/proj" && env HOME="$tmp/home" PATH="$tmp/bin:$PATH" STUB_LOG="$tmp/log" \
  timeout 10 bash "$DEVICE_RUN" --bogus 2>&1)
RC=$?
[ "$RC" = 2 ] && ok "row 14 unknown argument exits 2" || bad "row 14 exit $RC, want 2"
has "$OUT" "--symbolicate" "row 14 usage lists --symbolicate"

echo "== mutant M1: drop the Frameworks collection (row 3 must fail)"
sed '/^  for fw in/,/^  done$/d' "$DEVICE_RUN" >"$tmp/mut1.sh"
if ! grep -q 'Frameworks/\*\.framework' "$tmp/mut1.sh" && grep -q 'crash pull' "$tmp/mut1.sh"; then
  drive "$tmp/mut1.sh" "$tmp/art/DemoApp.app" --symbolicate "$tmp/pullm1"
  if case "$OUT" in *"MyFramework  fwfunc+0x0 [resolved locally]"*) false;; esac; then
    ok "mutant M1 failed its row (framework frame unresolved)"
  else
    bad "mutant M1 survived row 3"
  fi
else
  bad "mutant M1 edit did not apply"
fi

echo "== mutant M2: skip the temp dir cleanup (row 6 must fail)"
sed 's/rm -rf "\$tmpapp" || true/:/' "$DEVICE_RUN" >"$tmp/mut2.sh"
if ! grep -q 'rm -rf "$tmpapp" || true' "$tmp/mut2.sh" && grep -q 'mktemp -d' "$tmp/mut2.sh"; then
  drive "$tmp/mut2.sh" "$tmp/art/App.ipa" --symbolicate "$tmp/pullm2"
  if [ -z "$(ls -A "$tmp/tmpd" 2>/dev/null)" ]; then
    bad "mutant M2 survived row 6 (no leftover found)"
  else
    ok "mutant M2 failed its row (leftover unpack dir found)"
  fi
else
  bad "mutant M2 edit did not apply"
fi

[ "$fail" = 0 ] && echo "device-run-symbolicate: all checks passed"
exit "$fail"
