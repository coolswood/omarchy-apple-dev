/**
 * Bridgeless fallback for RN 0.87 iOS: register a no-op legacy
 * RCTEventEmitter callable JS module when the app did not register one.
 *
 * Why: on the bridgeless iOS runtime a legacy RCTEvent dispatch (touch,
 * scroll, component events from RCTEventDispatcher.dispatchEvent:) calls
 * into JS through ReactInstance::callFunctionOnModule. That call throws
 * "Module has not been registered as callable" and aborts the app when
 * RCTEventEmitter was never registered. setUpBatchedBridge.js registers
 * seven callable modules and RCTEventEmitter is not one of them. No other
 * JS file in react-native 0.87.1 registers it.
 *
 * Order: the import of ./index.js runs first, so any registration the app
 * makes comes first. In the bridgeless runtime the first registration of a
 * name is kept (ReactInstance.cpp, callableModules_.emplace), so the app's
 * own RCTEventEmitter wins and this no-op only fills the gap.
 *
 * The no-op drops legacy events. It hides the cause of the early event; it
 * does not find it. Not verified on a phone yet.
 */
import RCTEventEmitter from 'react-native/Libraries/EventEmitter/RCTEventEmitter';
import './index.js';

RCTEventEmitter.register({
  receiveEvent() {},
  receiveTouches() {},
});
