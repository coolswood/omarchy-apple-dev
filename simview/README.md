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

## Limits

This is not real SwiftUI layout, fonts, animation, or Metal. It proves nothing
about Apple's renderer. The module renders once with the initial state. State
writes and button actions are stored. They never fire. Touch input is
milestone M3. Its frame format lives in `docs/SIM-INPUT-MODEL.md`.
