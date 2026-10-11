# Changelog

## v0.2.0

### Build routes

- The setup guide separates no-Xcode and full-mode needs. No-Xcode needs Linux. It needs an iPhone to run apps and an Apple ID to sign them. Setup needs about 7 GB of temporary disk space.
- A run in an Ubuntu 24.04 container now has setup and build results.

### Device run and over-tailnet

- `device-run.sh --over-tailnet` installs and launches an app without a cable. It also saves a screenshot and reads the system log over Tailscale. Pair once over USB first. The phone needs Wi-Fi. Cellular-only access failed.
- One debugger run stopped at the app's `main` breakpoint. It took 220 seconds. Earlier tries did not stop there.

### Simulation research and simview

- M1 ran a small arm64 C program through the Linux loader on an arm64 Linux laptop. This proves the loader and its syscall shims. It does not prove Objective-C or Swift support.
- M2 draws a 390 by 844 frame on Linux. It compares the frame with a saved image.
- M3 adds scripted touch frames and hit testing. It updates `@State` and draws the frame again. It does not support scrolling, gestures, or windows.
- M4 adds a simulated navigation stack. Scripted actions push and pop screens. The recorded run passed seven test rows and five mutation checks.
- Simview uses our own SwiftUI-like module. It does not match Apple's renderer or navigation behavior. This is not full SwiftUI.
- The four stages add one capability at a time. Each stage has limits.

### React Native probe

- Seven of seven phone launches started. Each stopped in under one second. The Hermes bundle loaded and ran.
- React Native reported this error: “Failed to call into JavaScript module method RCTEventEmitter.receiveEvent(). Module has not been registered as callable.” We do not know why.
- With a debugger attached from launch, the app stayed running for 220 seconds. Nobody checked the screen.

### Documentation

- New documents cover simulation input, host needs, Ubuntu setup, tailnet limits, and M1 through M4. Run records support the results.
- The wider device-side SwiftUI declarations include `Color`, `Font`, `padding`, `List`, `ForEach`, and `NavigationLink`. None ran on a phone. The phone SwiftUI stubs do not export `NavigationStack`.

## v0.1.0

First tagged release of omarchy-apple-dev. It added Linux builds for iOS apps without Xcode. It added a portable toolchain, resource tools, project setup, Flutter support, and macOS builds. The release included app and device-run records.

An earlier metadata check matched five files of five in three tests. Other parts have device records. They lack an offline test suite.
