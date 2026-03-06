import Foundation
import CallKit

final class IOSCallManager {
  private let eventBridge: EventStreamBridge
  private let activeCallRegistry: ActiveCallRegistry
  private let provider: CXProvider
  private let callController = CXCallController()
  private let delegate = CallKitProviderDelegate()
  private let backgroundValidator = IOSBackgroundValidator()

  private var payloadStore: [String: CallPayload] = [:]
  private var uuidByCallId: [String: UUID] = [:]
  private var callIdByUuid: [UUID: String] = [:]
  private var pendingAcceptedCallIds: Set<String> = []
  private var confirmedAcceptedCallIds: Set<String> = []
  private var outgoingCallIds: Set<String> = []
  private var timeoutItems: [String: DispatchWorkItem] = [:]
  private var postCallBehavior: PostCallBehavior = .stayOpen
  private var backgroundDispatcherHandle: Int64?
  private var backgroundCallbackHandle: Int64?

  init(eventBridge: EventStreamBridge, activeCallRegistry: ActiveCallRegistry) {
    self.eventBridge = eventBridge
    self.activeCallRegistry = activeCallRegistry

    let config = CXProviderConfiguration(localizedName: "Callwave")
    config.supportsVideo = true
    config.maximumCallsPerCallGroup = 1
    config.maximumCallGroups = 1

    self.provider = CXProvider(configuration: config)
    delegate.onAccept = { [weak self] uuid in self?.handleAccept(uuid: uuid) }
    delegate.onEnd = { [weak self] uuid, reason in self?.handleEnd(uuid: uuid, reason: reason) }
    delegate.onDidReset = { [weak self] in self?.handleReset() }
    provider.setDelegate(delegate, queue: nil)
  }

  func showIncomingCall(_ payload: CallPayload) {
    guard activeCallRegistry.tryStart(callId: payload.callId) else {
      emit(callId: payload.callId, type: "declined", extra: payload.extra)
      return
    }

    payloadStore[payload.callId] = payload
    pendingAcceptedCallIds.remove(payload.callId)
    confirmedAcceptedCallIds.remove(payload.callId)
    outgoingCallIds.remove(payload.callId)
    let uuid = uuidByCallId[payload.callId] ?? UUID()
    uuidByCallId[payload.callId] = uuid
    callIdByUuid[uuid] = payload.callId

    let update = CXCallUpdate()
    update.localizedCallerName = payload.callerName
    update.remoteHandle = CXHandle(type: .generic, value: payload.handle)
    update.hasVideo = payload.callType == "video"

    provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
      if error != nil {
        self?.activeCallRegistry.remove(callId: payload.callId)
      } else {
        self?.scheduleIncomingTimeout(payload: payload, uuid: uuid)
      }
    }
  }

  func showOutgoingCall(_ payload: CallPayload) {
    guard activeCallRegistry.tryStart(callId: payload.callId) else {
      emit(callId: payload.callId, type: "declined", extra: payload.extra)
      return
    }

    payloadStore[payload.callId] = payload
    pendingAcceptedCallIds.remove(payload.callId)
    confirmedAcceptedCallIds.remove(payload.callId)
    outgoingCallIds.insert(payload.callId)
    let uuid = UUID()
    uuidByCallId[payload.callId] = uuid
    callIdByUuid[uuid] = payload.callId

    let handle = CXHandle(type: .generic, value: payload.handle)
    let startAction = CXStartCallAction(call: uuid, handle: handle)
    startAction.isVideo = payload.callType == "video"

    let transaction = CXTransaction(action: startAction)
    callController.request(transaction) { [weak self] _ in
      self?.emit(callId: payload.callId, type: "started", extra: payload.extra)
    }
  }

  func endCall(callId: String) {
    guard let uuid = uuidByCallId[callId] else {
      emit(callId: callId, type: "ended", extra: nil)
      applyPostCallBehaviorIfNeeded()
      return
    }

    let endAction = CXEndCallAction(call: uuid)
    let transaction = CXTransaction(action: endAction)
    callController.request(transaction) { [weak self] _ in
      self?.cleanup(callId: callId, uuid: uuid)
      self?.emit(callId: callId, type: "ended", extra: nil)
      self?.applyPostCallBehaviorIfNeeded()
    }
  }

  func acceptCall(callId: String) -> Bool {
    guard let uuid = uuidByCallId[callId], payloadStore[callId] != nil else {
      return false
    }
    handleAccept(uuid: uuid)
    return true
  }

  func confirmAcceptedCall(callId: String) -> Bool {
    guard pendingAcceptedCallIds.contains(callId) || confirmedAcceptedCallIds.contains(callId) else {
      return false
    }
    pendingAcceptedCallIds.remove(callId)
    confirmedAcceptedCallIds.insert(callId)
    return true
  }

  func registerBackgroundIncomingCallValidator(
    backgroundDispatcherHandle: Int64,
    backgroundCallbackHandle: Int64
  ) {
    self.backgroundDispatcherHandle = backgroundDispatcherHandle
    self.backgroundCallbackHandle = backgroundCallbackHandle
  }

  func clearBackgroundIncomingCallValidator() {
    backgroundDispatcherHandle = nil
    backgroundCallbackHandle = nil
  }

  func declineCall(callId: String) -> Bool {
    guard let uuid = uuidByCallId[callId], payloadStore[callId] != nil else {
      return false
    }
    let payload = payloadStore[callId]
    cancelTimeout(callId: callId)
    provider.reportCall(with: uuid, endedAt: Date(), reason: .declinedElsewhere)
    cleanup(callId: callId, uuid: uuid)
    emit(callId: callId, type: "declined", extra: payload?.extra)
    return true
  }

  func markMissed(callId: String, extra: [String: Any]? = nil) {
    let payload = payloadStore[callId]
    cancelTimeout(callId: callId)
    if let uuid = uuidByCallId[callId] {
      provider.reportCall(with: uuid, endedAt: Date(), reason: .unanswered)
      cleanup(callId: callId, uuid: uuid)
    } else {
      activeCallRegistry.remove(callId: callId)
      payloadStore.removeValue(forKey: callId)
      pendingAcceptedCallIds.remove(callId)
      confirmedAcceptedCallIds.remove(callId)
      outgoingCallIds.remove(callId)
    }
    emit(
      callId: callId,
      type: "missed",
      extra: eventExtra(payload: payload, fallbackExtra: extra)
    )
  }

  func activeCallIds() -> [String] {
    activeCallRegistry.activeCallIds()
  }

  func activeCallEventSnapshots() -> [[String: Any]] {
    activeCallRegistry.activeCallIds().map { callId in
      let payload = payloadStore[callId]
      let type: String
      if pendingAcceptedCallIds.contains(callId) || confirmedAcceptedCallIds.contains(callId) {
        type = "accepted"
      } else if outgoingCallIds.contains(callId) {
        type = "started"
      } else {
        type = "incoming"
      }
      return CallEventPayload.now(
        callId: callId,
        type: type,
        extra: type == "accepted"
          ? acceptedEventExtra(callId: callId, payload: payload)
          : eventExtra(payload: payload)
      ).toDictionary()
    }
  }

  func syncActiveCallsToEvents() {
    for callId in activeCallRegistry.activeCallIds() {
      let payload = payloadStore[callId]
      if pendingAcceptedCallIds.contains(callId) || confirmedAcceptedCallIds.contains(callId) {
        emit(callId: callId, type: "accepted", extra: acceptedEventExtra(callId: callId, payload: payload))
      } else if outgoingCallIds.contains(callId) {
        emit(callId: callId, type: "started", extra: eventExtra(payload: payload))
      } else {
        emit(callId: callId, type: "incoming", extra: eventExtra(payload: payload))
      }
    }
  }

  func setPostCallBehavior(rawValue: String?) {
    postCallBehavior = PostCallBehavior(rawValue: rawValue ?? "stayOpen") ?? .stayOpen
  }

  func handleAccept(uuid: UUID) {
    guard let callId = callIdByUuid[uuid] else { return }
    let payload = payloadStore[callId]
    cancelTimeout(callId: callId)
    pendingAcceptedCallIds.insert(callId)
    confirmedAcceptedCallIds.remove(callId)
    outgoingCallIds.remove(callId)
    guard let payload else { return }
    if payload.incomingAcceptStrategy == "deferOpenUntilConfirmed" {
      let startedBackgroundValidation = maybeRunBackgroundValidation(callId: callId, payload: payload)
      if !startedBackgroundValidation {
        emit(
          callId: callId,
          type: "accepted",
          extra: acceptedEventExtra(callId: callId, payload: payload)
        )
      }
      return
    }
    emit(
      callId: callId,
      type: "accepted",
      extra: acceptedEventExtra(callId: callId, payload: payload)
    )
    _ = confirmAcceptedCall(callId: callId)
  }

  func handleEnd(uuid: UUID, reason: CXCallEndedReason?) {
    guard let callId = callIdByUuid[uuid] else { return }
    let payload = payloadStore[callId]
    cleanup(callId: callId, uuid: uuid)

    let type = reason == .unanswered ? "timeout" : "ended"
    emit(callId: callId, type: type, extra: payload?.extra)
    if type == "timeout" {
      emit(callId: callId, type: "missed", extra: payload?.extra)
    }
  }

  func emitCallback(callId: String) {
    emit(callId: callId, type: "callback", extra: payloadStore[callId]?.extra)
  }

  private func handleReset() {
    timeoutItems.values.forEach { $0.cancel() }
    timeoutItems.removeAll()
    for callId in payloadStore.keys {
      activeCallRegistry.remove(callId: callId)
    }
    payloadStore.removeAll()
    uuidByCallId.removeAll()
    callIdByUuid.removeAll()
    pendingAcceptedCallIds.removeAll()
    confirmedAcceptedCallIds.removeAll()
    outgoingCallIds.removeAll()
  }

  private func cleanup(callId: String, uuid: UUID) {
    cancelTimeout(callId: callId)
    activeCallRegistry.remove(callId: callId)
    payloadStore.removeValue(forKey: callId)
    uuidByCallId.removeValue(forKey: callId)
    callIdByUuid.removeValue(forKey: uuid)
    pendingAcceptedCallIds.remove(callId)
    confirmedAcceptedCallIds.remove(callId)
    outgoingCallIds.remove(callId)
  }

  private func emit(callId: String, type: String, extra: [String: Any]?) {
    eventBridge.emit(CallEventPayload.now(callId: callId, type: type, extra: extra))
  }

  private func scheduleIncomingTimeout(payload: CallPayload, uuid: UUID) {
    cancelTimeout(callId: payload.callId)

    let workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      guard self.payloadStore[payload.callId] != nil else { return }

      self.provider.reportCall(with: uuid, endedAt: Date(), reason: .unanswered)
      self.emit(callId: payload.callId, type: "timeout", extra: payload.extra)
      self.emit(callId: payload.callId, type: "missed", extra: payload.extra)
      self.cleanup(callId: payload.callId, uuid: uuid)
    }

    timeoutItems[payload.callId] = workItem
    let delaySeconds = max(payload.timeoutSeconds, 1)
    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delaySeconds), execute: workItem)
  }

  private func cancelTimeout(callId: String) {
    timeoutItems[callId]?.cancel()
    timeoutItems.removeValue(forKey: callId)
  }

  private func applyPostCallBehaviorIfNeeded() {
    switch postCallBehavior {
    case .stayOpen:
      return
    case .backgroundOnEnded:
      // iOS should not force-close/background the app from a plugin.
      return
    }
  }

  private func eventExtra(
    payload: CallPayload?,
    fallbackExtra: [String: Any]? = nil
  ) -> [String: Any] {
    var merged = fallbackExtra ?? [:]
    if let payloadExtra = payload?.extra {
      merged.merge(payloadExtra) { _, new in new }
    }
    merged["callerName"] = payload?.callerName ?? (merged["callerName"] as? String ?? "Unknown")
    merged["handle"] = payload?.handle ?? (merged["handle"] as? String ?? "")
    merged["callType"] = payload?.callType ?? (merged["callType"] as? String ?? "audio")
    merged["avatarUrl"] = payload?.avatarUrl ?? merged["avatarUrl"] ?? NSNull()

    return merged
  }

  private func acceptedEventExtra(
    callId: String,
    payload: CallPayload?,
    fallbackExtra: [String: Any]? = nil
  ) -> [String: Any] {
    var merged = eventExtra(payload: payload, fallbackExtra: fallbackExtra)
    merged["acceptanceState"] = acceptedState(for: callId)
    return merged
  }

  private func acceptedState(for callId: String) -> String? {
    if confirmedAcceptedCallIds.contains(callId) {
      return "confirmed"
    }
    if pendingAcceptedCallIds.contains(callId) {
      return "pendingValidation"
    }
    return nil
  }

  private func maybeRunBackgroundValidation(callId: String, payload: CallPayload) -> Bool {
    guard !eventBridge.hasListener else {
      return false
    }
    guard
      let backgroundDispatcherHandle,
      let backgroundCallbackHandle
    else {
      return false
    }
    backgroundValidator.validate(
      backgroundDispatcherHandle: backgroundDispatcherHandle,
      backgroundCallbackHandle: backgroundCallbackHandle,
      payload: payload
    ) { [weak self] decision in
      guard let self else { return }
      guard self.activeCallRegistry.activeCallIds().contains(callId) else { return }
      if decision.isAllowed {
        _ = self.confirmAcceptedCall(callId: callId)
      } else {
        var extra = self.eventExtra(payload: payload, fallbackExtra: decision.extra)
        extra["outcomeReason"] = decision.reason ?? "failed"
        self.markMissed(callId: callId, extra: extra)
      }
    }
    return true
  }
}

private enum PostCallBehavior: String {
  case stayOpen
  case backgroundOnEnded
}
