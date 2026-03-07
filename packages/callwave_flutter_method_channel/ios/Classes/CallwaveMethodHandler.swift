import Foundation
import Flutter

final class CallwaveMethodHandler {
  private let callManager: IOSCallManager

  init(callManager: IOSCallManager) {
    self.callManager = callManager
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      result(nil)

    case "showIncomingCall":
      guard
        let args = call.arguments as? [String: Any],
        let payload = CallPayload(dictionary: args)
      else {
        result(FlutterError(code: "invalid_payload", message: "Missing incoming payload", details: nil))
        return
      }
      callManager.showIncomingCall(payload)
      result(nil)

    case "showOutgoingCall":
      guard
        let args = call.arguments as? [String: Any],
        let payload = CallPayload(dictionary: args)
      else {
        result(FlutterError(code: "invalid_payload", message: "Missing outgoing payload", details: nil))
        return
      }
      callManager.showOutgoingCall(payload)
      result(nil)

    case "registerBackgroundIncomingCallValidator":
      let args = call.arguments as? [String: Any]
      guard
        let dispatcherHandle = (args?["backgroundDispatcherHandle"] as? NSNumber)?.int64Value
      else {
        result(
          FlutterError(
            code: "invalid_background_validator",
            message: "Dispatcher handle is required",
            details: nil
          )
        )
        return
      }
      let acceptCallbackHandle = (args?["backgroundCallbackHandle"] as? NSNumber)?.int64Value
      let declineCallbackHandle =
        (args?["backgroundDeclineCallbackHandle"] as? NSNumber)?.int64Value
      guard acceptCallbackHandle != nil || declineCallbackHandle != nil else {
        result(
          FlutterError(
            code: "invalid_background_validator",
            message: "At least one callback handle is required",
            details: nil
          )
        )
        return
      }
      callManager.registerBackgroundIncomingCallValidator(
        backgroundDispatcherHandle: dispatcherHandle,
        backgroundAcceptCallbackHandle: acceptCallbackHandle,
        backgroundDeclineCallbackHandle: declineCallbackHandle
      )
      result(nil)

    case "clearBackgroundIncomingCallValidator":
      callManager.clearBackgroundIncomingCallValidator()
      result(nil)

    case "endCall":
      let args = call.arguments as? [String: Any]
      guard let callId = args?["callId"] as? String else {
        result(FlutterError(code: "invalid_call_id", message: "callId is required", details: nil))
        return
      }
      callManager.endCall(callId: callId)
      result(nil)

    case "acceptCall":
      let args = call.arguments as? [String: Any]
      guard let callId = args?["callId"] as? String else {
        result(FlutterError(code: "invalid_call_id", message: "callId is required", details: nil))
        return
      }
      guard callManager.acceptCall(callId: callId) else {
        result(
          FlutterError(
            code: "invalid_call_id",
            message: "No active incoming call found for callId=\(callId)",
            details: nil
          )
        )
        return
      }
      result(nil)

    case "confirmAcceptedCall":
      let args = call.arguments as? [String: Any]
      guard let callId = args?["callId"] as? String else {
        result(FlutterError(code: "invalid_call_id", message: "callId is required", details: nil))
        return
      }
      guard callManager.confirmAcceptedCall(callId: callId) else {
        result(
          FlutterError(
            code: "invalid_call_id",
            message: "No active accepted call found for callId=\(callId)",
            details: nil
          )
        )
        return
      }
      result(nil)

    case "declineCall":
      let args = call.arguments as? [String: Any]
      guard let callId = args?["callId"] as? String else {
        result(FlutterError(code: "invalid_call_id", message: "callId is required", details: nil))
        return
      }
      guard callManager.declineCall(callId: callId) else {
        result(
          FlutterError(
            code: "invalid_call_id",
            message: "No active incoming call found for callId=\(callId)",
            details: nil
          )
        )
        return
      }
      result(nil)

    case "markMissed":
      let args = call.arguments as? [String: Any]
      guard let callId = args?["callId"] as? String else {
        result(FlutterError(code: "invalid_call_id", message: "callId is required", details: nil))
        return
      }
      let extra = args?["extra"] as? [String: Any]
      callManager.markMissed(callId: callId, extra: extra)
      result(nil)

    case "syncCallConnectedState":
      let args = call.arguments as? [String: Any]
      guard
        let callId = args?["callId"] as? String,
        let connectedAtMs = (args?["connectedAtMs"] as? NSNumber)?.int64Value,
        connectedAtMs > 0
      else {
        result(
          FlutterError(
            code: "invalid_connected_state",
            message: "callId and connectedAtMs are required",
            details: nil
          )
        )
        return
      }
      callManager.syncCallConnectedState(callId: callId, connectedAtMs: connectedAtMs)
      result(nil)

    case "clearCallState":
      let args = call.arguments as? [String: Any]
      guard let callId = args?["callId"] as? String else {
        result(FlutterError(code: "invalid_call_id", message: "callId is required", details: nil))
        return
      }
      callManager.clearCallState(callId: callId)
      result(nil)

    case "getActiveCallIds":
      result(callManager.activeCallIds())

    case "getActiveCallEventSnapshots":
      result(callManager.activeCallEventSnapshots())

    case "syncActiveCallsToEvents":
      callManager.syncActiveCallsToEvents()
      result(nil)

    case "requestNotificationPermission":
      callManager.requestNotificationPermission(result: result)

    case "takePendingStartupAction":
      result(callManager.takePendingStartupAction())

    case "requestFullScreenIntentPermission":
      result(nil)

    case "setPostCallBehavior":
      let args = call.arguments as? [String: Any]
      let behavior = args?["postCallBehavior"] as? String
      callManager.setPostCallBehavior(rawValue: behavior)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
