import Foundation
import CallKit
import Flutter
import UIKit
import UserNotifications

final class IOSCallManager {
  private let eventBridge: EventStreamBridge
  private let activeCallRegistry: ActiveCallRegistry
  private let provider: CXProvider
  private let notificationCenter: NotificationCenter
  private let missedCallNotificationManager: MissedCallNotificationManager
  private let pendingStartupActionStore: PendingStartupActionStore
  private let ongoingCallStore: OngoingCallStore
  private let callController = CXCallController()
  private let delegate = CallKitProviderDelegate()
  private let backgroundValidator = IOSBackgroundValidator()

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
  private var timeoutItems: [String: DispatchWorkItem] = [:]
  private var postCallBehavior: PostCallBehavior = .stayOpen
  private var backgroundDispatcherHandle: Int64?
  private var backgroundCallbackHandle: Int64?
  private var notificationObservers: [NSObjectProtocol] = []

  init(
    eventBridge: EventStreamBridge,
    activeCallRegistry: ActiveCallRegistry,
    notificationCenter: NotificationCenter = .default,
    missedCallNotificationManager: MissedCallNotificationManager = MissedCallNotificationManager(),
    pendingStartupActionStore: PendingStartupActionStore = PendingStartupActionStore(),
    ongoingCallStore: OngoingCallStore = OngoingCallStore()
  ) {
    self.eventBridge = eventBridge
    self.activeCallRegistry = activeCallRegistry
    self.notificationCenter = notificationCenter
    self.missedCallNotificationManager = missedCallNotificationManager
    self.pendingStartupActionStore = pendingStartupActionStore
    self.ongoingCallStore = ongoingCallStore

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
    restorePersistedOngoingCall()
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
    callController.request(transaction) { [weak self] _ in
      self?.persistOngoingCall(
        payload: payload,
        eventType: "started",
        uuid: uuid
      )
      self?.emit(callId: payload.callId, type: "started", extra: payload.extra)
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
    backgroundCallbackHandle: Int64
  ) {
    self.backgroundDispatcherHandle = backgroundDispatcherHandle
    self.backgroundCallbackHandle = backgroundCallbackHandle
  }

  func clearBackgroundIncomingCallValidator() {
    backgroundDispatcherHandle = nil
    backgroundCallbackHandle = nil
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
    pendingAcceptedCallIds.remove(callId)
    confirmedAcceptedCallIds.remove(callId)
    launchActionOverrides.removeValue(forKey: callId)
    explicitIncomingLaunchEmittedCallIds.remove(callId)
    explicitOngoingLaunchEmittedCallIds.remove(callId)
    outgoingCallIds.remove(callId)
    connectedAtMsByCallId.removeValue(forKey: callId)
    ongoingCallStore.clear(callId: callId)
    missedCallNotificationManager.dismissMissedCall(callId: callId)
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
    let missedExtra = eventExtra(payload: payload, fallbackExtra: extra)
    cancelTimeout(callId: callId)
    if let uuid = uuidByCallId[callId] {
      provider.reportCall(with: uuid, endedAt: Date(), reason: .unanswered)
      cleanup(callId: callId, uuid: uuid)
    } else {
      activeCallRegistry.remove(callId: callId)
      payloadStore.removeValue(forKey: callId)
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
    cancelTimeout(callId: callId)
    pendingAcceptedCallIds.insert(callId)
    confirmedAcceptedCallIds.remove(callId)
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
    cleanup(callId: callId, uuid: uuid)

    let type = reason == .unanswered ? "timeout" : "ended"
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
    pendingAcceptedCallIds.removeAll()
    confirmedAcceptedCallIds.removeAll()
    launchActionOverrides.removeAll()
    explicitIncomingLaunchEmittedCallIds.removeAll()
    explicitOngoingLaunchEmittedCallIds.removeAll()
    outgoingCallIds.removeAll()
    connectedAtMsByCallId.removeAll()
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
    pendingAcceptedCallIds.remove(callId)
    confirmedAcceptedCallIds.remove(callId)
    launchActionOverrides.removeValue(forKey: callId)
    explicitIncomingLaunchEmittedCallIds.remove(callId)
    explicitOngoingLaunchEmittedCallIds.remove(callId)
    outgoingCallIds.remove(callId)
    connectedAtMsByCallId.removeValue(forKey: callId)
    ongoingCallStore.clear(callId: callId)
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
      let missedExtra = self.eventExtra(payload: payload)
      self.missedCallNotificationManager.showMissedCall(payload: payload.copy(extra: missedExtra))
      self.emit(callId: payload.callId, type: "missed", extra: missedExtra)
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
      payloadStore[callId] != nil &&
        !pendingAcceptedCallIds.contains(callId) &&
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

  private static let launchActionOpenIncoming =
    "com.callwave.flutter.methodchannel.ACTION_OPEN_INCOMING"
  private static let launchActionOpenOngoing =
    "com.callwave.flutter.methodchannel.ACTION_OPEN_ONGOING"
}

private enum PostCallBehavior: String {
  case stayOpen
  case backgroundOnEnded
}
