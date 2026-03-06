import Foundation
import Flutter

final class IOSBackgroundValidator {
  private var engine: FlutterEngine?
  private var channel: FlutterMethodChannel?
  private var activeDispatcherHandle: Int64?
  private var dispatcherReady = false
  private var pendingValidations: [PendingValidation] = []
  private var isValidationInFlight = false

  func validate(
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
      "validateBackgroundIncomingCall",
      arguments: [
        "backgroundCallbackHandle": pending.backgroundCallbackHandle,
        "callData": pending.payload.dictionary,
      ]
    ) { [weak self] result in
      let map = result as? [String: Any]
      pending.onComplete(
        BackgroundValidationResult(
          isAllowed: map?["isAllowed"] as? Bool ?? false,
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
    let backgroundCallbackHandle: Int64
    let payload: CallPayload
    let onComplete: (BackgroundValidationResult) -> Void
  }
}
