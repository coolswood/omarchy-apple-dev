# M7 test expectations

M7 adds rows and padding to our Linux simulation: `HStack`, `Spacer`, and
`.padding(_:)`. Without a row, a screen can only stack things vertically, so
most real first screens cannot draw. The rules are ours, not Apple's. They are
written here so a test can fail them.

The rules:

- An `HStack` places its children left to right. `spacing` points sit between
  every pair of children, a `Spacer` included. The default spacing is 0, like
  `VStack` in this module. Each child is centered on the row height. The row
  is as tall as its tallest child.
- A `Spacer` is 0 points wide. In an `HStack` it takes a share of the width the
  other children and the gaps leave. Spacers share it equally by integer
  division. The last spacer takes the remainder. A `Spacer` outside an
  `HStack` does nothing. It does not expand a `VStack`.
- A row that holds a `Spacer` is as wide as the proposed width. The proposed
  width is the scene width, 390 points, less 2 times each `.padding` applied
  above it. Apple proposes the parent's width instead. We did not measure
  where the two differ. Expect differences in a nested stack.
- `.padding(n)` adds n points on all four edges. The bare form uses 16.
  Padding does not change a button's hit area: it stays the label rect.
- A `NavigationLink` inside a row or inside padding still pushes. The stack
  rewrites it as before.

`rowdemo` has four lines on one screen. Line 1 is `left`, a `Spacer`, and
`right` in an `HStack` with spacing 4, padded by 10. Line 2 is two buttons
`minus` and `plus` in an `HStack` with spacing 6. Line 3 is a `Spacer`, `mid`,
and a `Spacer`. Line 4 is the label `taps: N`. The `VStack` around them has
spacing 8. Glyphs advance 6 points. A text is 6 times its length less 1 wide
and 7 high, or 9 high with a descender (g, j, p, q, y).

The numbers the rows check, worked by hand from those rules:

| Item | Size | Place |
|---|---|---|
| `left` | 23 by 7 | x 10, y 394 |
| `right` | 29 by 9 | x 351, y 393 (right edge 380 = 390 less padding 10) |
| line 1 | 390 by 29 | y 383 |
| `minus` | 29 by 7 | x 166, y 421 |
| `plus` | 23 by 9 | x 201, y 420 |
| `mid` | 17 by 7 | x 186, y 437 (the two spacers take 186 and 187) |
| `taps: N` | 41 by 9 | x 174, y 452 |

`simview/test-m7.sh` checks these rows. PNG tolerance is zero differing
pixels and zero channel difference. State is read from the log lines. Rows 1
and 2 read the layout and the pixels directly, so a golden is not the only
evidence for the numbers above.

| Row | Input | Expected |
|---|---|---|
| 0 | Render without frames | The PNG matches `golden/row-root.png`. |
| 1 | Read the button rects from the log | `minus` is `166,421,29,7` and `plus` is `201,420,23,9`. |
| 2 | Read the ink boxes from the PNG with `inkbox.py` | `left` starts at x 10 to 12 and y 394. `right` ends at x 378 or 379 and starts at y 393. `mid` spans x 186 to 202. |
| 3 | Tap the middle of `plus` twice | State shows `taps:2`. The PNG matches `golden/row-two.png`. |
| 4 | Tap the middle of `minus` | State shows `taps:-1`. The PNG matches `golden/row-minus.png`. |
| 5 | Tap in the 6 point gap between the buttons | The target is none. State stays `taps:0`. The PNG matches `golden/row-root.png`. |
| 6 | `rownavdemo`: a link in a padded row under a navigation title. Tap the link | The root matches `golden/row-nav-root.png`. After the tap the PNG matches `golden/row-nav-pushed.png`, which differs from the root. |
| 7 | Run the row 3 frames twice | Both logs and both PNG files are byte-identical. |

## Mutation checks

Each mutation changes one behavior in a copied module. The suite rebuilds the
app against that module. The named row must reject the changed build. A mutant
that fails to compile or survives its row fails the suite.

| Mutation | Changed behavior | Required failing check |
|---|---|---|
| no-spacing | Drops the gap between row children | Row 1 rects |
| no-centering | Puts every child at the top of the row | Row 1 rects |
| no-spacer-share | A spacer takes 0 points | Row 0 image compare |
| no-padding-offset | Padding grows the box but does not move the content | Row 0 image compare |
| proposal-not-reduced | A padded flexible row ignores the padding when it fills the width | Row 0 image compare |

## Notes

- Row 6 needs the stack rewrite to walk rows and padding. A one-time build of
  the module without those two cases crashed `rownavdemo` at the link, as the
  stack's own check intends. That run is in the receipt. It is not a suite
  mutant, because a crash cannot be told apart from a build failure there.
- Not proven: Apple's layout for rows. No `alignment:` argument, no
  `Spacer(minLength:)`, no per-edge padding, no `frame`, no `Divider`, and no
  vertical `Spacer`. A call that uses one does not compile, which is the
  loud answer on purpose.
