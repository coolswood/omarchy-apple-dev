/**
 * Bridgeless safety shim for RN 0.87 iOS: register the legacy
 * RCTEventEmitter callable JS module before the app runs.
 *
 * Why: on the bridgeless iOS runtime any RCTEvent dispatch (touch, scroll,
 * component events from RCTEventDispatcher.dispatchEvent:) calls into JS
 * via ReactInstance::callFunctionOnModule, which throws
 * "Module has not been registered as callable" and aborts the app when
 * RCTEventEmitter was never registered. setUpBatchedBridge.js registers
 * seven callable modules and RCTEventEmitter is not one of them; nothing
 * else registers it either, so a stock app that fires one legacy event
 * crashes on launch.
 *
 * The shim is a no-op receiver: legacy events are dropped, which is what a
 * new-architecture app that never subscribes to legacy events expects.
 * Registering twice is idempotent, so an app that registers its own
 * RCTEventEmitter still works.
 */
import RCTEventEmitter from 'react-native/Libraries/EventEmitter/RCTEventEmitter';
import './index.js';

RCTEventEmitter.register({
  receiveEvent() {},
  receiveTouches() {},
});
