# Receipt: venv resolved interpreter, branch venv-resolve-python, 2026-10-13

What changed: `install-toolchain.sh` now builds the pymobiledevice3 venv from the resolved interpreter.
The resolved path comes from `readlink -f "$(command -v python3)"`. The script prints the path and the
version. Step 4 and `--repair` share one health check. The venv is healthy only when its python imports
`cryptography` and `pymobiledevice3`. An unhealthy or missing venv is removed and rebuilt from the
current interpreter. Then `pymobiledevice3` is reinstalled.

The removal runs only after a guard accepts the path. The raw string and its fully resolved path must
both sit under `$HOME`, with at least one character past the slash. An empty path is refused. A relative
path is refused. A path outside `$HOME` is refused. `$HOME` itself and `$HOME/..` are refused too.

All rows run against stubs. The stubs are fake interpreters, a fake `python -m venv`, a fake venv python
with a marker file for imports, and a fake `pip`. There is no network and no real venv build. The
contributor's real-world failure was not reproduced. The report was taken as exact.

Failing first, against the unmodified `origin/main` installer (`INSTALLER` points the test at it):

```
$ INSTALLER=/tmp/main-install-toolchain.sh bash tests/install-venv/run.sh
== install-venv: installer=/tmp/main-install-toolchain.sh
note: no venv helpers found; rows will fail (fix not applied?)
FAIL resolved: venv_ensure rc 127: _: line 6: venv_ensure: command not found
FAIL kept: setup did not create exactly one venv
FAIL rebuilt: rc 127: _: line 6: venv_ensure: command not found
FAIL guard-empty: no refusal message: _: line 6: venv_reset: command not found
rc=1
```

After the fix, the same suite:

```
$ bash tests/install-venv/run.sh
ok   resolved: created from the resolved interpreter, path and version printed
ok   kept: healthy venv left alone after the symlink moved
ok   rebuilt: unhealthy venv removed and rebuilt from the new interpreter
ok   guard: empty, relative, outside-HOME, HOME itself, and HOME/.. refused
ok   mutation-readlink: caught
ok   mutation-health: caught
ok   mutation-guard: caught
rc=0
```

Mutation checks proven in-suite. Each one mutates the extracted helper block and asserts a row fails.

- `readlink -f` dropped from creation: the `resolved` row fails. The venv records the symlink.
- `venv_healthy` neutered to always true: the `rebuilt` row fails. The broken venv stays.
- The `$HOME` guard pattern opened to `*`: the `guard` rows fail. Outside-HOME paths would be removed.

Full suite on the branch, Linux host without Swift:

```
$ bash tests/run.sh
...
tests/run.sh: all checks passed
rc=0
```

Not checked here: a real `mise`/`asdf` toolchain swap on a phone-capable host. Also not checked: a real
venv build, and `--repair` on real hardware. The suite proves the logic against stubs only.

Follow-up (same day, review comment on PR #56): `--repair` ran the venv check only in the full-mode path,
after the SDK work. The no-xcode path execs `sdk-free/setup.sh` and never reached it. The check now runs
at the top of the `--repair` block, before the mode split, so both modes rebuild a broken venv first. New
rows run the extracted `--repair` block against stubs with one order log. An explicit no-xcode mode and a
saved no-xcode mode each record the rebuild line before the `setup` line. A healthy venv stays untouched
while setup still runs. A full-mode repair still rebuilds. On commit 16109fb5 the rows `repair-explicit`
and `repair-saved` fail: the order log holds `setup` alone, so the rebuild never ran. A fourth in-suite
mutation deletes the early call, and `repair-explicit` catches it. `bash tests/run.sh` ends `all checks
passed` on the Linux host.

Second follow-up (same day, review RED at 30e1a2f and CHANGES at 91891c8e): two regressions, both fixed.

- The guard compared the resolved venv path with the raw `$HOME`. A symlinked `$HOME`, or a `$HOME` with a
  trailing slash, made the first install refuse. `venv_path_ok` now resolves `$HOME` too and compares the
  resolved venv path with the resolved `$HOME`. New rows: `home-symlink` and `home-slash` reach venv
  creation. The five refusal cases still refuse. A new mutation compares against the raw `$HOME` again,
  and `home-symlink` catches it.
- `readlink -f "$(command -v python3)"` returns the mise binary when `python3` is a mise shim, and the
  script ran `mise -m venv`. `venv_create` now asks the interpreter for its own real path with
  `python3 -c 'import os,sys; print(os.path.realpath(sys.executable))'`. The stub interpreter gained a
  `-c` branch, and a new `shim` row runs creation through a fake mise-style shim: the venv is created by
  the real stub interpreter, never by the shim. The readlink mutation now swaps the probe for the raw
  PATH entry, and `resolved` catches it.

Optional review items also taken: `venv_create` prints `python3 not found on PATH` and returns 1 when
there is no `python3`, and `venv_reset` returns 1 instead of calling `exit` inside the helper. Not taken:
re-running `venv_healthy` after `venv_create`; that one stayed open with the reviewer. The suite is now
15 rows and 5 mutation checks, all against stubs. `bash tests/run.sh` ends `all checks passed`.
