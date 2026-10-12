# Receipt: device-run.sh --console, branch stream-console, 2026-10-12

What changed: `device-run.sh --rsd` and `--over-tailnet` take `--console [SECONDS]` (default 20). After the
install it launches the app with `developer dvt launch <bundle id> --stream` under `timeout`. It prints the
app's stdout and stderr while the stream runs. It then reports `running after N s: yes/no` (the launched
pid in `developer dvt proclist`) and `fatal text seen: yes/no` (an `uncaught exception` or
`Terminating app` line in the stream). It stops the app with `developer dvt pkill --bundle <id>`.
One flag serves both paths: `--rsd` against a USB tunnel (cable), and `--over-tailnet`. Both hold the RSD
address the script already has. The flag refuses to stream when the bundle id in `xtool.yml` is not the
app just installed. Exit code: 0 when the launch started, non-zero when it did not. A fatal line in the
stream is a report about the app, not an error of the script.

Follow-up fixes (same day), each driven by a live run of the flag and covered by a stub row:

- `installed_bid` asked `apps list` without the `--rsd HOST PORT` address in rsd and tailnet mode. The
  answer carried no JSON. The script died in a Python traceback. It now takes the connection as extra
  arguments (`--rsd` in console mode). A non-JSON answer fails with a clear message (rows 11, 12).
- A launch that never started streamed nothing, so no `Process launched with pid` line appeared. A
  phone locked for hours refuses launches. The old code reported plain `no` twice and exited 0. It
  now reports `launch did not start` on stderr. Both report lines are `unknown`. It exits non-zero
  and still stops the app once (row 13).
- `dvt launch` writes the pid line as a plain `print()` into a pipe. Block-buffered, `timeout`'s
  SIGTERM ends the tool with no flush and the line never reaches the stream file. The launch
  invocation is now prefixed with `PYTHONUNBUFFERED=1` so the line flushes through the pipe into
  the stream (row 14). Measured (w7K, 2026-10-12): the real tool, with stdout redirected to a file
  through `rn-ct.sh` and SIGTERM at 25 s, did flush the pid line. 417 bytes held in the stream file.
  The pipe-buffering effect on the real tool is unmeasured live. The live run that drove this fix
  went through the pipe form and got 0 bytes because the phone refused the launch, not because the
  line was buffered. A Ctrl-C exit (130) during the stream is now an interrupt: the app is stopped,
  `interrupted` is printed on stderr, and the script exits 130 (row 15). The `--console=SECONDS`
  form is accepted. The unknown argument message lists both forms. The mode guard refuses
  `--console` on modes without an RSD address (rows 16, 17).

The pid-line format (`Process launched with pid <N>`) was cross-checked against the live launch in
`receipts/2026-10-08-flutter-ios.md` line 44, which holds the captured line `Process launched with pid
1086` from a `dvt launch XTL-<team>.com.example.helloOmarchy` run.

Checked, with no phone attached:

- `tests/device-run-console/run.sh`: 17 rows and 2 mutants, all stub-driven. A stub `pymobiledevice3` on
  PATH records its argv and prints canned output. It answers `apps list`, `apps install`,
  `developer dvt launch --stream`, `developer dvt proclist` and `developer dvt pkill`. The test runs
  `device-run.sh --rsd 127.0.0.1 65002 App.ipa --console ...` against it.
  Rows: the stub sees `launch com.example.app --stream --rsd 127.0.0.1 65002`. A launch that streams
  longer than SECONDS is cut by `timeout` (stub sleeps 25 s, `--console 2`). `running after 5 s: yes`
  when proclist holds the launched pid, `: no` when it does not; exit stays 0. `fatal text seen: yes`
  for a canned `Terminating app due to uncaught exception` stream, `: no` for a clean one; exit stays 0
  in both. `dvt pkill` runs exactly once with the bundle id, also when the launch is cut. A foreign
  bundle id is refused with no launch call. The unknown-argument usage text lists `--console`. Bare
  `--console` is accepted. The stub answers `apps list` only when the call carries the rsd args, so the
  flag must pass them to `installed_bid` (row 11). A non-JSON `apps list` answer fails with a clear
  message, a non-zero exit, and no Python traceback (row 12). A launch that prints no pid line within
  the window reports `launch did not start` on stderr, `running after N s: unknown` and
  `fatal text seen: unknown`, exits non-zero, and still stops the app once (row 13); the code before
  this fix printed a plain `no` for both reports and exited 0. A python launch stub that `print()`s
  the pid line into the pipe and sleeps reaches the stream file only because `PYTHONUNBUFFERED=1` is
  set on the launch command (row 14); without it the line stays in the pipe buffer and `timeout`
  SIGTERMs with no flush. A launch that exits 130 is treated as an interrupt: `interrupted` on
  stderr, exit 130, one pkill, no `launch failed` text (row 15). `--console` without `--rsd` or
  `--over-tailnet` is refused with exit 2 (row 16). The `--console=SECONDS` form is accepted and
  runs SECONDS (row 17). Rows 16 and 17 cover guards present since the first console commit and
  fail against the code before the change because the flag does not exist there.
  Mutants: with the `timeout` dropped from the `dvt launch` line (stub sleep 12 s), the cut row no longer
  cuts; the run hits the 8 s outer limit. With the `dvt pkill` line dropped, the pkill row sees no call.
  Both mutants fail their rows in-suite.
- Fail first: the test at the time of the first commit (10 rows, 2 mutants) against the code before
  the change (origin/main `f19afe9`) ends with 17 FAIL lines, rc 1. Rows 11 and 12 fail on the next
  commit (9d2c2c3, before the `installed_bid` fix) the same way the live run failed: no `apps list`
  call with the rsd args, a JSONDecodeError traceback, and no clear error text. Row 13 fails on the
  third commit (ac36cbf, before the no-pid-line fix) the way the second live run failed: exit 0,
  `running after N s: no`, `fatal text seen: no`, no message. Rows 14 and 15 fail on the fourth
  commit (adeee3f, before the unbuffered and interrupt fixes): row 14's python launch stub prints
  the pid line into the pipe without flushing and the line never reaches the stream (PYTHONUNBUFFERED
  was missing); row 15 reports a Ctrl-C exit as a failed launch. With w7K's wider measurement using
  the 13-row test as of adeee3f, the FAIL count against `f19afe9` is 23; the current 17-row test
  gives 31. After the fixes the test prints `device-run-console: all checks passed`, rc 0.
- `bash tests/run.sh`: `tests/run.sh: all checks passed`, rc 0, on a host with no Swift toolchain.
  `shellcheck -S warning device-run.sh` reports 2 notes, both on lines this change did not touch.

Live phone run: not yet proven. Three live runs of the flag so far (the lane owner and w7K, 2026-10-12,
rsd mode) failed before the stream and drove the four fixes above; rows 11 to 15 cover exactly those
failures. Not checked until the lane owner re-runs live: a stream from a running app (so the pid-in-proclist
match, `running after N s: yes`, and the `fatal text seen` lines stay unverified against real output).
The pipe-buffering effect on the real tool, with the fix in place, is also unmeasured live. Re-run with:

    ./device-run.sh --over-tailnet 100.x.y.z path/to/App.ipa --console 25

run from the xtool project directory whose `xtool.yml` bundle id matches the signed ipa. This receipt
makes no claim about a phone result.
