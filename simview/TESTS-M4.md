# M4 test expectations

Written before the M4 code, per the M4 rung of `docs/IOS-SIMULATION-LINUX.md`
(the exit demo: first screen, a scripted tap navigates one level, a saved
screenshot, a clean exit). `simview/test-m4.sh` checks each row and fails if
a row does not match. One app drives the rows: `navdemo`, built from
`simview/Sources/NavDemo/NavDemo.swift`. Its root screen is a `List` of two
`NavigationLink` rows under a `navigationTitle("demo")` navigation bar. Row
one pushes a detail screen: title `one`, texts `detail one` and `taps: 0`,
a `tap` button that owns a `@State`, and a `deeper` link that pushes a third
screen titled `deep`. Row two pushes the same detail with label `two`. The
back button pops one level. The app source is unchanged app-style SwiftUI:
no simview types are named.

The runner prints the root screen's button rects before the frame log, as in
M3; the tests read tap points from those rects. Buttons on a pushed screen
are not printed, so their rects come from the documented layout arithmetic
below, and the rows assert that arithmetic through the pixels and the log.

## Documented layout arithmetic

Font: one glyph is 5 points wide plus a 1 point gap, so a string of `n`
characters is `6n - 1` points wide and 7 points tall without descenders. The
navigation bar is 44 points tall; the bar title is centered in it; the back
button `< Back` (new `<` glyph, 6 characters, 35 x 7) sits at x 12, y 18; a
1 point separator line spans the bar at y 43. Content is centered in the
area below the bar (y 44 to 844, height 800). A stack lays children top to
bottom with the configured spacing; each child is centered horizontally
unless the stack is leading-aligned; a `List` is a leading-aligned stack
with a separator line between rows.

Root screen. List rows `item one` and `item two` are 47 x 7 each; two
separator lines are 1 point. Column height: 7+16+1+16+7+16+1 = 64, so the
column starts at 44 + (800 - 64) / 2 = 412 and x 0 = (390 - 47) / 2 = 171.

- Button#1 `item one` rect 171,412,47,7
- separator y 435
- Button#2 `item two` rect 171,452,47,7

Pushed `one` screen. Children `detail one` (59 x 7), `taps: 0` (41 x 7),
`tap` button (17 x 7), `deeper` link (35 x 7); height 4*7 + 3*16 = 76; start
y 44 + (800 - 76) / 2 = 406, x 0 = (390 - 59) / 2 = 165. Bar back button is
laid before the content, so it takes id 1.

- Button#1 back rect 12,18,35,7
- `taps: 0` text at 174,429,41,7
- Button#2 `tap` rect 186,452,17,7
- Button#3 `deeper` rect 177,475,35,7

Bar titles: `demo` is 23 wide at x 183; `one` and `two` are 17 wide at x 186.

Tolerances, as in M3: log comparison is exact bytes; PNG comparison is
`simview/compare.py` (0 differing pixels, 0 per-channel difference).

| # | Row | Input | Expected |
|---|-----|-------|----------|
| 0 | Root render and clean exit | `navdemo --out root.png`, no frames | Exit 0. The PNG matches `golden/nav-root.png`: bar title `demo`, no back button, two rows with separators. |
| 1 | Tap pushes one level | frames: tap at Button#1 center | Exit 0. Every log line matches `t=<t> finger=<n> <phase> (<x>,<y>) target=<t|none> state=<s> render=ok`. The `ended` line names `target=Button#1`. The final PNG matches `golden/nav-one.png`: bar title `one`, back button drawn, detail texts and buttons in place. |
| 2 | Detail state renders | frames: tap Button#1 center, then tap the detail `tap` button at 186,452 center | Exit 0. The last `ended` line shows `state=taps:1`. Every differing pixel between the final PNG and `golden/nav-one.png` sits inside 174,429,41,7 (the `taps:` text): the label re-rendered from the detail's `@State`. |
| 3 | Back pops one level | frames: tap Button#1, tap `deeper` (Button#3 center 194,478), tap back (Button#1 center 29,21) | Exit 0. Six lines. The `deeper` ended line names Button#3; the back ended line names Button#1. The final PNG matches `golden/nav-one.png` (the `one` screen), not `golden/nav-root.png`: back removes the last level only. |
| 4 | Back hit area is its label | frames: tap Button#1, then tap the bar at (250, 21), right of the back label | Exit 0. Both bar tap lines say `target=none`; no action fires. The final PNG matches `golden/nav-one.png`: the app is still on the pushed screen. |
| 5 | Row two pushes its own detail | frames: tap at Button#2 center | Exit 0. The final PNG matches `golden/nav-two.png`: bar title `two`, detail text `detail two`. |
| 6 | Same file twice | row 2 frames, two runs | Exit 0 twice. The two logs are identical bytes after dropping the `wrote` line; the two PNGs are identical bytes. |

## Mutation checks

As in the M3 review rounds, each row must bite: the suite applies one named
implementation change to a copy of the module, rebuilds `navdemo` against
it, reruns the row, and requires the row's check to fail. The suite fails if
a mutant survives its row. Expected: each mutant fails exactly its row, and
the receipt records the observed failures.

| Mutant | Change | Row that must fail | Why it fails |
|---|---|---|---|
| pop-clears | The back action sets the stack to empty instead of removing the last level | 3 | The final render is the root screen, not `golden/nav-one.png`. |
| bar-wide-back | The back button's hit rect spans the whole bar | 4 | The bar tap names `target=Button#1`, fires, and the render pops to root. |
| root-title | The bar title is always taken from the root screen | 1 | The pushed bar reads `demo`, so the PNG differs from `golden/nav-one.png`. |
| frozen-destination | The pushed screen's spec is built once at push time instead of rebuilt each pass | 2 | The `taps:` label keeps its push-time pixels, so the differing pixels do not land inside the text box. |
| no-separators | The draw pass skips separator lines | 0 | The root render loses the two separator lines and differs from `golden/nav-root.png`. |
