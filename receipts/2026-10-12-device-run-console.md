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

Follow-up fix (same day): the first live run of the flag failed in `installed_bid`. It asked
`apps list` without the `--rsd HOST PORT` address in rsd and tailnet mode, so the answer was no JSON and
the script died in a Python traceback. `installed_bid` now takes the connection as extra arguments
(`--rsd` in console mode), and a non-JSON answer fails with a clear message and no traceback.

Checked, with no phone attached:

- `tests/device-run-console/run.sh`: 12 rows and 2 mutants, all stub-driven. A stub `pymobiledevice3` on
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
  message, a non-zero exit, and no Python traceback (row 12).
  Mutants: with the `timeout` dropped from the `dvt launch` line (stub sleep 12 s), the cut row no longer
  cuts; the run hits the 8 s outer limit. With the `dvt pkill` line dropped, the pkill row sees no call.
  Both mutants fail their rows in-suite.
- Fail first: the test run against `device-run.sh` before the change ends with 17 FAIL lines (rows and
  mutants), rc 1. Rows 11 and 12 fail on the first commit (6db868d, before the `installed_bid` fix) the
  same way the live run failed: no `apps list` call with the rsd args, a JSONDecodeError traceback, and
  no clear error text. After the fix the test prints `device-run-console: all checks passed`, rc 0.
- `bash tests/run.sh`: `tests/run.sh: all checks passed`, rc 0, on a host with no Swift toolchain.
  `shellcheck -S warning device-run.sh` reports 2 notes, both on lines this change did not touch.

Live phone run: not yet proven. The one live run of the flag so far (the lane owner, 2026-10-12, rsd
mode) failed in `installed_bid` before the stream; the fix above addresses exactly that failure and is
covered by rows 11 and 12. The pid-in-proclist match and the stream reports stay unverified until the
lane owner re-runs live with:

    ./device-run.sh --over-tailnet 100.x.y.z path/to/App.ipa --console 25

run from the xtool project directory whose `xtool.yml` bundle id matches the signed ipa. This receipt
makes no claim about a phone result.
