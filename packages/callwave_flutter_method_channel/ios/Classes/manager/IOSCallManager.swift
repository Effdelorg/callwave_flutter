import Foundation
import CallKit
import Flutter
import UIKit
import UserNotifications

final class IOSCallManager {
  /// Wire values mirrored in Dart [CallEventExtraKeys.outcomeReason] documentation.
  private static let outcomeCallkitStartFailed = "callkit_start_failed"
  private static let outcomeCallkitEndFailed = "callkit_end_failed"
  private static let outcomeIncomingPresentationFailed = "incoming_presentation_failed"

  private let eventBridge: EventStreamBridge
  private let activeCallRegistry: ActiveCallRegistry
  private let provider: CXProvider
  private let notificationCenter: NotificationCenter
  private let missedCallNotificationManager: MissedCallNotificationManager
  private let pendingStartupActionStore: PendingStartupActionStore
  private let ongoingCallStore: OngoingCallStore
  private let incomingCallStore: IncomingCallStore
  private let callController = CXCallController()
  private let delegate = CallKitProviderDelegate()
  private let backgroundValidator = IOSBackgroundValidator()
  private let backgroundValidatorRegistrationStore: BackgroundValidatorRegistrationStore

  private var payloadStore: [String: CallPayload] = [:]
  private var uuidByCallId: [String: UUID] = [:]
  private var callIdByUuid: [UUID: String] = [:]
  private var pendingAcceptedCallIds: Set<String> = []
  private var confirmedAcceptedCallIds: Set<String> = []
  private var launchActionOverrides: [String: String] = [:]
  private var explicitIncomingLaunchEmittedCallIds: Set<String> = []
  private var explicitOngoingLaunchEmittedCallIds: Set<String> = []
  private var outgoingCallIds: Set<String> = []
  private var connectedAtMsByCallId: [String: Int64] = [:]
  private var incomingExpiresAtMsByCallId: [String: Int64] = [:]
  private var timeoutItems: [String: DispatchWorkItem] = [:]
  private var postCallBehavior: PostCallBehavior = .stayOpen
  private var backgroundDispatcherHandle: Int64?
  private var backgroundAcceptCallbackHandle: Int64?
  private var backgroundDeclineCallbackHandle: Int64?
  private var notificationObservers: [NSObjectProtocol] = []

  init(
    eventBridge: EventStreamBridge,
    activeCallRegistry: ActiveCallRegistry,
    notificationCenter: NotificationCenter = .default,
    missedCallNotificationManager: MissedCallNotificationManager = MissedCallNotificationManager(),
    pendingStartupActionStore: PendingStartupActionStore = PendingStartupActionStore(),
    ongoingCallStore: OngoingCallStore = OngoingCallStore(),
    incomingCallStore: IncomingCallStore = IncomingCallStore(),
    backgroundValidatorRegistrationStore: BackgroundValidatorRegistrationStore =
      BackgroundValidatorRegistrationStore()
  ) {
    self.eventBridge = eventBridge
    self.activeCallRegistry = activeCallRegistry
    self.notificationCenter = notificationCenter
    self.missedCallNotificationManager = missedCallNotificationManager
    self.pendingStartupActionStore = pendingStartupActionStore
    self.ongoingCallStore = ongoingCallStore
    self.incomingCallStore = incomingCallStore
    self.backgroundValidatorRegistrationStore = backgroundValidatorRegistrationStore

    let config = CXProviderConfiguration(localizedName: "Callwave")
    config.supportsVideo = true
    config.maximumCallsPerCallGroup = 1
    config.maximumCallGroups = 1

    self.provider = CXProvider(configuration: config)
    delegate.onAccept = { [weak self] uuid in self?.handleAccept(uuid: uuid) }
    delegate.onEnd = { [weak self] uuid, reason in self?.handleEnd(uuid: uuid, reason: reason) }
    delegate.onDidReset = { [weak self] in self?.handleReset() }
    provider.setDelegate(delegate, queue: nil)
    self.missedCallNotificationManager.registerCategories()
    restoreBackgroundIncomingCallValidatorRegistration()
    restorePersistedOngoingCall()
    restorePersistedIncomingCall()
    registerApplicationObservers()
  }

  deinit {
    for observer in notificationObservers {
      notificationCenter.removeObserver(observer)
    }
  }

  func showIncomingCall(_ payload: CallPayload) {
    guard activeCallRegistry.tryStart(callId: payload.callId) else {
      emit(callId: payload.callId, type: "declined", extra: payload.extra)
      return
    }

    payloadStore[payload.callId] = payload
    pendingAcceptedCallIds.remove(payload.callId)
    confirmedAcceptedCallIds.remove(payload.callId)
    launchActionOverrides.removeValue(forKey: payload.callId)
    explicitIncomingLaunchEmittedCallIds.remove(payload.callId)
    explicitOngoingLaunchEmittedCallIds.remove(payload.callId)
    outgoingCallIds.remove(payload.callId)
    connectedAtMsByCallId.removeValue(forKey: payload.callId)
    let expiresAtMs = computeExpiresAtMs(timeoutSeconds: payload.timeoutSeconds)
    incomingExpiresAtMsByCallId[payload.callId] = expiresAtMs
    let uuid = uuidByCallId[payload.callId] ?? UUID()
    uuidByCallId[payload.callId] = uuid
    callIdByUuid[uuid] = payload.callId

    let update = CXCallUpdate()
    update.localizedCallerName = payload.callerName
    update.remoteHandle = CXHandle(type: .generic, value: payload.handle)
    update.hasVideo = payload.callType == "video"

    provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
      if let error {
        self?.activeCallRegistry.remove(callId: payload.callId)
        self?.payloadStore.removeValue(forKey: payload.callId)
        self?.uuidByCallId.removeValue(forKey: payload.callId)
        self?.callIdByUuid.removeValue(forKey: uuid)
        self?.incomingExpiresAtMsByCallId.removeValue(forKey: payload.callId)
        self?.incomingCallStore.clear(callId: payload.callId)
        guard let self else { return }
        self.emit(
          callId: payload.callId,
          type: "declined",
          extra: self.failureExtra(
            base: payload.extra,
            outcomeReason: Self.outcomeIncomingPresentationFailed,
            error: error
          )
        )
      } else {
        self?.incomingCallStore.save(payload: payload, uuid: uuid, expiresAtMs: expiresAtMs)
        self?.scheduleIncomingTimeout(payload: payload, uuid: uuid, expiresAtMs: expiresAtMs)
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
    launchActionOverrides.removeValue(forKey: payload.callId)
    explicitIncomingLaunchEmittedCallIds.remove(payload.callId)
    explicitOngoingLaunchEmittedCallIds.remove(payload.callId)
    outgoingCallIds.insert(payload.callId)
    connectedAtMsByCallId.removeValue(forKey: payload.callId)
    let uuid = UUID()
    uuidByCallId[payload.callId] = uuid
    callIdByUuid[uuid] = payload.callId

    let handle = CXHandle(type: .generic, value: payload.handle)
    let startAction = CXStartCallAction(call: uuid, handle: handle)
    startAction.isVideo = payload.callType == "video"

    let transaction = CXTransaction(action: startAction)
    callController.request(transaction) { [weak self] error in
      guard let self else { return }
      if let error {
        self.cleanup(callId: payload.callId, uuid: uuid)
        self.emit(
          callId: payload.callId,
          type: "ended",
          extra: self.failureExtra(
            base: payload.extra,
            outcomeReason: Self.outcomeCallkitStartFailed,
            error: error
          )
        )
        return
      }
      self.persistOngoingCall(
        payload: payload,
        eventType: "started",
        uuid: uuid
      )
      self.emit(callId: payload.callId, type: "started", extra: payload.extra)
    }
  }

  func endCall(callId: String) {
    guard let uuid = uuidByCallId[callId] else {
      clearCallState(callId: callId)
      emit(callId: callId, type: "ended", extra: nil)
      applyPostCallBehaviorIfNeeded()
      return
    }

    let endAction = CXEndCallAction(call: uuid)
    let transaction = CXTransaction(action: endAction)
    callController.request(transaction) { [weak self] error in
      guard let self else { return }
      if let error {
        self.emit(
          callId: callId,
          type: "ended",
          extra: self.failureExtra(
            base: self.payloadStore[callId]?.extra,
            outcomeReason: Self.outcomeCallkitEndFailed,
            error: error
          )
        )
        return
      }
      self.cleanup(callId: callId, uuid: uuid)
      self.emit(callId: callId, type: "ended", extra: nil)
      self.applyPostCallBehaviorIfNeeded()
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
    incomingExpiresAtMsByCallId.removeValue(forKey: callId)
    incomingCallStore.clear(callId: callId)
    launchActionOverrides.removeValue(forKey: callId)
    explicitIncomingLaunchEmittedCallIds.remove(callId)
    explicitOngoingLaunchEmittedCallIds.remove(callId)
    if let payload = payloadStore[callId] {
      persistOngoingCall(
        payload: payload,
        eventType: "accepted",
        uuid: uuidByCallId[callId]
      )
    }
    return true
  }

  func registerBackgroundIncomingCallValidator(
    backgroundDispatcherHandle: Int64,
    backgroundAcceptCallbackHandle: Int64?,
    backgroundDeclineCallbackHandle: Int64?
  ) {
    self.backgroundDispatcherHandle = backgroundDispatcherHandle
    self.backgroundAcceptCallbackHandle = backgroundAcceptCallbackHandle
    self.backgroundDeclineCallbackHandle = backgroundDeclineCallbackHandle
    backgroundValidatorRegistrationStore.save(
      backgroundDispatcherHandle: backgroundDispatcherHandle,
      backgroundAcceptCallbackHandle: backgroundAcceptCallbackHandle,
      backgroundDeclineCallbackHandle: backgroundDeclineCallbackHandle
    )
  }

  func clearBackgroundIncomingCallValidator() {
    backgroundDispatcherHandle = nil
    backgroundAcceptCallbackHandle = nil
    backgroundDeclineCallbackHandle = nil
    backgroundValidatorRegistrationStore.clear()
  }

  func syncCallConnectedState(callId: String, connectedAtMs: Int64) {
    guard activeCallRegistry.activeCallIds().contains(callId) else {
      return
    }
    connectedAtMsByCallId[callId] = connectedAtMs
    ongoingCallStore.updateConnectedAt(callId: callId, connectedAtMs: connectedAtMs)
  }

  func clearCallState(callId: String) {
    if let uuid = uuidByCallId[callId] {
      cleanup(callId: callId, uuid: uuid)
      return
    }
    activeCallRegistry.remove(callId: callId)
    payloadStore.removeValue(forKey: callId)
    incomingCallStore.clear(callId: callId)
    pendingAcceptedCallIds.remove(callId)
    confirmedAcceptedCallIds.remove(callId)
    launchActionOverrides.removeValue(forKey: callId)
    explicitIncomingLaunchEmittedCallIds.remove(callId)
    explicitOngoingLaunchEmittedCallIds.remove(callId)
    outgoingCallIds.remove(callId)
    connectedAtMsByCallId.removeValue(forKey: callId)
    incomingExpiresAtMsByCallId.removeValue(forKey: callId)
    ongoingCallStore.clear(callId: callId)
    missedCallNotificationManager.dismissMissedCall(callId: callId)
  }

  func declineCall(callId: String) -> Bool {
    guard let uuid = uuidByCallId[callId], payloadStore[callId] != nil else {
      return false
    }
    let payload = payloadStore[callId]
    if let payload, !reconcileIncomingTimeout(callId: callId, payload: payload, rescheduleIfPending: false) {
      return true
    }
    cancelTimeout(callId: callId)
    incomingExpiresAtMsByCallId.removeValue(forKey: callId)
    provider.reportCall(with: uuid, endedAt: Date(), reason: .declinedElsewhere)
    cleanup(callId: callId, uuid: uuid)
    emit(callId: callId, type: "declined", extra: payload?.extra)
    return true
  }

  func markMissed(callId: String, extra: [String: Any]? = nil) {
    let payload = payloadStore[callId]
    let missedExtra = eventExtra(payload: payload, fallbackExtra: extra)
    cancelTimeout(callId: callId)
    incomingExpiresAtMsByCallId.removeValue(forKey: callId)
    if let uuid = uuidByCallId[callId] {
      provider.reportCall(with: uuid, endedAt: Date(), reason: .unanswered)
      cleanup(callId: callId, uuid: uuid)
    } else {
      activeCallRegistry.remove(callId: callId)
      payloadStore.removeValue(forKey: callId)
      incomingCallStore.clear(callId: callId)
      pendingAcceptedCallIds.remove(callId)
      confirmedAcceptedCallIds.remove(callId)
      launchActionOverrides.removeValue(forKey: callId)
      explicitIncomingLaunchEmittedCallIds.remove(callId)
      explicitOngoingLaunchEmittedCallIds.remove(callId)
      outgoingCallIds.remove(callId)
      connectedAtMsByCallId.removeValue(forKey: callId)
      ongoingCallStore.clear(callId: callId)
    }
    let notificationPayload = (payload ?? fallbackPayload(callId: callId)).copy(extra: missedExtra)
    missedCallNotificationManager.showMissedCall(payload: notificationPayload)
    emit(
      callId: callId,
      type: "missed",
      extra: missedExtra
    )
  }

  func requestNotificationPermission(result: @escaping FlutterResult) {
    missedCallNotificationManager.requestPermission { granted in
      DispatchQueue.main.async {
        result(granted)
      }
    }
  }

  func takePendingStartupAction() -> [String: Any]? {
    pendingStartupActionStore.take()
  }

  func activeCallIds() -> [String] {
    activeCallRegistry.activeCallIds()
  }

  func activeCallEventSnapshots() -> [[String: Any]] {
    activeCallRegistry.activeCallIds().compactMap { callId in
      let payload = payloadStore[callId]
      if let payload, isIncomingRingingCall(callId: callId),
         !reconcileIncomingTimeout(callId: callId, payload: payload) {
        return nil
      }
      let type: String
      if pendingAcceptedCallIds.contains(callId) || confirmedAcceptedCallIds.contains(callId) {
        type = "accepted"
      } else if outgoingCallIds.contains(callId) {
        type = "started"
      } else {
        type = "incoming"
      }
      let extra: [String: Any]
      if type == "accepted" {
        extra = acceptedEventExtra(callId: callId, payload: payload)
      } else if type == "incoming" {
        extra = incomingEventExtra(
          callId: callId,
          payload: payload,
          consumeLaunchActionOverride: true
        )
      } else {
        extra = eventExtra(payload: payload, callId: callId)
      }
      return CallEventPayload.now(
        callId: callId,
        type: type,
        extra: extra
      ).toDictionary()
    }
  }

  func syncActiveCallsToEvents() {
    for callId in activeCallRegistry.activeCallIds() {
      let payload = payloadStore[callId]
      if let payload, isIncomingRingingCall(callId: callId),
         !reconcileIncomingTimeout(callId: callId, payload: payload) {
        continue
      }
      if pendingAcceptedCallIds.contains(callId) || confirmedAcceptedCallIds.contains(callId) {
        emit(callId: callId, type: "accepted", extra: acceptedEventExtra(callId: callId, payload: payload))
      } else if outgoingCallIds.contains(callId) {
        emit(callId: callId, type: "started", extra: eventExtra(payload: payload, callId: callId))
      } else {
        emit(
          callId: callId,
          type: "incoming",
          extra: incomingEventExtra(
            callId: callId,
            payload: payload,
            consumeLaunchActionOverride: true
          )
        )
      }
    }
  }

  func setPostCallBehavior(rawValue: String?) {
    postCallBehavior = PostCallBehavior(rawValue: rawValue ?? "stayOpen") ?? .stayOpen
  }

  func handleAccept(uuid: UUID) {
    guard let callId = callIdByUuid[uuid] else { return }
    let payload = payloadStore[callId]
    if let payload, !reconcileIncomingTimeout(callId: callId, payload: payload, rescheduleIfPending: false) {
      return
    }
    cancelTimeout(callId: callId)
    incomingExpiresAtMsByCallId.removeValue(forKey: callId)
    pendingAcceptedCallIds.insert(callId)
    confirmedAcceptedCallIds.remove(callId)
    incomingCallStore.clear(callId: callId)
    launchActionOverrides.removeValue(forKey: callId)
    explicitIncomingLaunchEmittedCallIds.remove(callId)
    explicitOngoingLaunchEmittedCallIds.remove(callId)
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
    let isTimeout = reason == .unanswered
    let wasIncomingDecline = !isTimeout && isIncomingRingingCall(callId: callId)
    cleanup(callId: callId, uuid: uuid)

    if wasIncomingDecline {
      guard let payload else {
        emit(callId: callId, type: "declined", extra: nil)
        return
      }
      if !maybeRunBackgroundDeclineReport(payload: payload) {
        emit(callId: callId, type: "declined", extra: payload.extra)
      }
      return
    }

    let type = isTimeout ? "timeout" : "ended"
    emit(callId: callId, type: type, extra: payload?.extra)
    if type == "timeout" {
      let missedExtra = eventExtra(payload: payload)
      if let payload {
        missedCallNotificationManager.showMissedCall(payload: payload.copy(extra: missedExtra))
      }
      emit(callId: callId, type: "missed", extra: missedExtra)
    }
  }

  func emitCallback(callId: String) {
    emit(callId: callId, type: "callback", extra: payloadStore[callId]?.extra)
  }

  func handleNotificationResponse(response: UNNotificationResponse) -> Bool {
    guard let payload = missedCallNotificationManager.payload(from: response) else {
      return false
    }
    missedCallNotificationManager.dismissMissedCall(callId: payload.callId)
    let isCallback =
      response.actionIdentifier == MissedCallNotificationManager.callbackActionIdentifier
    let type = isCallback ? "callback" : "missed"
    let launchAction = isCallback
      ? "com.callwave.flutter.methodchannel.ACTION_CALLBACK"
      : "com.callwave.flutter.methodchannel.ACTION_OPEN_MISSED_CALL"
    let startupActionType = isCallback ? "callback" : "openMissedCall"
    let mergedExtra = eventExtra(payload: payload, fallbackExtra: payload.extra)
    if eventBridge.hasListener {
      emit(
        callId: payload.callId,
        type: type,
        extra: appendLaunchAction(extra: mergedExtra, launchAction: launchAction)
      )
    } else {
      pendingStartupActionStore.save(
        type: startupActionType,
        payload: payload.copy(extra: mergedExtra)
      )
    }
    return true
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
    incomingCallStore.clear()
    pendingAcceptedCallIds.removeAll()
    confirmedAcceptedCallIds.removeAll()
    launchActionOverrides.removeAll()
    explicitIncomingLaunchEmittedCallIds.removeAll()
    explicitOngoingLaunchEmittedCallIds.removeAll()
    outgoingCallIds.removeAll()
    connectedAtMsByCallId.removeAll()
    incomingExpiresAtMsByCallId.removeAll()
    ongoingCallStore.clear()
  }

  private func restorePersistedOngoingCall() {
    guard let snapshot = ongoingCallStore.restore() else {
      return
    }
    let payload = snapshot.payload
    guard activeCallRegistry.tryStart(callId: payload.callId) else {
      ongoingCallStore.clear(callId: payload.callId)
      return
    }
    payloadStore[payload.callId] = payload
    pendingAcceptedCallIds.remove(payload.callId)
    confirmedAcceptedCallIds.remove(payload.callId)
    launchActionOverrides.removeValue(forKey: payload.callId)
    explicitIncomingLaunchEmittedCallIds.remove(payload.callId)
    explicitOngoingLaunchEmittedCallIds.remove(payload.callId)
    outgoingCallIds.remove(payload.callId)
    if let uuid = snapshot.uuid {
      uuidByCallId[payload.callId] = uuid
      callIdByUuid[uuid] = payload.callId
    }
    switch snapshot.eventType {
    case "accepted":
      confirmedAcceptedCallIds.insert(payload.callId)
    case "started":
      outgoingCallIds.insert(payload.callId)
    default:
      ongoingCallStore.clear(callId: payload.callId)
      activeCallRegistry.remove(callId: payload.callId)
      payloadStore.removeValue(forKey: payload.callId)
      return
    }
    if let connectedAtMs = snapshot.connectedAtMs {
      connectedAtMsByCallId[payload.callId] = connectedAtMs
    }
    incomingExpiresAtMsByCallId.removeValue(forKey: payload.callId)
    incomingCallStore.clear(callId: payload.callId)
  }

  /// Restores incoming call state from disk after app relaunch. Only restores if
  /// within the call's timeout window; expired entries are cleared.
  private func restorePersistedIncomingCall() {
    guard let snapshot = incomingCallStore.restore() else {
      return
    }
    let payload = snapshot.payload
    let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
    let expiresAtMs = snapshot.expiresAtMs
    if payloadStore[payload.callId] != nil {
      incomingExpiresAtMsByCallId[payload.callId] = expiresAtMs
      _ = reconcileIncomingTimeout(callId: payload.callId, payload: payload, fallbackExpiresAtMs: expiresAtMs)
      return
    }
    guard activeCallRegistry.tryStart(callId: payload.callId) else {
      incomingCallStore.clear(callId: payload.callId)
      return
    }
    payloadStore[payload.callId] = payload
    uuidByCallId[payload.callId] = snapshot.uuid
    callIdByUuid[snapshot.uuid] = payload.callId
    pendingAcceptedCallIds.remove(payload.callId)
    confirmedAcceptedCallIds.remove(payload.callId)
    launchActionOverrides.removeValue(forKey: payload.callId)
    explicitIncomingLaunchEmittedCallIds.remove(payload.callId)
    explicitOngoingLaunchEmittedCallIds.remove(payload.callId)
    outgoingCallIds.remove(payload.callId)
    connectedAtMsByCallId.removeValue(forKey: payload.callId)
    incomingExpiresAtMsByCallId[payload.callId] = expiresAtMs
    if nowMs >= expiresAtMs {
      finalizeIncomingTimeout(
        callId: payload.callId,
        payload: payload,
        uuid: snapshot.uuid
      )
      return
    }
    scheduleIncomingTimeout(
      payload: payload,
      uuid: snapshot.uuid,
      expiresAtMs: expiresAtMs
    )
  }

  private func persistOngoingCall(
    payload: CallPayload,
    eventType: String,
    uuid: UUID?
  ) {
    ongoingCallStore.save(
      payload: payload,
      eventType: eventType,
      connectedAtMs: connectedAtMsByCallId[payload.callId],
      uuid: uuid
    )
  }

  private func cleanup(callId: String, uuid: UUID) {
    cancelTimeout(callId: callId)
    missedCallNotificationManager.dismissMissedCall(callId: callId)
    activeCallRegistry.remove(callId: callId)
    payloadStore.removeValue(forKey: callId)
    uuidByCallId.removeValue(forKey: callId)
    callIdByUuid.removeValue(forKey: uuid)
    incomingCallStore.clear(callId: callId)
    pendingAcceptedCallIds.remove(callId)
    confirmedAcceptedCallIds.remove(callId)
    launchActionOverrides.removeValue(forKey: callId)
    explicitIncomingLaunchEmittedCallIds.remove(callId)
    explicitOngoingLaunchEmittedCallIds.remove(callId)
    outgoingCallIds.remove(callId)
    connectedAtMsByCallId.removeValue(forKey: callId)
    incomingExpiresAtMsByCallId.removeValue(forKey: callId)
    ongoingCallStore.clear(callId: callId)
  }

  private func emit(callId: String, type: String, extra: [String: Any]?) {
    eventBridge.emit(CallEventPayload.now(callId: callId, type: type, extra: extra))
  }

  private func failureExtra(
    base: [String: Any]?,
    outcomeReason: String,
    error: Error
  ) -> [String: Any] {
    var merged = base ?? [:]
    merged["outcomeReason"] = outcomeReason
    merged["nativeErrorDescription"] = error.localizedDescription
    return merged
  }

  private func scheduleIncomingTimeout(
    payload: CallPayload,
    uuid: UUID,
    expiresAtMs: Int64
  ) {
    cancelTimeout(callId: payload.callId)
    incomingExpiresAtMsByCallId[payload.callId] = expiresAtMs

    let workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      _ = self.reconcileIncomingTimeout(
        callId: payload.callId,
        payload: payload,
        fallbackExpiresAtMs: expiresAtMs
      )
    }

    timeoutItems[payload.callId] = workItem
    let delayMs = max(expiresAtMs - Int64(Date().timeIntervalSince1970 * 1000), 1)
    DispatchQueue.main.asyncAfter(
      deadline: .now() + .milliseconds(Int(delayMs)),
      execute: workItem
    )
  }

  private func cancelTimeout(callId: String) {
    timeoutItems[callId]?.cancel()
    timeoutItems.removeValue(forKey: callId)
  }

  private func computeExpiresAtMs(timeoutSeconds: Int) -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000) + (Int64(max(timeoutSeconds, 1)) * 1000)
  }

  private func currentIncomingExpiresAtMs(callId: String) -> Int64? {
    if let cached = incomingExpiresAtMsByCallId[callId] {
      return cached
    }
    guard let snapshot = incomingCallStore.restore(), snapshot.payload.callId == callId else {
      return nil
    }
    incomingExpiresAtMsByCallId[callId] = snapshot.expiresAtMs
    return snapshot.expiresAtMs
  }

  @discardableResult
  private func reconcileIncomingTimeout(
    callId: String,
    payload: CallPayload,
    fallbackExpiresAtMs: Int64? = nil,
    rescheduleIfPending: Bool = true
  ) -> Bool {
    if pendingAcceptedCallIds.contains(callId) || confirmedAcceptedCallIds.contains(callId) {
      return false
    }
    let expiresAtMs = currentIncomingExpiresAtMs(callId: callId) ??
      fallbackExpiresAtMs ??
      computeExpiresAtMs(timeoutSeconds: payload.timeoutSeconds)
    if currentIncomingExpiresAtMs(callId: callId) == nil || fallbackExpiresAtMs != nil {
      incomingExpiresAtMsByCallId[callId] = expiresAtMs
      if let uuid = uuidByCallId[callId] {
        incomingCallStore.save(payload: payload, uuid: uuid, expiresAtMs: expiresAtMs)
      }
    }
    let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
    guard nowMs < expiresAtMs else {
      finalizeIncomingTimeout(callId: callId, payload: payload, uuid: uuidByCallId[callId])
      return false
    }
    if rescheduleIfPending && isIncomingRingingCall(callId: callId), let uuid = uuidByCallId[callId] {
      scheduleIncomingTimeout(payload: payload, uuid: uuid, expiresAtMs: expiresAtMs)
    }
    return true
  }

  private func finalizeIncomingTimeout(
    callId: String,
    payload: CallPayload?,
    uuid: UUID?
  ) {
    if pendingAcceptedCallIds.contains(callId) || confirmedAcceptedCallIds.contains(callId) {
      return
    }
    let resolvedPayload = payloadStore[callId] ?? payload ?? fallbackPayload(callId: callId)
    payloadStore[callId] = resolvedPayload
    cancelTimeout(callId: callId)
    incomingExpiresAtMsByCallId.removeValue(forKey: callId)
    if let uuid {
      provider.reportCall(with: uuid, endedAt: Date(), reason: .unanswered)
      cleanup(callId: callId, uuid: uuid)
    } else {
      activeCallRegistry.remove(callId: callId)
      payloadStore.removeValue(forKey: callId)
      incomingCallStore.clear(callId: callId)
      pendingAcceptedCallIds.remove(callId)
      confirmedAcceptedCallIds.remove(callId)
      launchActionOverrides.removeValue(forKey: callId)
      explicitIncomingLaunchEmittedCallIds.remove(callId)
      explicitOngoingLaunchEmittedCallIds.remove(callId)
      outgoingCallIds.remove(callId)
      connectedAtMsByCallId.removeValue(forKey: callId)
      ongoingCallStore.clear(callId: callId)
    }
    emit(callId: callId, type: "timeout", extra: resolvedPayload.extra)
    let missedExtra = eventExtra(payload: resolvedPayload)
    missedCallNotificationManager.showMissedCall(payload: resolvedPayload.copy(extra: missedExtra))
    emit(callId: callId, type: "missed", extra: missedExtra)
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
    fallbackExtra: [String: Any]? = nil,
    callId: String? = nil
  ) -> [String: Any] {
    var merged = fallbackExtra ?? [:]
    if let payloadExtra = payload?.extra {
      merged.merge(payloadExtra) { _, new in new }
    }
    merged["callerName"] = payload?.callerName ?? (merged["callerName"] as? String ?? "Unknown")
    merged["handle"] = payload?.handle ?? (merged["handle"] as? String ?? "")
    merged["callType"] = payload?.callType ?? (merged["callType"] as? String ?? "audio")
    merged["avatarUrl"] = payload?.avatarUrl ?? merged["avatarUrl"] ?? NSNull()
    let resolvedCallId = callId ?? payload?.callId
    if let resolvedCallId, let connectedAtMs = connectedAtMsByCallId[resolvedCallId] {
      merged["connectedAtMs"] = connectedAtMs
    } else {
      merged.removeValue(forKey: "connectedAtMs")
    }

    return merged
  }

  private func fallbackPayload(callId: String) -> CallPayload {
    CallPayload(
      dictionary: [
        "callId": callId,
        "callerName": "Unknown",
        "handle": "",
        "timeoutSeconds": 30,
        "callType": "audio",
        "incomingAcceptStrategy": "openImmediately",
      ]
    )!
  }

  private func incomingEventExtra(
    callId: String,
    payload: CallPayload?,
    fallbackExtra: [String: Any]? = nil,
    consumeLaunchActionOverride: Bool = false
  ) -> [String: Any] {
    let merged = eventExtra(payload: payload, fallbackExtra: fallbackExtra)
    guard let launchAction = launchActionOverride(
      callId: callId,
      consume: consumeLaunchActionOverride
    ) else {
      return merged
    }
    return appendLaunchAction(extra: merged, launchAction: launchAction)
  }

  private func acceptedEventExtra(
    callId: String,
    payload: CallPayload?,
    fallbackExtra: [String: Any]? = nil
  ) -> [String: Any] {
    var merged = eventExtra(payload: payload, fallbackExtra: fallbackExtra, callId: callId)
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

  private func registerApplicationObservers() {
    notificationObservers.append(
      notificationCenter.addObserver(
        forName: UIApplication.didBecomeActiveNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.handleApplicationDidBecomeActive()
      }
    )
    if #available(iOS 13.0, *) {
      notificationObservers.append(
        notificationCenter.addObserver(
          forName: UIScene.didActivateNotification,
          object: nil,
          queue: .main
        ) { [weak self] _ in
          self?.handleApplicationDidBecomeActive()
        }
      )
    }
  }

  private func handleApplicationDidBecomeActive() {
    if let callId = activeOngoingCallIdForOpenLaunch() {
      guard !explicitOngoingLaunchEmittedCallIds.contains(callId) else {
        return
      }
      guard launchActionOverrides[callId] == nil else {
        return
      }
      explicitOngoingLaunchEmittedCallIds.insert(callId)
      launchActionOverrides[callId] = Self.launchActionOpenOngoing
      let type = confirmedAcceptedCallIds.contains(callId) ? "accepted" : "started"
      if type == "accepted" {
        emit(
          callId: callId,
          type: type,
          extra: acceptedEventExtra(callId: callId, payload: payloadStore[callId])
        )
      } else {
        emit(
          callId: callId,
          type: type,
          extra: eventExtra(payload: payloadStore[callId], callId: callId)
        )
      }
      return
    }
    guard let callId = activeIncomingCallIdForOpenLaunch() else {
      return
    }
    guard !explicitIncomingLaunchEmittedCallIds.contains(callId) else {
      return
    }
    guard launchActionOverrides[callId] == nil else {
      return
    }
    explicitIncomingLaunchEmittedCallIds.insert(callId)
    launchActionOverrides[callId] = Self.launchActionOpenIncoming
    emit(
      callId: callId,
      type: "incoming",
      extra: incomingEventExtra(callId: callId, payload: payloadStore[callId])
    )
  }

  private func activeIncomingCallIdForOpenLaunch() -> String? {
    activeCallRegistry.activeCallIds().first { callId in
      guard let payload = payloadStore[callId] else {
        return false
      }
      guard reconcileIncomingTimeout(callId: callId, payload: payload) else {
        return false
      }
      return !pendingAcceptedCallIds.contains(callId) &&
        !confirmedAcceptedCallIds.contains(callId) &&
        !outgoingCallIds.contains(callId)
    }
  }

  private func activeOngoingCallIdForOpenLaunch() -> String? {
    activeCallRegistry.activeCallIds().first { callId in
      payloadStore[callId] != nil &&
        (confirmedAcceptedCallIds.contains(callId) || outgoingCallIds.contains(callId))
    }
  }

  private func launchActionOverride(callId: String, consume: Bool) -> String? {
    let launchAction = launchActionOverrides[callId]
    if consume, launchAction != nil {
      launchActionOverrides.removeValue(forKey: callId)
    }
    return launchAction
  }

  private func appendLaunchAction(
    extra: [String: Any],
    launchAction: String
  ) -> [String: Any] {
    var merged = extra
    merged["launchAction"] = launchAction
    return merged
  }

  private func maybeRunBackgroundValidation(callId: String, payload: CallPayload) -> Bool {
    guard !eventBridge.hasListener else {
      return false
    }
    guard
      let backgroundDispatcherHandle = payload.backgroundDispatcherHandle ?? backgroundDispatcherHandle,
      let backgroundCallbackHandle =
        payload.backgroundCallbackHandle ?? backgroundAcceptCallbackHandle
    else {
      return false
    }
    backgroundValidator.validateAccept(
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

  private func maybeRunBackgroundDeclineReport(payload: CallPayload) -> Bool {
    guard !shouldDeferDeclineToLiveListener() else {
      return false
    }
    guard
      let backgroundDispatcherHandle = payload.backgroundDispatcherHandle ?? backgroundDispatcherHandle,
      let backgroundCallbackHandle =
        payload.backgroundDeclineCallbackHandle ?? backgroundDeclineCallbackHandle
    else {
      return false
    }
    backgroundValidator.reportDecline(
      backgroundDispatcherHandle: backgroundDispatcherHandle,
      backgroundCallbackHandle: backgroundCallbackHandle,
      payload: payload
    ) { [weak self] decision in
      guard let self else { return }
      guard !decision.isAllowed else { return }
      var extra = self.eventExtra(payload: payload, fallbackExtra: decision.extra)
      extra["outcomeReason"] = decision.reason ?? "failed"
      self.markMissed(callId: payload.callId, extra: extra)
    }
    return true
  }

  private func restoreBackgroundIncomingCallValidatorRegistration() {
    guard let registration = backgroundValidatorRegistrationStore.load() else {
      return
    }
    backgroundDispatcherHandle = registration.backgroundDispatcherHandle
    backgroundAcceptCallbackHandle = registration.backgroundAcceptCallbackHandle
    backgroundDeclineCallbackHandle = registration.backgroundDeclineCallbackHandle
  }

  private func shouldDeferDeclineToLiveListener() -> Bool {
    guard eventBridge.hasListener else {
      return false
    }
    return UIApplication.shared.applicationState == .active
  }

  private func isIncomingRingingCall(callId: String) -> Bool {
    payloadStore[callId] != nil &&
      !pendingAcceptedCallIds.contains(callId) &&
      !confirmedAcceptedCallIds.contains(callId) &&
      !outgoingCallIds.contains(callId)
  }

  private static let launchActionOpenIncoming =
    "com.callwave.flutter.methodchannel.ACTION_OPEN_INCOMING"
  private static let launchActionOpenOngoing =
    "com.callwave.flutter.methodchannel.ACTION_OPEN_ONGOING"
}

private enum PostCallBehavior: String {
  case stayOpen
  case backgroundOnEnded
}
