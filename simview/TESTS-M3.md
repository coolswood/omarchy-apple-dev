# M3 test expectations

Written before the M3 code, per `docs/SIM-INPUT-MODEL.md`. `simview/test-m3.sh`
checks each row. It fails if a row does not match. One app drives the rows:
`m3app`, built from `simview/Sources/M3App/M3App.swift`. It has two buttons.
Button#1 shows the state in its label, so a tap changes pixels inside the
button box. The demo app `simview-demo` also gets one tap check, because its
source must stay unchanged and it must keep working.

The runner prints each button rect as `button id=N rect=x,y,w,h` before the
frame log. The tests read tap points from those rects. No test hard codes a
layout offset.

Tolerances, stated here: log comparison is exact bytes. PNG comparison is
`simview/compare.py`: 0 differing pixels, 0 per-channel difference.

| # | Row | Input | Expected |
|---|-----|-------|----------|
| 0 | Demo app tap | `simview-demo --frames tap.json --out after.png`, tap at the Button#1 rect center | Exit 0. Log has `target=Button#1` and `state=count:1`. Log line shape is `t=<t> finger=<n> <phase> (<x>,<y>) target=<t> state=<s> render=ok`. |
| 1 | Tap inside a button | `m3app`, tap at Button#1 center, `--out after.png`; no-tap render to `before.png` first | Exit 0. The `ended` log line shows `state=count:1`. No line shows any other count value, so the action ran once. `before.png` and `after.png` differ inside the Button#1 rect. |
| 2 | Press inside, move out, lift outside | frames: `began` at Button#1 center, `moved` 60 points left, `ended` there | Exit 0. All three lines name `target=Button#1`: the target is fixed at touch down. Every line shows `state=count:0`. No action. |
| 3 | Out and back, lift inside | frames: `began` at center, `moved` out, `moved` back to center, `ended` at center | Exit 0. The `ended` line shows `state=count:1`. No line shows any other count value. One action. |
| 4 | Drag across a second button | frames: `began` on Button#1, `moved` to Button#2 center, `ended` there | Exit 0. Every line names `target=Button#1`, never Button#2. Every line shows `state=count:0`. No action on either button. |
| 5 | Tap on empty space | frames: `began` and `ended` at (30, 30) | Exit 0. Both lines say `target=none`. Both show `state=count:0`. |
| 6 | Two fingers, one lifts | frames: two fingers `began`; one `ended` plus one `stationary`; one `stationary`; last `ended` | Exit 0. The lift frame logs two lines: `finger=0 ended` and `finger=1 stationary`. The next frame logs one line. The last frame logs one line. |
| 7 | Frames out of time order | frames with `t_ms` 400 then 200 | Exit code nonzero. No PNG written. The error on stderr names the frame index and both times. |
| 8 | Same file twice | row 1 frames, two runs | Exit 0 twice. The two logs are identical bytes. The two PNGs are identical bytes. |
| N | Negative control | row 1 checker fed the row 5 no-action log | The checker must fail, so the suite can detect a lost action. |

Rows 9 and 10 were added in review, after the first commit of this file.
They guard the fixes for two review findings on state handling. The rule
stands: each expected result here was written before the code that makes it
pass.

| # | Row | Input | Expected |
|---|-----|-------|----------|
| 9 | Nested child state survives the rebuild | `nestedapp`, tap at Button#1 center, the button owned by a child view with its own `@State` | Exit 0. The `ended` line shows `state=taps:1,rounds:0`. The child's box is pooled by slot, so the rebuilt tree reads the new value. |
| 10 | App state re-renders | `nestedapp`, tap at Button#2 center, the button whose action writes `@State` on the App struct | Exit 0. The `ended` line shows `state=taps:0,rounds:1`. The render after the frame differs from the no-tap render. |

Rows 11 to 13 came from the second review round, which named three
implementation changes that could survive the earlier rows. Each row kills
its named change; the receipt records the failed run against each changed
build. Rows 9 and 10 do not cover those three.

| # | Row | Input | Expected |
|---|-----|-------|----------|
| 11 | Topmost wins under overlap | `overlapapp`, whose Button#1 label is Button#2; both rects are identical; tap at the shared center | Exit 0. Both lines say `target=Button#2`, and the `ended` line shows `state=which:2`. A hit test that walks draw order forward picks Button#1 and fails this row. |
| 12 | Second finger on another button | `m3app`: finger 0 down on Button#1, finger 1 down on Button#2, finger 0 lifts on Button#1, finger 1 lifts on Button#2 | Exit 0. All four lines say `target=Button#1`, and all show `state=count:0`. Per-finger targets produce a Button#2 line or an action and fail this row. |
| 13 | Stationary keeps the gesture open | `m3app`: finger 0 began on Button#1; finger 0 stationary plus finger 1 began; finger 1 ends inside Button#1 while finger 0 is stationary; finger 0 ends inside | Exit 0. Five lines show `state=count:0`, the stationary lines are logged, and exactly one action fires on the last lift. A runner that rebuilds the down set from each frame and drops stationary fingers fires early and fails this row. |
