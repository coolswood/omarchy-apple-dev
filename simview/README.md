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
apart. The loader refuses out-of-order `t_ms` and names the frame index. The
runner prints each button rect, then one log line per finger record:

```
button id=1 rect=177,430,35,9
t=0 finger=0 began (194,434) target=Button#1 state=count:0 render=ok
t=80 finger=0 ended (194,434) target=Button#1 state=count:1 render=ok
```

The rules: coordinates are scene points, one pixel per point. The topmost
element under the first finger at `began` owns the whole touch, and keeps it
when the finger leaves. The action fires only when the last finger ends
inside that target. A `cancelled` finger kills the touch. Every frame ends
with a re-render from the current `@State` values, so a fired action shows in
the final PNG. `@State` stores its value in a reference cell, so copies of a
view share one box and the action closure writes what the next render reads.

`simview/test-m3.sh` runs the eight rows of the spec, the demo tap, the
negative control, and the determinism check. Expected results, written
before the code: `simview/TESTS-M3.md`. The second app, `m3app`, carries two
buttons for the drag-across row. Its source is `simview/Sources/M3App/`.

## Limits

This is not real SwiftUI layout, fonts, animation, or Metal. It proves nothing
about Apple's renderer. Hit testing is ours, so M3 proves our input model, not
iOS gesture recognizers. No scroll, fling, pinch, rotate, or keyboard. The
runner takes times from the file, not from a clock.
