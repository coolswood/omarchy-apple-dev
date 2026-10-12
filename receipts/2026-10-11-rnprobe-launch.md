# RNProbe phone launch results

2026-10-11. iPhone 15 Pro Max (iPhone16,2), iOS 27.0.1 (24A446). App: RNProbe. React Native 0.87.1. Bundle ID: `com.joshuawarren.omarchyappledev.rnprobe`. Runs used the tailnet.

## Five crash reports

The reports were pulled with `pymobiledevice3 crash pull`. Each captured launch ended in 1 second or less.

| Launch to capture, CDT (-0500) | Time |
|---|---:|
| 10:48:51.854 to 10:48:52.567 | 0.71 s |
| 11:25:13.966 to 11:25:14.222 | 0.26 s |
| 11:25:15.344 to 11:25:15.495 | 0.15 s |
| 11:34:08.159 to 11:34:08.561 | 0.40 s |
| 12:09:55.476 to 12:09:55.764 | 0.29 s |

All five reports show `EXC_CRASH`, `SIGABRT`, and `Abort trap: 6`. The faulting thread was `com.meta.react.turbomodulemanager.queue`. Frames include `abort`, `__cxa_rethrow`, `objc_exception_rethrow`, and `React ObjCTurboModule performVoidMethodInvocation`. The last exception backtrace includes `RCTGetFatalHandler`, `-[RCTExceptionsManager reportFatal:stack:exceptionId:extraDataAsJSON:]`, and `reportException`. The main and JavaScript threads were idle in the run loop at capture. Each report includes a Hermes image.

## Stream launch

At 12:42:01 CDT, `pymobiledevice3 developer dvt launch <bundle id> --stream` logged `ReactInstance evaluateJavaScript` with the JavaScript bundle. Stderr then reported:

```text
Unhandled JS Exception: Error: Failed to call into JavaScript module method RCTEventEmitter.receiveEvent(). Module has not been registered as callable. Registered callable JavaScript modules (n = 7): AppRegistry, HMRClient, GlobalPerformanceLogger, RCTDeviceEventEmitter, RCTLog, RCTNativeAppEventEmitter, Systrace.
```

The app then aborted. A control launch at 13:01 CDT used `MallocStackLogging=1` without a debugger. The stream showed the same fatal exception. The app was not running after 25 seconds.

## Launch count

Seven launches without a debugger ended in the same abort. This count includes five crash reports, the stream launch, and the control launch. The five crash reports show an abort within one second of launch. The stream launch aborted in the same second it started. The control launch was not timed beyond 25 seconds. Earlier launch checks returned a process ID. The app was not running after 10 seconds in those checks.

## Debugger run

The debugger attached from the first instruction over the tailnet debug route. The run lasted from 17:54 to 17:59Z. The app was still running after 220 seconds. A breakpoint on `-[RCTEventDispatcher sendEvent:]` resolved to one location and was never hit.

## Not checked

Nobody checked the screen or took a screenshot. What the app draws is unknown. The cause of the early event is unknown.

Later result: the abort came from a stale JS bundle, not from the runtime. See `receipts/2026-10-12-rnprobe-stale-bundle.md`.
