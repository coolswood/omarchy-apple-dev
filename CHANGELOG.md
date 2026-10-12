# Changelog

## Unreleased

### React Native probe

- The abort listed under v0.2.0 came from a stale JS bundle in the first ipa. A rebuild from the current `App.tsx` stayed running for 25 seconds in 5 of 5 phone launches. Nobody checked the screen. See `receipts/2026-10-12-rnprobe-stale-bundle.md`.

## v0.2.0

### Build routes

- The README separates no-Xcode and full-mode needs. No-Xcode needs Linux. It needs an iPhone to run apps and an Apple ID to sign them. Setup needs about 7 GB of temporary disk space.
- A run in an Ubuntu 24.04 container now has setup and build results.

### Device run and over-tailnet

- `device-run.sh --over-tailnet` installs and launches an app over the tailnet without a cable. Screenshot and system log need separate `pymobiledevice3` commands. Pair once over USB first. The phone needs Wi-Fi. Cellular-only access failed.
- One debugger run stopped at the app's `main` breakpoint. It took 220 seconds. Earlier tries did not stop there.

### Simulation research and simview

- M1 ran a small arm64 C program through the Linux loader on an arm64 Linux laptop. This proves the loader and its syscall shims. It does not prove Objective-C or Swift support.
- M2 draws a 390 by 844 frame on Linux. It compares the frame with a saved image. This checks one frame. The saved image is the goal.
- M3 adds scripted touch frames and hit testing. It updates `@State` and draws the frame again. It does not support scrolling, gestures, or windows.
- M4 adds a simulated navigation stack. Scripted actions push and pop screens. The recorded run passed seven test rows and five mutation checks.
- Simview uses our own SwiftUI-like module. It does not match Apple's renderer or navigation behavior. This is not full SwiftUI.
- The four stages add one capability at a time. Each stage has limits. All four run on Linux. None uses a Mac.

### React Native probe

- Seven phone launches with no debugger ended in the same abort. The five crash reports show an abort within one second of launch. The Hermes bundle loaded and ran. See `receipts/2026-10-11-rnprobe-launch.md`.
- React Native reported: "Failed to call into JavaScript module method RCTEventEmitter.receiveEvent(). Module has not been registered as callable." The cause is unknown.
- With a debugger attached from launch, the app was still running after 220 seconds. Nobody checked the screen.

### Documentation

- Added `docs/SIM-INPUT-MODEL.md` for scripted input and `docs/OVER-TAILNET.md` for remote device use. `docs/PHONE-NODE.md` is a parked note.
- Updated `docs/IOS-SIMULATION-LINUX.md` with host needs and M1 through M4 findings. `docs/DISTROS.md` links the Ubuntu run at `receipts/2026-10-09-ubuntu-2404.md`.
- The wider device-side SwiftUI declarations include `Color`, `Font`, `padding`, `List`, `ForEach`, and `NavigationLink`. None ran on a phone. The phone SwiftUI stubs do not export `NavigationStack`.

## v0.1.0

First tagged release of omarchy-apple-dev. It added Linux builds for iOS apps without Xcode. It added a portable toolchain, resource tools, project setup, Flutter support, and macOS builds. The release included app and device-run records. The first tag set a baseline.

Five of five files matched the same Xcode output in each of three metadata tests. Some other parts have device records and no offline test suite.
