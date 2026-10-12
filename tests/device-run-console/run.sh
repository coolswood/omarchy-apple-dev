#!/usr/bin/env bash
# Checks device-run.sh --console [SECONDS] with a stub pymobiledevice3, with no phone attached.
# The stub records its argv and prints canned output for apps list, apps install,
# developer dvt launch --stream, developer dvt proclist and developer dvt pkill.
#
# Rows (expected results written before the code):
#   1  launch: the stub sees "developer dvt launch <bid> --stream --rsd H P"
#   2  bound:  SECONDS cuts a launch that streams longer (stub sleeps 25 s, --console 2)
#   3  running yes: proclist holds the launched pid -> "running after N s: yes"
#   4  running no:  proclist without that pid -> "running after N s: no", exit still 0
#   5  fatal yes:  stream with "Terminating app due to uncaught exception" -> "fatal text seen: yes",
#      exit still 0 (a fatal in the stream is a report, not an error of the script)
#   6  fatal no:   clean stream -> "fatal text seen: no"
#   7  pkill:      called exactly once with the bundle id, also when the launch is cut (row 2)
#   8  foreign:    bundle id not the one just installed -> refusal, no launch call
#   9  usage:      the unknown-argument text lists --console
#   10 default:    bare --console is accepted
#   11 addressing: the stub answers apps list only when it carries --rsd H P, so the flag must
#      pass the rsd args to installed_bid (fails on code that asks without them)
#   12 bad list:   a non-JSON apps list gives a clear error and a non-zero exit, no traceback
#   13 no start:   a launch that prints no pid line within the window gives a clear stderr
#      message, running/fatal report unknown, non-zero exit, and still exactly one pkill
# Mutants (each must fail its row):
#   M1  drop the timeout in front of dvt launch -> row 2 no longer cuts (15 s outer timeout fires)
#   M2  drop the dvt pkill line -> row 7 no longer sees a pkill call
set -uo pipefail
here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
DEVICE_RUN=$here/../../device-run.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 (missing: $2)";; esac; }
not_has() { case "$1" in *"$2"*) bad "$3 (unexpected: $2)";; *) ok "$3";; esac; }

# The stub pymobiledevice3. Behavior switches: the argv log, the canned stream and proclist
# files, the launch sleep, and the app ids.
mkdir -p "$tmp/bin" "$tmp/home"
cat >"$tmp/bin/pymobiledevice3" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${STUB_LOG:?}"
applist=${STUB_APPLIST:-}
[ -n "$applist" ] || printf -v applist '{"%s": {}}' "$STUB_BID"
if [ "$1 $2" = "apps list" ]; then
  # Real pymobiledevice3 prints no JSON when it has no --rsd or --udid address to ask.
  case "$*" in
    *--rsd*)
      if [ -n "${STUB_APPLIST_TEXT:-}" ]; then printf '%s\n' "$STUB_APPLIST_TEXT"
      else printf '%s\n' "$applist"; fi ;;
    *) echo "ERROR: no device or tunnel given" >&2; exit 1 ;;
  esac
elif [ "$1 $2" = "apps install" ]; then
  echo "Install: $3"
elif [ "$1 $2 $3" = "developer dvt launch" ]; then
  [ "${STUB_PID_LINE:-1}" = 1 ] && echo "Process launched with pid 4242"
  cat "${STUB_STREAM:?}"
  sleep "${STUB_LAUNCH_SLEEP:-0}"
elif [ "$1 $2 $3" = "developer dvt proclist" ]; then
  if [ -n "${STUB_PROCLIST:-}" ]; then cat "$STUB_PROCLIST"; else echo "[]"; fi
elif [ "$1 $2 $3" = "developer dvt pkill" ]; then
  echo "Stopped process"
else
  echo "stub: unexpected call: $*" >&2
  exit 99
fi
STUB
chmod +x "$tmp/bin/pymobiledevice3"

# A minimal xtool project: device-run.sh reads the bundle id from xtool.yml here.
mkdir -p "$tmp/proj"
printf 'bundleID: com.example.app\n' >"$tmp/proj/xtool.yml"

# drive SCRIPT SECONDS-cutoff ARGS...: runs device-run.sh through the stub.
# Sets OUT (combined output) and RC. STUB_* and SECONDS-cutoff come from the caller.
OUT=; RC=0
drive() {
  local script=$1 cutoff=$2; shift 2
  : >"$tmp/log"
  OUT=$(cd "$tmp/proj" && env HOME="$tmp/home" PATH="$tmp/bin:$PATH" \
    STUB_LOG="$tmp/log" STUB_STREAM="$tmp/stream.txt" STUB_PROCLIST="$tmp/proclist.json" \
    STUB_BID=com.example.app STUB_APPLIST="${STUB_APPLIST:-}" \
    STUB_APPLIST_TEXT="${STUB_APPLIST_TEXT:-}" \
    STUB_PID_LINE="${STUB_PID_LINE:-1}" \
    STUB_LAUNCH_SLEEP="${STUB_LAUNCH_SLEEP:-0}" \
    timeout "$cutoff" bash "$script" --rsd 127.0.0.1 65002 App.ipa "$@" 2>&1)
  RC=$?
}
calls() { grep -c "$1" "$tmp/log" || true; }

printf '[{"pid": 4242, "name": "ExampleApp"}]\n' >"$tmp/proclist.json"
printf 'hello from the app\n' >"$tmp/stream.txt"

echo "== row 1: launch --stream with the rsd args"
STUB_LAUNCH_SLEEP=0 drive "$DEVICE_RUN" 60 --console 5
has "$(cat "$tmp/log")" "developer dvt launch com.example.app --stream --rsd 127.0.0.1 65002" "row 1 stub saw launch --stream with rsd args"
has "$OUT" "running after 5 s: yes" "row 1 running after 5 s: yes"
has "$OUT" "fatal text seen: no" "row 1 fatal text seen: no"
has "$OUT" "hello from the app" "row 1 stream printed"
[ "$RC" = 0 ] && ok "row 1 exit 0" || bad "row 1 exit $RC, want 0"

echo "== row 2: SECONDS cuts a long stream"
printf 'still streaming\n' >"$tmp/stream.txt"
STUB_LAUNCH_SLEEP=25 drive "$DEVICE_RUN" 15 --console 2
if [ "$RC" = 124 ]; then bad "row 2 launch not cut by 2 s"; else ok "row 2 launch cut by 2 s"; fi
has "$(cat "$tmp/log")" "developer dvt pkill --bundle com.example.app --rsd 127.0.0.1 65002" "row 2 pkill after the cut"

echo "== row 3: proclist holds the pid"
drive "$DEVICE_RUN" 60 --console 5
has "$OUT" "running after 5 s: yes" "row 3 running after 5 s: yes"

echo "== row 4: proclist without the pid"
printf '[{"pid": 99, "name": "SpringBoard"}]\n' >"$tmp/proclist.json"
drive "$DEVICE_RUN" 60 --console 5
has "$OUT" "running after 5 s: no" "row 4 running after 5 s: no"
[ "$RC" = 0 ] && ok "row 4 exit 0 (not running is a report)" || bad "row 4 exit $RC, want 0"
printf '[{"pid": 4242, "name": "ExampleApp"}]\n' >"$tmp/proclist.json"

echo "== row 5: fatal line in the stream"
printf 'Terminating app due to uncaught exception NSException\n' >"$tmp/stream.txt"
drive "$DEVICE_RUN" 60 --console 5
has "$OUT" "fatal text seen: yes" "row 5 fatal text seen: yes"
[ "$RC" = 0 ] && ok "row 5 exit 0 (fatal is a report)" || bad "row 5 exit $RC, want 0"

echo "== row 6: clean stream"
printf 'all good\n' >"$tmp/stream.txt"
drive "$DEVICE_RUN" 60 --console 5
has "$OUT" "fatal text seen: no" "row 6 fatal text seen: no"

echo "== row 7: pkill exactly once with the bundle id"
drive "$DEVICE_RUN" 60 --console 5
n=$(calls "developer dvt pkill --bundle com.example.app")
[ "$n" = 1 ] && ok "row 7 pkill exactly once" || bad "row 7 pkill called $n times, want 1"

echo "== row 8: foreign bundle id refused"
STUB_APPLIST='{"com.other.app": {}}' drive "$DEVICE_RUN" 60 --console 5
[ "$RC" != 0 ] && ok "row 8 refused (exit $RC)" || bad "row 8 exit 0, want non-zero"
has "$OUT" "not the bundle id this run installed" "row 8 refusal text"
not_has "$OUT" "developer dvt launch" "row 8 no launch call"
STUB_APPLIST=

echo "== row 9: usage text lists --console"
OUT=$(cd "$tmp/proj" && env HOME="$tmp/home" PATH="$tmp/bin:$PATH" STUB_LOG="$tmp/log" \
  timeout 10 bash "$DEVICE_RUN" --bogus 2>&1)
RC=$?
[ "$RC" = 2 ] && ok "row 9 unknown argument exits 2" || bad "row 9 exit $RC, want 2"
has "$OUT" "--console" "row 9 usage lists --console"

echo "== row 10: bare --console accepted"
drive "$DEVICE_RUN" 60 --console
[ "$RC" = 0 ] && ok "row 10 bare --console exit 0" || bad "row 10 exit $RC, want 0"

echo "== row 11: apps list goes to the rsd address"
drive "$DEVICE_RUN" 60 --console 5
has "$(cat "$tmp/log")" "apps list --rsd 127.0.0.1 65002" "row 11 apps list carries the rsd args"
has "$OUT" "running after 5 s: yes" "row 11 console reports after the list"

echo "== row 12: non-JSON apps list fails clearly"
STUB_APPLIST_TEXT='ERROR: not json' drive "$DEVICE_RUN" 60 --console 5
[ "$RC" != 0 ] && ok "row 12 non-zero exit ($RC)" || bad "row 12 exit 0, want non-zero"
has "$OUT" "apps list did not return JSON" "row 12 clear error text"
not_has "$OUT" "Traceback" "row 12 no Python traceback"
not_has "$OUT" "JSONDecodeError" "row 12 no JSONDecodeError text"

echo "== row 13: launch prints no pid line"
printf '' >"$tmp/stream.txt"
STUB_PID_LINE=0 STUB_LAUNCH_SLEEP=12 drive "$DEVICE_RUN" 15 --console 2
[ "$RC" != 0 ] && ok "row 13 non-zero exit ($RC)" || bad "row 13 exit 0, want non-zero"
has "$OUT" "launch did not start: no 'Process launched with pid' line within 2 s" "row 13 clear no-start message"
has "$OUT" "running after 2 s: unknown" "row 13 running unknown"
not_has "$OUT" "fatal text seen: no" "row 13 no false fatal=no"
n=$(calls "developer dvt pkill --bundle com.example.app")
[ "$n" = 1 ] && ok "row 13 pkill exactly once" || bad "row 13 pkill called $n times, want 1"
printf 'hello from the app\n' >"$tmp/stream.txt"

echo "== mutant M1: drop the timeout (row 2 must fail)"
sed 's/timeout "$CONSOLE_SECS" "\$PMD3" developer dvt launch/"$PMD3" developer dvt launch/' \
  "$DEVICE_RUN" >"$tmp/mut1.sh"
if [ "$(grep -c 'dvt launch' "$tmp/mut1.sh")" = "$(grep -c 'dvt launch' "$DEVICE_RUN")" ] \
  && ! grep -q 'timeout "$CONSOLE_SECS" "$PMD3" developer dvt launch' "$tmp/mut1.sh"; then
  STUB_LAUNCH_SLEEP=12 drive "$tmp/mut1.sh" 8 --console 2
  [ "$RC" = 124 ] && ok "mutant M1 failed its row (not cut within 8 s)" || bad "mutant M1 survived row 2"
else
  bad "mutant M1 edit did not apply"
fi

echo "== mutant M2: drop the pkill (row 7 must fail)"
sed '/dvt pkill/d' "$DEVICE_RUN" >"$tmp/mut2.sh"
if grep -q 'dvt launch' "$tmp/mut2.sh" && ! grep -q 'dvt pkill' "$tmp/mut2.sh"; then
  drive "$tmp/mut2.sh" 60 --console 5
  n=$(calls "dvt pkill")
  [ "$n" = 0 ] && ok "mutant M2 failed its row (no pkill call)" || bad "mutant M2 survived row 7 ($n pkill calls)"
else
  bad "mutant M2 edit did not apply"
fi

[ "$fail" = 0 ] && echo "device-run-console: all checks passed"
exit "$fail"
