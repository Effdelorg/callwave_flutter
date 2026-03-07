import Foundation
import Flutter

final class IOSBackgroundValidator {
  private enum BackgroundAction {
    case acceptValidation
    case declineReport

    var methodName: String {
      switch self {
      case .acceptValidation:
        return "validateBackgroundIncomingCall"
      case .declineReport:
        return "reportBackgroundIncomingCallDecline"
      }
    }

    var successKey: String {
      switch self {
      case .acceptValidation:
        return "isAllowed"
      case .declineReport:
        return "isReported"
      }
    }
  }

  private var engine: FlutterEngine?
  private var channel: FlutterMethodChannel?
  private var activeDispatcherHandle: Int64?
  private var dispatcherReady = false
  private var pendingValidations: [PendingValidation] = []
  private var isValidationInFlight = false

  func validateAccept(
    backgroundDispatcherHandle: Int64,
    backgroundCallbackHandle: Int64,
    payload: CallPayload,
    onComplete: @escaping (BackgroundValidationResult) -> Void
  ) {
    run(
      action: .acceptValidation,
      backgroundDispatcherHandle: backgroundDispatcherHandle,
      backgroundCallbackHandle: backgroundCallbackHandle,
      payload: payload,
      onComplete: onComplete
    )
  }

  func reportDecline(
    backgroundDispatcherHandle: Int64,
    backgroundCallbackHandle: Int64,
    payload: CallPayload,
    onComplete: @escaping (BackgroundValidationResult) -> Void
  ) {
    run(
      action: .declineReport,
      backgroundDispatcherHandle: backgroundDispatcherHandle,
      backgroundCallbackHandle: backgroundCallbackHandle,
      payload: payload,
      onComplete: onComplete
    )
  }

  private func run(
    action: BackgroundAction,
    backgroundDispatcherHandle: Int64,
    backgroundCallbackHandle: Int64,
    payload: CallPayload,
    onComplete: @escaping (BackgroundValidationResult) -> Void
  ) {
    guard ensureEngine(backgroundDispatcherHandle: backgroundDispatcherHandle) else {
      onComplete(
        BackgroundValidationResult(
          isAllowed: false,
          reason: "failed",
          extra: nil
        )
      )
      return
    }

    pendingValidations.append(
      PendingValidation(
        action: action,
        backgroundCallbackHandle: backgroundCallbackHandle,
        payload: payload,
        onComplete: onComplete
      )
    )
    flushPendingValidations()
  }

  private func ensureEngine(backgroundDispatcherHandle: Int64) -> Bool {
    if engine != nil, activeDispatcherHandle == backgroundDispatcherHandle {
      return true
    }

    guard
      let callbackInfo = FlutterCallbackCache.lookupCallbackInformation(backgroundDispatcherHandle)
    else {
      return false
    }

    let flutterEngine = FlutterEngine(
      name: "callwave_background_validator",
      project: nil,
      allowHeadlessExecution: true
    )
    channel = FlutterMethodChannel(
      name: "callwave_flutter/background",
      binaryMessenger: flutterEngine.binaryMessenger
    )
    channel?.setMethodCallHandler { [weak self] call, result in
      self?.handleMethodCall(call, result: result)
    }

    let didStart = flutterEngine.run(
      withEntrypoint: callbackInfo.callbackName,
      libraryURI: callbackInfo.callbackLibraryPath
    )
    guard didStart else {
      channel?.setMethodCallHandler(nil)
      channel = nil
      return false
    }

    engine = flutterEngine
    activeDispatcherHandle = backgroundDispatcherHandle
    dispatcherReady = false
    return true
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "backgroundDispatcherReady":
      dispatcherReady = true
      result(nil)
      flushPendingValidations()
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func flushPendingValidations() {
    guard dispatcherReady, let channel, !isValidationInFlight else { return }
    guard !pendingValidations.isEmpty else { return }

    isValidationInFlight = true
    let pending = pendingValidations.removeFirst()
    channel.invokeMethod(
      pending.action.methodName,
      arguments: [
        "backgroundCallbackHandle": pending.backgroundCallbackHandle,
        "callData": pending.payload.dictionary,
      ]
    ) { [weak self] result in
      let map = result as? [String: Any]
      pending.onComplete(
        BackgroundValidationResult(
          isAllowed: map?[pending.action.successKey] as? Bool ?? false,
          reason: map?["reason"] as? String,
          extra: map?["extra"] as? [String: Any]
        )
      )
      self?.isValidationInFlight = false
      self?.flushPendingValidations()
    }
  }

  struct BackgroundValidationResult {
    let isAllowed: Bool
    let reason: String?
    let extra: [String: Any]?
  }

  private struct PendingValidation {
    let action: BackgroundAction
    let backgroundCallbackHandle: Int64
    let payload: CallPayload
    let onComplete: (BackgroundValidationResult) -> Void
  }
}
