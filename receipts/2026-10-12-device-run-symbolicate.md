# Receipt: device-run.sh --symbolicate, branch crashpull-device-run, 2026-10-12

What changed: `device-run.sh --rsd` and `--over-tailnet` take `--symbolicate [DIR]`
(`--symbolicate=DIR` also works). After the launch or console step the run pulls the
phone's crash reports with `pymobiledevice3 crash pull DIR --rsd HOST PORT`. DIR
defaults to `./crash-<utc-timestamp>` in the project directory and is created. Then
each `*.ips` in the pull dir prints under a heading with its file name through
`tools/ips-symbolicate.py`. The tool gets the installed app binary and every Mach-O
under the app's Frameworks directory as `--binary`. An `.ipa` package is unpacked to
a temp dir first; every exit path removes that temp dir again. A report for another
app prints too. When no report matches the app executable name, the run prints
`no crash report matches app <exe> in <dir>` and exits 0. Only a failed pull exits
non-zero. A report the tool cannot read prints a warning and does not change the
exit code. The flag is refused in the modes with no RSD address, like `--console`.

Test: `tests/device-run-symbolicate/run.sh` stubs `pymobiledevice3` and uses the
real `tools/ips-symbolicate.py` on synthetic arm64 fixtures (assembled with the
Mach-O builder of the ips-symbolicate test). 14 rows and 2 mutation checks. Stub
results on this branch, 2026-10-12:

- crash pull is called as `crash pull DIR --rsd 127.0.0.1 65002`, with an explicit
  DIR, with the default DIR, and with the `--symbolicate=DIR` form.
- The app binary resolves a stripped frame (`DemoApp  appfunc+0x0 [resolved
  locally]`). The framework Mach-O resolves its own frame (`MyFramework  fwfunc+0x0
  [resolved locally]`). Mutant M1 (drop the Frameworks collection) leaves the
  framework frame unresolved, so its row fails.
- An `.ipa` package symbolicates the same way, and no temp unpack dir is left in
  TMPDIR. Mutant M2 (skip the cleanup) leaves the unpack dir, so its row fails.
- Every pulled report is symbolicated, each under a heading with the file name. The
  pull runs after the console step; the call log holds pkill before crash pull.
- No report for the app, or an empty pull, prints the no-match line and exits 0.
- A failing crash pull exits non-zero with `crash pull failed`. The flag without
  `--rsd` or `--over-tailnet` exits 2. The unknown-argument usage lists
  `--symbolicate`.

All rows fail on unmodified `main`: the flag is unknown there, so every run of the
suite exits 2.

Live phone run: not yet. The lane owner proves the flag with one command from an
xtool project directory:

    <repo>/device-run.sh --rsd HOST PORT App.ipa --symbolicate

HOST and PORT are the RSD address of a tunnel the host already holds, for example
from `sudo pymobiledevice3 lockdown start-tunnel`. A crash of the app in the same
run fills the pull dir. A phone with no crash report still exits 0 with the
no-match line.
