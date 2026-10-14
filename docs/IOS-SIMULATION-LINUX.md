# iOS app simulation on Linux (standing project)

Date: 2026-10-10. Status: research; no simulation code exists yet.

Question: can a Linux host check iPhone app UI behavior with no macOS and no iPhone?

The repo's test routes today are: compile and symbol-check on Linux, run in the iOS
Simulator on a Mac over ssh, ship to TestFlight, or run on the phone over USB. Those are
covered by `receipts/2026-10-10-testing-without-the-phone-plan.md`. This document is about
the longer-term route that needs neither macOS nor a phone: simulate the app on Linux
itself, starting from the Mach-O binaries this repo already produces.

## Two routes

- Route A (user-supplied runtime): the user points the tool at their own downloaded
  simulator runtime; the repo never fetches, stores, or ships any runtime material.
- Route B (reimplementation): we write our own declarations and draw code, so no runtime
  material is involved at all.

## Prior art

### Mach-O loaders on Linux (the Wine pattern)

Wine runs Windows binaries on Linux by loading them and reimplementing the OS around
them ([LWN overview](https://lwn.net/Articles/794871/)). The same pattern exists for
Mach-O:

| Project | What it does | Limits |
|---|---|---|
| [Darling](https://github.com/darlinghq/darling) ([docs](https://docs.darlinghq.org/)) | Loads Mach-O binaries and reimplements the macOS layer: a userspace kernel server for Mach IPC and Darwin syscalls, plus reimplemented Foundation, AppKit (built on Cocotron), CoreAudio, CoreFoundation. Many CLI tools work; GUI is in development behind an AppKit implementation and a Metal-on-Vulkan backend. | Targets macOS, not iOS: no UIKit, no iOS frameworks. Requires 64-bit x86 Linux ([build docs](https://docs.darlinghq.org/build-instructions.html)), so no arm64 path. |
| [maloader](https://github.com/shinh/maloader) | Small userland Mach-O loader for Linux (`ld-mac`). | Old, x86, proof-of-concept scale. |
| [machismo](https://github.com/bmdhacks/machismo) (2026) | Runs Apple Silicon Mach-O binaries on aarch64 Linux with no CPU emulation: maps Mach-O segments, redirects imports to native Linux `.so` files, and bridges ABI differences (constructors return `this`, Apple libc++ SSO layout, pthread signatures, zero-filling `malloc`, `_tlv_bootstrap`, compact unwind to DWARF, LSE atomics emulation). | Built for C/C++ game binaries, not iOS apps: no Objective-C runtime, no UIKit. |
| [osxcross](https://github.com/tpoechtrager/osxcross) | Cross toolchain that builds macOS binaries from Linux; the user supplies their own SDK. | Build-only, no runtime. Same user-supplies-material shape as Route A. |

### QEMU boots of real iOS (research kernels only)

| Project | What it actually runs |
|---|---|
| [xnu-qemu-arm64](https://github.com/alephsecurity/xnu-qemu-arm64) | Boots the iOS 12.1 kernel ([build guide](https://github.com/alephsecurity/xnu-qemu-arm64/wiki/Build-iOS-on-QEMU)). Research kernel, no UI. |
| [qemu-t8030](https://github.com/TrungNguyen1909/qemu-t8030) | A13 device (iPhone 11 class) running iOS 14 through a restore; enough to reach a shell over ssh ([eShard writeup](https://www.eshard.com/blog/emulating-ios-14-with-qemu)). |
| [QEMUAppleSilicon](https://github.com/wangningyi/QEMUAppleSilicon) and its [IOMFB fork](https://github.com/ChefKissInc/QEMUAppleSilicon) | iPhone 11 target; display/framebuffer (IOMFB) work. |
| [Corellium](https://www.corellium.com/platform) | Commercial virtual ARM devices running real iOS. Closed platform, paid. |

What the eShard team hit, and why this lane is hard
([writeup](https://www.eshard.com/blog/emulating-ios-14-with-qemu)):

- iOS rendering goes through Metal to a real GPU. The `gpu=0` software-render bootarg is
  gone in iOS 14; software rendering survives only as a QuartzCore fallback. They proved
  the fallback works by patching QuartzCore on a jailbroken device: slow, with artifacts.
- Kernel patches (checkra1n KPF injected via PongoOS) need per-version maintenance; A13
  pointer-authentication instructions break older patch matching.
- Apple system libraries ship in one dyld shared cache (arm64e), which complicates
  loading and debugging.
- Net result today: kernels boot and shells work; app UI does not. No QEMU project runs
  App Store apps.

An iPod touch 1G emulator exists as a research project
([CCC 2023 talk](https://fahrplan.events.ccc.de/congress/2023/fahrplan/system/event_attachments/attachments/000/004/479/original/ccc_presentation.pdf)).

### Reimplemented UI frameworks

| Project | What it does | Fit here |
|---|---|---|
| [GNUstep](https://gnustep.org/) | Long-running reimplementation of the AppKit/Foundation stack on Linux. | Proof that framework reimplementation is durable work; nothing iOS. |
| [SwiftCrossUI](https://github.com/stackotter/swift-cross-ui) ([docs](https://docs.swiftcrossui.dev/documentation/swiftcrossui/)) | SwiftUI-style code on Linux (GTK backend), with AppKit, UIKit, Android, and WinUI backends. | Closest existing shape for M2/M3: SwiftUI dialect in, pixels out. |
| [OpenSwiftUI](https://github.com/OpenSwiftUIProject/OpenSwiftUI) ([site](https://openswiftuiproject.org/)) | Open-source SwiftUI implementation aiming at Linux, Android, WASI, embedded. | Young; worth watching. |
| [Skip](https://github.com/skiptools/skip) ([architecture](https://skip.dev/docs/architecture)) | Compile-time transpiler: Swift to Kotlin, SwiftUI to Jetpack Compose. | Different lane (no Linux runtime), but its SwiftUI API mapping is useful reference. |

### Cross-compiled app frameworks with a Linux target

- [Flutter](https://docs.flutter.dev/platform-integration/linux/building) runs on Linux
  desktop through its own embedder; the engine rasterizes scenes on CPU or GPU
  ([engine architecture](https://github.com/flutter/flutter/blob/master/docs/about/The-Engine-architecture.md)).
  This repo already builds Flutter apps from Linux with no macOS.
- [React Native](https://reactnative.dev/docs/out-of-tree-platforms) officially supports
  Windows and macOS out of tree; an Ubuntu port existed in 2016-2017
  ([Canonical branch](https://github.com/CanonicalLtd/react-native/tree/ubuntu)). This
  repo keeps an RN lane too (`rn-no-xcode`).

These frameworks prove app logic on Linux. They do not prove iOS UI behavior, because
the iOS UI stack is not in the loop.

### The Android-emulator shape, and why it does not carry over

The Android emulator is QEMU plus bootable Android system images
([emulator sources](https://android.googlesource.com/platform/external/qemu/+/emu-master-dev/android/docs/ANDROID-EMULATION-LIBRARY.TXT));
[Waydroid](https://github.com/waydroid/waydroid) runs a full Android system in a Linux
namespace container. That shape works because Android's system is open and its images
are bootable artifacts anyone can build. iOS has no bootable system image outside
Apple's own signing flow, so the Android shape collapses into Route A (user-supplied
runtime) or the research-kernel QEMU lane above.

### What changes on arm64 Linux on Apple Silicon hardware

On an arm64 Linux host the CPU already runs the app's instruction set, so a loader is
enough: no emulation, no QEMU. [machismo](https://github.com/bmdhacks/machismo) proves
the pattern for C/C++ binaries. Two gaps remain for iOS apps: the Objective-C runtime
and UIKit do not exist on Linux, and Apple's system libraries are arm64e with pointer
authentication while app binaries are plain arm64 (see the dyld cache notes in the
[eShard writeup](https://www.eshard.com/blog/emulating-ios-14-with-qemu)). This lab
already builds and runs arm64 Linux binaries natively on Apple Silicon hardware, so
every rung below has both a `qemu-aarch64-static` option and a native arm64 option.

## What an app needs from its host

A phone gives an app more than a CPU and a screen. Before the first frame, the system has done many jobs. A host that
runs the app must do the same jobs. If it does not, the app stops at start.

The table lists those jobs and the rung that covers each. It is our reading of published research notes on running
simulator-built apps without the simulator. We have run none of the rows. A row becomes a measured claim when its
rung lands a receipt.

| Job | The app expects | Our host | Rung |
|---|---|---|---|
| Find system services by name | Named lookups at start. When they fail, the app exits. | A small name registry. It answers known names. It logs and refuses the rest. | M4 |
| Give the app a screen and a scene | A scene with a size, a scale and an active state. The app makes its window after that. | One fixed scene, 390 by 844 points. M2 draws one pixel per point, so the PNG is 390 by 844. | M2 draws it, M4 delivers it to the app |
| Collect drawn layers and show them | Layers go to a render service. It draws them into shared buffers. | Our draw path. It fills an RGBA buffer on the CPU, then writes a PNG. | M2 |
| Use the GPU | Drawing and shader builds call a GPU service. | None. Route B has no GPU. Route A leaves it to the user's machine. | out of scope |
| Deliver touches | Frames of finger records: a finger, a phase, a position, and a time. One element is the target. | Our frame format and hit testing. See [SIM-INPUT-MODEL.md](SIM-INPUT-MODEL.md). | M3 |
| Deliver keys and text focus | A focus owner. Without one, the app drops keys silently. | Key records, text records, and a focus owner in the runner. See [SIM-INPUT-MODEL.md](SIM-INPUT-MODEL.md). | M6 |
| Copy and paste | A pasteboard service shared by apps. | An in-memory store for one run. | M4 or later |
| Keep app data | A private folder for documents, caches and preferences. | One folder per bundle id under a run directory. | M4 |
| Keep secrets | A keychain service. | A plain file, marked as not secure. | M4 or later |
| Network and TLS | Plain sockets work alone. TLS needs a trust service. | Sockets first. TLS only when a test app needs it. | M4 |
| Language and region | Locale, 24-hour time and first weekday from system preferences. | Fixed `en_US` values in the run directory. | M4 |
| Web views, drag and drop between apps, dictation | Helper processes or system services. | Not planned. | out of scope |

Two points follow.

- Route B (our own declarations and draw code) replaces the UI framework. It needs only the rows our view vocabulary
  touches. Those are the scene, drawing, touches and, for M4, the app data folder.
- Route A (a runtime the user supplies) keeps Apple's framework code. It must provide every row. Each one is a
  stand-in service around the user's own libraries. That is a large job, and it stays on the user's machine.

## Milestone ladder

Each rung lands a receipt in `receipts/` with the commands and outputs actually observed.
A rung is done when its exit check is observed, not argued.

### M1 — a Mach-O arm64 hello from our toolchain runs on Linux

Landed on branch `machoload-m1` (commit `a68df70`), proven under `qemu-aarch64-static`;
also run natively on arm64 Linux
([receipt](../receipts/2026-10-10-machoload-m1.md)).

- Entry checks:
  - The chroot toolchain emits a Mach-O arm64 executable. Already proven for device
    builds in `sdk-free/`; `llvm-objdump --macho --all-headers hello` lists
    `LC_SEGMENT_64 __TEXT` and `LC_MAIN`.
  - An arm64 Linux runner exists: `qemu-aarch64-static` on the build host, or the native
    arm64 Linux host.
- Exit demo (observed, qemu):
  ```
  $ qemu-aarch64-static machoload/.build/loader machoload/.build/Hello
  Hello from an iOS Mach-O on Linux
  $ echo $?
  0
  ```
  The same pair also printed that line with exit 0 on a native arm64 Linux laptop, with no emulator (2026-10-11). That
  pair is the 2026-10-10 build. It was not rebuilt from main, because the build host's `ld64.lld` refuses platform iOS,
  so its hashes were not compared with a fresh build.
- Cannot prove: dyld shared cache loading, the Objective-C runtime, any framework. A
  C-level hello only proves the loader and its syscall shims.

### M2 — a SwiftUI view renders to a PNG (software draw path, no GPU)

- Entry checks: M1 done; a starting view vocabulary picked from `sdk-free/swiftui/`
  (VStack, Text, Button, `@State`); a CPU rasterizer plan: RGBA buffer plus PNG
  writer, bitmap font for text first, real font shaping later.
- Exit demo (expected shape):
  ```
  $ ./simview demo1.swift --out demo1.png
  $ file demo1.png
  demo1.png: PNG image data, 390 x 844
  ```
  The PNG matches a golden image within a stated pixel-diff tolerance, and glyphs appear
  where the Text views sit.
- Cannot prove: real SwiftUI layout or state-graph behavior, animations, font shaping,
  Metal or GPU numbers. It proves our draw path and our view vocabulary, nothing about
  Apple's renderer.

Landed on branch `simview-m2`
([receipt](../receipts/2026-10-11-simview-m2.md)). The demo app
`sdk-free/swiftui/HelloApp.swift` compiles unchanged on Linux against our own
`SwiftUI` module in `simview/Sources/SwiftUI/`. The module builds the render
tree with result builders, measures in points, and draws into a 390 x 844 RGBA
buffer, one pixel per point. The PNG encoder, its CRC32 and Adler32 checks, and
a hand-drawn 5 x 7 bitmap font are all our own code. Observed: `file` reports
`PNG image data, 390 x 844`; two renders give identical bytes; the render
matches `simview/golden/demo1.png` with 0 differing pixels under the tolerance
stated in `simview/compare.py`; a changed initial state fails that compare.
`simview/test.sh` runs these checks, and `tests/run.sh` calls it.

### M3 — touch input mapping

The frame format, the rules and the test list for this rung are in [SIM-INPUT-MODEL.md](SIM-INPUT-MODEL.md).

Landed on branch `simview-m3`. `./simview-demo --frames frames.json --out
after.png` validates the file, walks the frames, fires button actions under
the touch rules, and re-renders from `@State` after every frame. A tap of the
demo app fires once (`state=count:1` on the ended record), and 19 pixels
differ from the no-tap render, the count glyph. Receipt with commands and
outputs: `../receipts/2026-10-11-simview-m3.md`. All eight spec rows pass in
`simview/test-m3.sh`, with the expected results in `simview/TESTS-M3.md`.

- Cannot prove: iOS gesture recognizers, full multi-touch gestures (pinch, rotate, scroll with fling), timing feel,
  iOS hit-testing edge rules. It proves our frame format, our hit-testing and the state -> render loop.

### M4 — a real iOS app shell runs

- Entry checks: M3 done; one of this repo's real apps (the SwiftUI demo or RNProbe)
  compiles against our declarations with no Apple-derived material in the build; any
  Route A run stays on the user's machine and never enters the repo.
- Stand-ins this rung adds, and only the ones the chosen app needs to start: the scene delivered to the app, the
  name registry, one app data folder per bundle id, fixed `en_US` locale values, and TLS trust only if the app uses
  TLS. Each one lands with a test that starts the app with and without it.
- Exit demo: the app's own SwiftUI code draws its first screen, a scripted tap navigates
  one level, a screenshot is saved, and the app exits cleanly. The receipt records app
  name, commit, commands, and outputs.
- Cannot prove: parity with a real device (fonts, animation curves, system services such
  as push, camera, Keychain), App Store apps, performance numbers.

Landed on branch `simview-m4`, exit-demo scope
([receipt](../receipts/2026-10-11-simview-m4.md)). The module gained the
vocabulary the demo needs: `NavigationStack`, `NavigationLink`, `List`,
`navigationTitle`. The navigation bar draws its title, a back button whose
hit area is its label rect, and a separator line; list rows lay out as a
leading stack with a separator after each row. The `NavDemo` app
(`simview/Sources/NavDemo/NavDemo.swift`, app-style SwiftUI only) draws a
two-row list, pushes a per-row detail screen that owns `@State`, pushes a
third screen, and pops one level per back tap. Observed: scripted frames
push and pop; the render after back is byte-identical to the root golden;
`simview/test-m4.sh` runs the rows of `simview/TESTS-M4.md` plus five
mutation checks, each proven in-suite against a changed build. The
stand-ins table rows above (name registry, app data folder, locale, TLS)
are not reachable by an app built on our own SwiftUI module. The module
calls no system service. This rung therefore landed the exit demo only, and
those rows stay listed for Route A.
`NavigationStack` is our own type on Linux. On the unmerged `swiftui-wide`
branch, the symbol check found no `NavigationStack` symbols in the phone's
SwiftUI stubs on iOS 27.0.1. `NavDemo` therefore has not been built for the
phone, and we expect it would not link as written.
- Cannot prove (M4 additions): UINavigationController parity, interactive
  gesture pop, large titles, scroll-edge bar effects, a detail whose state
  survives pop and re-push (pooled boxes continue from the old value; real
  iOS resets), more than one `NavigationStack`, or a link outside a stack.

### M5: vertical scrolling

The scroll rules are in [SIM-INPUT-MODEL.md](SIM-INPUT-MODEL.md).

Landed on branch `simview-m5` ([receipt](../receipts/2026-10-11-simview-m5.md)).
The module gained `ScrollView`. The runner reads `began`, `moved`, and `ended`
records as one drag. It applies the finger delta to a vertical content offset.
It clamps the offset between zero and the content height minus the viewport
height. A drag past eight points cancels the row tap and scrolls instead.
Measured on the demo: viewport 390 by 844 points, content 1103 points, so the
maximum offset is 259 points. A 200 point upward drag matches the 200 point
golden with 0 differing pixels. A 10000 point drag clamps at 259 points. A 500
point downward drag from offset zero stays at the root render. A tap selects
its row. A drag that starts on a row scrolls and leaves the selection at -1.
`simview/test-m5.sh` runs seven rows plus five mutation checks, each one
proven in-suite against a changed build. The M2, M3, and M4 suites still pass.

- Cannot prove: iOS scroll behavior. Momentum, fling, and deceleration after
  the lift are not implemented. Neither are pinch, rotate, or keys.

### M6: keyboard input and text field focus

The key and text record rules are in [SIM-INPUT-MODEL.md](SIM-INPUT-MODEL.md).

Landed on branch `simview-m6` ([receipt](../receipts/2026-10-14-simview-m6.md)).
A frame file gains two record kinds next to the finger records: a `key` record
with a USB keyboard usage number (page 7), and a `text` record with one
character. The runner routes both to the focused text field only. A completed
tap focuses the field under it; a tap anywhere else blurs it; a cancelled tap
changes nothing. A key with no focus is dropped, and the runner prints one
warning line. The module gained `TextField`, which renders its text or
placeholder, an underline, and a caret. Typed characters append at the caret,
which sits at the end. Backspace removes one character and stops at empty.
Return fires `onSubmit` when present and always blurs. The `KeysDemo` app has
two fields and an echo label. `simview/test-m6.sh` runs eleven rows plus six
mutation checks, each proven in-suite against a changed build. The M2, M3,
M4, and M5 suites still pass.

- Cannot prove: our own input model, not Apple's keyboard. No IME, dictation,
  autocorrect, or multitap. Shift and caps lock are not implemented, so every
  typed character is its literal self. No claim about Apple's focus ring or
  caret drawing.

## Standing rules

- This project adds Linux-only checks. It does not replace the fallback ladder in
  `receipts/2026-10-10-testing-without-the-phone-plan.md`; the Mac Simulator, TestFlight,
  and phone runs stay the primary test routes.
- Each rung: one receipt file in `receipts/`, commands and observed outputs only, no
  Apple-derived files.
