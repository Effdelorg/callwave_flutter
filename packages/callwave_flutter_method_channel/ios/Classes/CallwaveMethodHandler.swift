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

    case "endCall":
      let args = call.arguments as? [String: Any]
      guard let callId = args?["callId"] as? String else {
        result(FlutterError(code: "invalid_call_id", message: "callId is required", details: nil))
        return
      }
      callManager.endCall(callId: callId)
      result(nil)

    case "markMissed":
      let args = call.arguments as? [String: Any]
      guard let callId = args?["callId"] as? String else {
        result(FlutterError(code: "invalid_call_id", message: "callId is required", details: nil))
        return
      }
      callManager.markMissed(callId: callId)
      result(nil)

    case "getActiveCallIds":
      result(callManager.activeCallIds())

    case "requestNotificationPermission":
      result(true)

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
