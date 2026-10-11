# M5 test expectations

M5 checks vertical scrolling in our Linux simulation. The `scrolldemo` app
contains 48 tappable rows inside `ScrollView`. The app also displays the
selected row. A tap updates that label. A drag on a row scrolls instead.

The viewport is 390 by 844 points. Each row is 7 points high. Its label is
35 or 41 points wide. Row groups use 16 points of vertical spacing. The
content is 1103 points high. Its maximum offset is 259 points.

The frame file uses the M3 finger records. A drag has `began`, `moved`, and
`ended` records. Coordinates are scene points. Dragging upward by 200 points
sets the offset to 200. A drag beyond eight points cancels the row tap.

`simview/test-m5.sh` checks these rows. PNG tolerance is zero differing pixels
and zero channel difference. Logs are checked for the expected selected value.

| Row | Input | Expected |
|---|---|---|
| 0 | Render without frames | The PNG matches `golden/scroll-root.png`. |
| 1 | Drag upward by 200 points | The PNG matches `golden/scroll-mid.png`. The selected row remains -1. |
| 2 | Drag upward by 10000 points | The offset stops at 259 points. The PNG matches `golden/scroll-bottom.png`. |
| 3 | Drag down from the top | The offset stays at zero. The PNG matches `golden/scroll-root.png`. |
| 4 | Tap the first row | The selected value becomes 0. |
| 5 | Begin on the first row, then drag upward by 200 points | The offset becomes 200. The selected value stays -1. The PNG matches `golden/scroll-mid.png`. |
| 6 | Run the same drag twice | Both logs and PNG files are byte-identical. |

## Mutation checks

Each mutation changes one behavior in a copied module. The suite rebuilds the
app against that module. The named row must reject the changed build. A mutant
that fails to compile or survives its row fails the suite.

| Mutation | Changed behavior | Required failing check |
|---|---|---|
| Wrong direction | Adds the finger delta to the offset | Row 1 image compare |
| Ignored offset | Places content at zero for every render | Row 1 image compare |
| No row cancellation | Keeps the tap active after slop | Row 5 selected value |
| No upper clamp | Allows offsets beyond the content end | Row 2 image compare |
| No lower clamp | Allows negative offsets at the content start | Row 3 image compare |
