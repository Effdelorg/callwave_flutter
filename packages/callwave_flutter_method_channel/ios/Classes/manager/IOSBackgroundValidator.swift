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

  /// Matches [AndroidBackgroundValidator.VALIDATION_TIMEOUT_MS].
  private static let validationTimeout: TimeInterval = 8.0

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

    removeQueuedValidations(forCallId: payload.callId)

    let completion = ValidationCompletion(onComplete: onComplete)
    pendingValidations.append(
      PendingValidation(
        action: action,
        backgroundCallbackHandle: backgroundCallbackHandle,
        payload: payload,
        completion: completion
      )
    )
    flushPendingValidations()
  }

  private func removeQueuedValidations(forCallId callId: String) {
    pendingValidations.removeAll { $0.payload.callId == callId }
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
    CallwaveFlutterPlugin.registerPluginsForBackgroundEngine(flutterEngine)
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
    let completion = pending.completion

    let timeoutWork = DispatchWorkItem { [weak self] in
      completion.complete(
        BackgroundValidationResult(
          isAllowed: false,
          reason: "failed",
          extra: nil
        )
      )
      self?.isValidationInFlight = false
      self?.flushPendingValidations()
    }
    DispatchQueue.main.asyncAfter(
      deadline: .now() + Self.validationTimeout,
      execute: timeoutWork
    )

    channel.invokeMethod(
      pending.action.methodName,
      arguments: [
        "backgroundCallbackHandle": pending.backgroundCallbackHandle,
        "callData": pending.payload.dictionary,
      ]
    ) { [weak self] result in
      timeoutWork.cancel()
      let parsed: BackgroundValidationResult
      if result is FlutterError {
        parsed = BackgroundValidationResult(
          isAllowed: false,
          reason: "failed",
          extra: nil
        )
      } else if let map = result as? [String: Any] {
        parsed = BackgroundValidationResult(
          isAllowed: map[pending.action.successKey] as? Bool ?? false,
          reason: map["reason"] as? String,
          extra: map["extra"] as? [String: Any]
        )
      } else {
        parsed = BackgroundValidationResult(
          isAllowed: false,
          reason: "failed",
          extra: nil
        )
      }
      completion.complete(parsed)
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
    let completion: ValidationCompletion
  }

  private final class ValidationCompletion {
    private let lock = NSLock()
    private var completed = false
    private let onComplete: (BackgroundValidationResult) -> Void

    init(onComplete: @escaping (BackgroundValidationResult) -> Void) {
      self.onComplete = onComplete
    }

    func complete(_ result: BackgroundValidationResult) {
      lock.lock()
      defer { lock.unlock() }
      guard !completed else { return }
      completed = true
      onComplete(result)
    }
  }
}
