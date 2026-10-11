# Changelog

## v0.2.0

### Build routes

- The setup guide lists no-Xcode needs apart from full-mode needs. No-Xcode setup needs Linux, an iPhone for app runs, an Apple ID for signing, and about 7 GB of temporary disk space.
- A run in an Ubuntu 24.04 container now has setup and build results.

### Device run and over-tailnet

- `device-run.sh --over-tailnet` installs and launches an app without a cable. It also saves a screenshot and reads the system log over Tailscale. Pair once over USB first. The phone needs Wi-Fi. Cellular-only access failed.
- The debugger stopped at the app's `main` breakpoint after waiting 220 seconds. Earlier tries did not stop there.

### Simulation research and simview

- M1 ran a small arm64 C program through the Linux loader on an arm64 Linux laptop. This proves the loader and its syscall shims. It does not prove Objective-C or Swift support.
- M2 draws a 390 by 844 frame on Linux. It compares the frame with a saved image.
- M3 adds scripted touch frames and hit testing. It updates `@State` and draws the frame again. It does not support scrolling, gestures, or windows.
- M4 adds a simulated navigation stack. Scripted actions push and pop screens. The recorded run passed seven test rows and five mutation checks.
- Simview uses our own SwiftUI-like module. It does not match Apple's renderer or navigation behavior.

### React Native probe

- We built and signed the probe. Its phone launch check over the tailnet failed. It returned no process ID. No successful phone run is recorded.

### Documentation

- New documents cover simulation input, host needs, Ubuntu setup, tailnet limits, and M1 through M4. Run records support the results.
- The wider device-side SwiftUI declarations include `Color`, `Font`, `padding`, `List`, `ForEach`, and `NavigationLink`. None ran on a phone. The phone SwiftUI stubs do not export `NavigationStack`.

## v0.1.0

First tagged release of omarchy-apple-dev. It added Linux builds for iOS apps without Xcode. It added a portable toolchain, resource tools, project setup, Flutter support, and macOS builds. The release included app and device-run records.

A metadata check found five of five files matched the output from the same Xcode version. This result held in three test cases. Other areas have device records. They do not have an offline test suite.
