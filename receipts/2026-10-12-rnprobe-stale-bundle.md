# RNProbe: the abort came from a stale JS bundle

2026-10-11 evening (CDT). iPhone 15 Pro Max (iPhone16,2), iOS 27.0.1 (24A446). App: RNProbe, React Native 0.87.1. Install and launch ran from a Linux machine over the tailnet, with `pymobiledevice3 apps install` and `pymobiledevice3 developer dvt launch <bundle id> --stream`. Each launch ran 25 seconds.

This receipt replaces the cause open in `receipts/2026-10-11-rnprobe-launch.md`.

## Phone results

| Build | sha256 (first 16) | Launches | Result |
|---|---|---|---|
| Original ipa from 2026-10-09 | `44bea4269a9bd489` | 3 | All 3 aborted: `RCTEventEmitter.receiveEvent()` not registered. App not running after 25 s. |
| Rebuilt from the current `App.tsx`, no shim | `54d64ea3ae5ce982` | 4 | All 4 running after 25 s. No `RCTFatalException` in stderr. |
| Rebuilt, with a no-op `RCTEventEmitter` shim | `35ef56f29213ddb7` | 1 | Running after 25 s. No fatal. |

With the 7 earlier aborts of the original ipa, that build has aborted 10 of 10 launches. The rebuilt builds have not aborted in 5 launches.

## What differs between the builds

- The native files differ only by the code signature: `RNProbe` 4464 differing bytes, `React` 1170, `hermesvm` 1166, `ReactNativeDependencies` 4340 (`cmp -l`). File sizes are identical.
- `main.jsbundle` differs: 1254057 bytes against 1237259 bytes.
- The plain JS of the original bundle contains `RNCSafeAreaProvider` and `RNCSafeAreaView` (2 matches each). The rebuilt bundles contain neither.
- Time stamps: the original JS bundle was built 2026-10-09 18:30. `App.tsx` was changed at 18:39, to use React Native's own `SafeAreaView`. The ipa was signed at 18:42 and kept the 18:30 bundle.

## Reading

The ipa shipped a bundle built from the old template `App.tsx`. That file used `react-native-safe-area-context`, which has native components this app does not have. The abort happens on that bundle and not on a bundle built from the current `App.tsx`. The exact mechanism is not proven. My inference is that the missing native component sends a legacy event. The shim is not needed: the rebuild runs without it.

## Not checked

Nobody checked the screen. What the app draws is unknown. The run did not use a debugger. The lock state of the phone was not recorded.

## Fix for the route

Build the bundle after the last edit of the app source. `rn-js.sh` always runs Metro, so a rebuild with `rn-js.sh` fixes it. Check the bundle time stamp against `App.tsx` before you sign.
