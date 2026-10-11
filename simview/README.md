# simview

Milestone M2 of the simulation ladder. The plan lives in
`docs/IOS-SIMULATION-LINUX.md`. The demo app in `sdk-free/swiftui` compiles
unchanged on Linux. It builds against our own `SwiftUI` module under
`simview/Sources/SwiftUI/`. The app renders one frame to a PNG on the CPU.
No GPU, no Mac, no phone. Receipt: `receipts/2026-10-11-simview-m2.md`.

## What is here

- `Sources/SwiftUI/SwiftUI.swift` is our `SwiftUI` module. It declares the
  vocabulary the app uses: `App`, `Scene`, `View`, `WindowGroup`, `VStack`,
  `Text`, `Button`, and `@State`. Views build a render tree. A measure pass
  sizes the tree in points. A draw pass fills one RGBA buffer. The buffer is
  390 x 844. One pixel is one point. `App.main()` reads `--out`, renders, and
  writes the PNG.
- The glyphs are a hand-drawn 5 x 7 bitmap font. It covers the ASCII the demo
  apps need. The PNG encoder is ours too. It computes CRC32 and Adler32 and
  emits stored deflate blocks.
- `build.sh` builds the module and the demo. The demo lands at `simview-demo`
  in the repo root. `test.sh` renders twice and compares the bytes. It
  compares the result with `golden/demo1.png`. `compare.py` states the
  tolerance: 0 differing pixels, 0 per-channel difference. It also runs a
  negative control. A changed initial state must fail that compare.

## Running it

A host with native Swift runs the scripts directly:

```sh
simview/build.sh
./simview-demo --out demo1.png
simview/test.sh
```

The chroot build host has no native `swiftc`. Export `SIMVIEW_CHROOT_RUN`
first. It names a copy of the repo arch runner. Its `/work` bind must be this
checkout. Then run the same three commands:

```sh
SIMVIEW_CHROOT_RUN=$HOME/scratch/apple-dev/simview/archrun.sh simview/test.sh
```

## Milestone M3: scripted touch frames

M3 adds the input loop of `docs/SIM-INPUT-MODEL.md`. The demo binary gains
`--frames`:

```sh
./simview-demo --frames frames.json --out after.png
```

The file holds frames of finger records, or the short form
`{"tap": [x, y]}`, which expands to a began frame and an ended frame 80 ms
apart, for finger 0. The loader refuses out-of-order `t_ms` and names the
frame index. The runner prints each button rect, then one log line per
finger record.

The rules: coordinates are scene points. One pixel is one point. The topmost
element under the first finger at `began` owns the whole touch. It keeps the
touch when the finger leaves. The action fires only when the last finger ends
inside that target. A `cancelled` finger kills the touch. Every frame ends
with a full tree rebuild and a re-render. A fired action appears in the final
PNG. `@State` boxes are pooled by creation slot. Each pass rebuilds the tree
and reuses boxes in the same order. A write inside an action appears in the
next render. The log lists each reachable `@State` value in tree order.

`simview/test-m3.sh` checks the spec rows, the demo tap, a negative control,
determinism, and state regressions. Expected results live in
`simview/TESTS-M3.md`. The `m3app` app carries two buttons for drag tests.
The `nestedapp` app checks child and app state. Their sources live under
`simview/Sources/`.

## Milestone M4: navigation

M4 adds `NavigationStack`, `NavigationLink`, `List`, and `navigationTitle`.
The navigation bar draws a title, a back button, and a separator. Its back
button uses the label as its hit area. Content centers below the bar. `List`
places rows in a leading stack and adds a separator after each row.

The `navdemo` app shows two rows. Each row pushes a detail screen. The detail
has its own `@State` and a deeper link. The back button pops one level.
`simview/test-m4.sh` compares root and pushed screens against goldens. It
checks back behavior, hit area, determinism, and five mutation checks.

## Milestone M5: vertical scrolling

M5 adds `ScrollView` to the app vocabulary. A frame file uses the M3 finger
records for a drag: `began`, `moved`, then `ended`. The runner applies the
drag delta to a vertical content offset. It clamps the offset at both ends
and renders again after every frame. A drag past the eight point slop cancels
a row tap and scrolls the content.

The `scrolldemo` app contains 48 tappable rows. `simview/test-m5.sh` checks
the root, upward scrolling, top and bottom clamps, row taps, drag cancellation,
determinism, and five mutations. The tests compare exact PNG bytes against
goldens. See `simview/TESTS-M5.md` for expected outcomes.

Scroll here is our own model. It is not Apple's scroll implementation.

## Limits

This is not real SwiftUI layout, fonts, animation, or Metal. It proves nothing
about Apple's renderer or gesture recognizers. Scrolling has no fling or
momentum. Pinch, rotate, and keyboard input are not implemented. The runner
takes times from the file, not from a clock.
