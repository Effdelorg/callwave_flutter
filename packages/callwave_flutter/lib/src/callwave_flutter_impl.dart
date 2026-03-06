import 'dart:async';
import 'dart:ui' as ui;

import 'package:callwave_flutter_platform_interface/callwave_flutter_platform_interface.dart'
    as platform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'config/callwave_configuration.dart';
import 'engine/call_session.dart';
import 'engine/callwave_engine.dart';
import 'enums/call_event_type.dart';
import 'enums/call_session_state.dart';
import 'enums/call_type.dart';
import 'enums/post_call_behavior.dart';
import 'models/call_accept_decision.dart';
import 'models/background_incoming_call_validation_request.dart';
import 'models/call_data.dart';
import 'models/call_event.dart';
import 'models/call_event_extra_keys.dart';
import 'models/call_startup_route_decision.dart';

class CallwaveFlutter {
  CallwaveFlutter._();

  static final CallwaveFlutter instance = CallwaveFlutter._();
  static const Duration _sessionCleanupDelay = Duration(seconds: 3);

  platform.CallwaveFlutterPlatform get _platform =>
      platform.CallwaveFlutterPlatform.instance;
  final Map<String, CallSession> _sessions = <String, CallSession>{};
  final Map<String, void Function()> _sessionListeners =
      <String, void Function()>{};
  final Map<String, Timer> _sessionCleanupTimers = <String, Timer>{};
  final Map<String, int> _acceptFlowVersions = <String, int>{};
  final Set<String> _acceptValidationsInFlight = <String>{};
  final Set<String> _announcedRoutableSessions = <String>{};
  final StreamController<CallSession> _sessionController =
      StreamController<CallSession>.broadcast();

  StreamSubscription<CallEvent>? _engineEventSubscription;
  CallwaveEngine? _engine;
  IncomingCallHandling _incomingCallHandling =
      const IncomingCallHandling.realtime();
  BackgroundIncomingCallValidator? _backgroundIncomingCallValidator;

  Stream<CallEvent> get events {
    return _platform.events.map((dto) {
      return CallEvent(
        callId: dto.callId,
        type: _eventTypeFromDto(dto.type),
        timestamp: DateTime.fromMillisecondsSinceEpoch(dto.timestampMs),
        extra: dto.extra,
      );
    });
  }

  /// Applies a new engine/configuration pair and resets any in-memory session
  /// state tracked by the singleton.
  ///
  /// Reconfiguring during an active call intentionally disposes existing
  /// sessions so apps should treat this as startup/setup, not an in-call mode
  /// toggle.
  void configure(CallwaveConfiguration configuration) {
    _disposeAllSessions();
    _acceptFlowVersions.clear();
    _acceptValidationsInFlight.clear();
    _announcedRoutableSessions.clear();
    _engine = configuration.engine;
    _incomingCallHandling = configuration.incomingCallHandling;
    _backgroundIncomingCallValidator =
        configuration.backgroundIncomingCallValidator;
    final previousSubscription = _engineEventSubscription;
    _engineEventSubscription = null;
    unawaited(previousSubscription?.cancel());
    _engineEventSubscription = events.listen(
      _onEngineEvent,
      onError: _onEngineEventStreamError,
    );
    unawaited(
      _syncBackgroundIncomingCallValidatorRegistration().catchError(
        (Object error, StackTrace stackTrace) {
          Zone.current.handleUncaughtError(error, stackTrace);
        },
      ),
    );
  }

  void setEngine(CallwaveEngine engine) {
    configure(CallwaveConfiguration(engine: engine));
  }

  bool get hasEngine => _engine != null;

  Stream<CallSession> get sessions => _sessionController.stream;

  CallSession? getSession(String callId) => _sessions[callId];

  /// Snapshot of non-terminal sessions currently tracked in memory.
  ///
  /// Useful for startup hydration when listeners attach after sessions were
  /// created (for example, cold-start restore before widget tree mount).
  List<CallSession> get activeSessions {
    return _sessions.values.where((session) => !session.isEnded).toList(
          growable: false,
        );
  }

  CallSession createSession({
    required CallData callData,
    required bool isOutgoing,
    CallSessionState initialState = CallSessionState.idle,
  }) {
    _requireEngineConfigured();
    final existing = _sessions[callData.callId];
    if (existing != null) {
      existing.updateCallData(callData);
      _reconcileSessionState(existing, initialState);
      return existing;
    }

    final session = CallSession(
      callData: callData,
      isOutgoing: isOutgoing,
      initialState: initialState,
      engineProvider: () => _engine,
      acceptNative: acceptCall,
      declineNative: declineCall,
      endNative: endCall,
      startOutgoingNative: showOutgoingCall,
    );

    _sessions[callData.callId] = session;
    void listener() => _onSessionChanged(callData.callId);
    _sessionListeners[callData.callId] = listener;
    session.addListener(listener);
    if (_isRoutableSessionState(initialState)) {
      _announcedRoutableSessions.add(callData.callId);
    }
    _sessionController.add(session);
    return session;
  }

  /// Restores active sessions from native state (syncs events, creates sessions).
  ///
  /// Prefer [prepareStartupRouteDecision] in `main()` before `runApp()` — it
  /// calls this and returns a route decision. If you call this directly, pass
  /// [CallwaveScope.preRoutedCallIds] for any call you route yourself to avoid
  /// double navigation (startup route + auto-push).
  Future<void> restoreActiveSessions() async {
    _requireEngineConfigured();
    final snapshots = await _platform.getActiveCallEventSnapshots();
    if (snapshots.isNotEmpty) {
      final orderedSnapshots = snapshots.toList(growable: false)
        ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
      for (final snapshot in orderedSnapshots) {
        await _applySnapshotEvent(snapshot);
      }
    } else {
      // Fallback for platform implementations that only support event replay.
      await _platform.syncActiveCallsToEvents();
      await Future<void>.delayed(Duration.zero);
    }

    final activeCallIds = await getActiveCallIds();
    for (final callId in activeCallIds) {
      final existing = _sessions[callId];
      if (existing != null) {
        if (existing.state == CallSessionState.idle) {
          _reconcileSessionState(existing, CallSessionState.connecting);
        }
        continue;
      }
      createSession(
        callData: _fallbackCallData(callId),
        isOutgoing: false,
        initialState: CallSessionState.connecting,
      );
    }
  }

  Future<void> _applySnapshotEvent(platform.CallEventDto snapshot) async {
    final event = CallEvent(
      callId: snapshot.callId,
      type: _eventTypeFromDto(snapshot.type),
      timestamp: DateTime.fromMillisecondsSinceEpoch(snapshot.timestampMs),
      extra: snapshot.extra,
    );

    switch (event.type) {
      case CallEventType.incoming:
        final session = _ensureSessionFromEvent(
          event: event,
          isOutgoing: false,
          initialState: CallSessionState.ringing,
        );
        await session.applyNativeEvent(event);
        return;
      case CallEventType.accepted:
        final session = _ensureSessionFromEvent(
          event: event,
          isOutgoing: false,
          initialState: _acceptedInitialState(event.extra),
        );
        await _handleAcceptedEvent(session, event);
        return;
      case CallEventType.started:
        final session = _ensureSessionFromEvent(
          event: event,
          isOutgoing: true,
          initialState: CallSessionState.connecting,
        );
        await session.applyNativeEvent(event);
        return;
      case CallEventType.declined:
      case CallEventType.ended:
      case CallEventType.timeout:
      case CallEventType.missed:
      case CallEventType.callback:
        return;
    }
  }

  /// Restores active sessions and returns startup route recommendation.
  ///
  /// Intended for `main()` before `runApp()` to decide initial route.
  Future<CallStartupRouteDecision> prepareStartupRouteDecision() async {
    await restoreActiveSessions();
    final startupSession = _selectStartupRouteSession(activeSessions);
    if (startupSession == null ||
        !_shouldOpenStartupCall(startupSession.state)) {
      return const CallStartupRouteDecision.home();
    }
    return CallStartupRouteDecision.call(
      callId: startupSession.callId,
      sessionState: startupSession.state,
    );
  }

  Future<void> showIncomingCall(CallData data) {
    return _platform.showIncomingCall(
      _toDtoWithStrategy(
        data,
        incomingAcceptStrategy:
            _incomingCallHandling is RealtimeIncomingCallHandling
                ? platform.IncomingAcceptStrategy.openImmediately
                : platform.IncomingAcceptStrategy.deferOpenUntilConfirmed,
      ),
    );
  }

  Future<void> showOutgoingCall(CallData data) {
    return _platform.showOutgoingCall(_toDto(data));
  }

  /// Accepts an active incoming call.
  ///
  /// The returned future fails if [callId] does not map to an active incoming
  /// call on the current platform runtime.
  Future<void> acceptCall(String callId) {
    return _platform.acceptCall(callId);
  }

  /// Marks an accepted call as confirmed so native UI can proceed.
  ///
  /// Call after validation allows the call. Fails if [callId] is unknown.
  Future<void> confirmAcceptedCall(String callId) {
    return _platform.confirmAcceptedCall(callId);
  }

  /// Declines an active incoming call.
  ///
  /// The returned future fails if [callId] does not map to an active incoming
  /// call on the current platform runtime.
  Future<void> declineCall(String callId) {
    return _platform.declineCall(callId);
  }

  Future<void> endCall(String callId) {
    _invalidateAcceptFlow(callId);
    return _platform.endCall(callId);
  }

  /// Marks a call as missed. [extra] can include [CallEventExtraKeys.outcomeReason].
  Future<void> markMissed(String callId, {Map<String, dynamic>? extra}) {
    _invalidateAcceptFlow(callId);
    return _platform.markMissed(callId, extra: extra);
  }

  Future<List<String>> getActiveCallIds() {
    return _platform.getActiveCallIds();
  }

  Future<bool> requestNotificationPermission() {
    return _platform.requestNotificationPermission();
  }

  Future<void> requestFullScreenIntentPermission() {
    return _platform.requestFullScreenIntentPermission();
  }

  /// Configures post-call behavior when the user ends a call via [endCall].
  ///
  /// Does not apply to timeout, decline, or [markMissed]. On Android,
  /// [PostCallBehavior.backgroundOnEnded] moves the app to background.
  /// On iOS, the setting is accepted but has no effect.
  Future<void> setPostCallBehavior(PostCallBehavior behavior) {
    return _platform.setPostCallBehavior(
      _dtoPostCallBehaviorFromPublic(behavior),
    );
  }

  void _onEngineEvent(CallEvent event) {
    switch (event.type) {
      case CallEventType.incoming:
        final session = _ensureSessionFromEvent(
          event: event,
          isOutgoing: false,
          initialState: CallSessionState.ringing,
        );
        unawaited(session.applyNativeEvent(event));
        return;
      case CallEventType.accepted:
        final session = _ensureSessionFromEvent(
          event: event,
          isOutgoing: false,
          initialState: _acceptedInitialState(event.extra),
        );
        unawaited(
          _handleAcceptedEvent(
            session,
            event,
            shouldAnnounceWhenReady: _isOpenOngoingLaunchAction(event.extra),
          ),
        );
        return;
      case CallEventType.started:
        final session = _ensureSessionFromEvent(
          event: event,
          isOutgoing: true,
          initialState: CallSessionState.connecting,
        );
        unawaited(session.applyNativeEvent(event));
        if (_isOpenOngoingLaunchAction(event.extra)) {
          _sessionController.add(session);
        }
        return;
      case CallEventType.declined:
      case CallEventType.ended:
      case CallEventType.timeout:
      case CallEventType.missed:
        _invalidateAcceptFlow(event.callId);
        final session = _sessions[event.callId];
        if (session != null) {
          unawaited(session.applyNativeEvent(event));
        }
        return;
      case CallEventType.callback:
        return;
    }
  }

  Future<void> _handleAcceptedEvent(
    CallSession session,
    CallEvent event, {
    bool shouldAnnounceWhenReady = false,
  }) async {
    final isConfirmed = _isConfirmedAcceptance(event.extra);
    if (isConfirmed) {
      _invalidateAcceptFlow(session.callId);
      await _beginConfirmedAcceptedSession(
        session,
        shouldAnnounceWhenReady: shouldAnnounceWhenReady,
      );
      return;
    }

    final handling = _incomingCallHandling;
    if (handling is RealtimeIncomingCallHandling) {
      _invalidateAcceptFlow(session.callId);
      await _beginConfirmedAcceptedSession(
        session,
        shouldAnnounceWhenReady: shouldAnnounceWhenReady,
        needsNativeConfirmation: true,
      );
      return;
    }

    if (_acceptValidationsInFlight.contains(session.callId)) {
      return;
    }

    final validator = (handling as ValidatedIncomingCallHandling).validator;
    final flowVersion = _nextAcceptFlowVersion(session.callId);
    _acceptValidationsInFlight.add(session.callId);
    session.reportValidating();

    try {
      final decision = await validator(session);
      _acceptValidationsInFlight.remove(session.callId);
      if (!_isCurrentAcceptFlow(session.callId, flowVersion) ||
          session.isEnded) {
        return;
      }

      if (decision.extra != null && decision.extra!.isNotEmpty) {
        session.updateCallData(
          session.callData.copyWith(
            extra: _mergeExtraMaps(session.callData.extra, decision.extra),
          ),
        );
      }

      if (decision.isAllowed) {
        await _beginConfirmedAcceptedSession(
          session,
          shouldAnnounceWhenReady: shouldAnnounceWhenReady,
          needsNativeConfirmation: true,
        );
        return;
      }

      await _markMissedSafely(
        session,
        extra: _validationRejectExtra(
          session: session,
          decision: decision,
        ),
      );
    } catch (error, stackTrace) {
      _acceptValidationsInFlight.remove(session.callId);
      if (!_isCurrentAcceptFlow(session.callId, flowVersion) ||
          session.isEnded) {
        return;
      }
      Zone.current.handleUncaughtError(error, stackTrace);
      await _markMissedSafely(
        session,
        extra: _validationRejectExtra(
          session: session,
          decision: const CallAcceptDecision.reject(
            reason: CallAcceptRejectReason.failed,
          ),
        ),
      );
    }
  }

  Future<void> _beginConfirmedAcceptedSession(
    CallSession session, {
    required bool shouldAnnounceWhenReady,
    bool needsNativeConfirmation = false,
  }) async {
    if (needsNativeConfirmation) {
      try {
        await confirmAcceptedCall(session.callId);
      } catch (error, stackTrace) {
        Zone.current.handleUncaughtError(error, stackTrace);
        if (!session.isEnded) {
          await _markMissedSafely(
            session,
            extra: _validationRejectExtra(
              session: session,
              decision: const CallAcceptDecision.reject(
                reason: CallAcceptRejectReason.unavailable,
              ),
            ),
          );
        }
        return;
      }
    }

    if (session.isEnded) {
      return;
    }
    final wasValidating = session.state == CallSessionState.validating;
    final beginAnsweringFuture = session.beginAnswering();
    if (shouldAnnounceWhenReady || wasValidating) {
      _announcedRoutableSessions.add(session.callId);
      _sessionController.add(session);
    }
    unawaited(beginAnsweringFuture);
  }

  void _onEngineEventStreamError(Object error, StackTrace stackTrace) {
    Zone.current.handleUncaughtError(error, stackTrace);
  }

  Future<void> _markMissedSafely(
    CallSession session, {
    Map<String, dynamic>? extra,
  }) async {
    try {
      await markMissed(session.callId, extra: extra);
    } catch (error, stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
      if (!session.isEnded) {
        session.reportEnded();
      }
    }
  }

  void _onSessionChanged(String callId) {
    final session = _sessions[callId];
    if (session == null) {
      return;
    }
    if (session.isEnded) {
      _invalidateAcceptFlow(callId);
      _announcedRoutableSessions.remove(callId);
      // Terminal states are absorbing; schedule cleanup once.
      if (_sessionCleanupTimers.containsKey(callId)) {
        return;
      }
      _sessionCleanupTimers[callId] = Timer(
        _sessionCleanupDelay,
        () => _disposeSession(callId),
      );
      return;
    }
    if (_isRoutableSessionState(session.state)) {
      if (_announcedRoutableSessions.add(callId)) {
        _sessionController.add(session);
      }
    } else {
      _announcedRoutableSessions.remove(callId);
    }
    _sessionCleanupTimers.remove(callId)?.cancel();
  }

  void _disposeSession(String callId) {
    _sessionCleanupTimers.remove(callId)?.cancel();
    _invalidateAcceptFlow(callId);
    _announcedRoutableSessions.remove(callId);
    final session = _sessions.remove(callId);
    final listener = _sessionListeners.remove(callId);
    if (session == null || listener == null) {
      return;
    }
    session
      ..removeListener(listener)
      ..dispose();
  }

  void _disposeAllSessions() {
    for (final timer in _sessionCleanupTimers.values) {
      timer.cancel();
    }
    _sessionCleanupTimers.clear();
    _acceptFlowVersions.clear();
    _acceptValidationsInFlight.clear();
    _announcedRoutableSessions.clear();

    final sessions = _sessions.values.toList(growable: false);
    for (final session in sessions) {
      final callId = session.callId;
      final listener = _sessionListeners.remove(callId);
      if (listener != null) {
        session.removeListener(listener);
      }
      session.dispose();
    }
    _sessions.clear();
  }

  CallSession _ensureSessionFromEvent({
    required CallEvent event,
    required bool isOutgoing,
    required CallSessionState initialState,
  }) {
    final existing = _sessions[event.callId];
    final callData = _callDataFromEvent(event, fallback: existing?.callData);
    if (existing != null) {
      existing.updateCallData(callData);
      _reconcileSessionState(existing, initialState);
      return existing;
    }
    return createSession(
      callData: callData,
      isOutgoing: isOutgoing,
      initialState: initialState,
    );
  }

  void _reconcileSessionState(CallSession session, CallSessionState target) {
    if (session.isEnded) {
      return;
    }
    switch (target) {
      case CallSessionState.idle:
        return;
      case CallSessionState.ringing:
        if (session.state == CallSessionState.idle) {
          session.reportRinging();
        }
        return;
      case CallSessionState.validating:
        if (session.state == CallSessionState.idle ||
            session.state == CallSessionState.ringing) {
          session.reportValidating();
        }
        return;
      case CallSessionState.connecting:
        if (session.state == CallSessionState.idle ||
            session.state == CallSessionState.ringing ||
            session.state == CallSessionState.validating) {
          session.reportConnecting();
        }
        return;
      case CallSessionState.connected:
        session.reportConnected();
        return;
      case CallSessionState.reconnecting:
        if (session.state == CallSessionState.connected ||
            session.state == CallSessionState.connecting) {
          session.reportReconnecting();
        }
        return;
      case CallSessionState.ended:
        session.reportEnded();
        return;
      case CallSessionState.failed:
        session.reportFailed();
        return;
    }
  }

  CallSession? _selectStartupRouteSession(List<CallSession> sessions) {
    CallSession? selected;
    var selectedPriority = -1;
    for (final session in sessions) {
      final priority = _startupRoutePriority(session.state);
      if (priority > selectedPriority) {
        selected = session;
        selectedPriority = priority;
      }
    }
    return selected;
  }

  int _startupRoutePriority(CallSessionState state) {
    switch (state) {
      case CallSessionState.connected:
        return 4;
      case CallSessionState.reconnecting:
        return 3;
      case CallSessionState.connecting:
        return 2;
      case CallSessionState.validating:
      case CallSessionState.ringing:
      case CallSessionState.idle:
      case CallSessionState.ended:
      case CallSessionState.failed:
        return 1;
    }
  }

  bool _shouldOpenStartupCall(CallSessionState state) {
    return state == CallSessionState.connecting ||
        state == CallSessionState.connected ||
        state == CallSessionState.reconnecting;
  }

  bool _isRoutableSessionState(CallSessionState state) {
    return state != CallSessionState.validating &&
        state != CallSessionState.ended &&
        state != CallSessionState.failed;
  }

  CallSessionState _acceptedInitialState(Map<String, dynamic>? extra) {
    if (_isConfirmedAcceptance(extra) ||
        _incomingCallHandling is RealtimeIncomingCallHandling) {
      return CallSessionState.connecting;
    }
    return CallSessionState.validating;
  }

  bool _isConfirmedAcceptance(Map<String, dynamic>? extra) {
    return extra?[CallEventExtraKeys.acceptanceState] ==
        CallEventExtraKeys.acceptanceStateConfirmed;
  }

  int _nextAcceptFlowVersion(String callId) {
    final nextVersion = (_acceptFlowVersions[callId] ?? 0) + 1;
    _acceptFlowVersions[callId] = nextVersion;
    return nextVersion;
  }

  void _invalidateAcceptFlow(String callId) {
    _acceptFlowVersions[callId] = (_acceptFlowVersions[callId] ?? 0) + 1;
    _acceptValidationsInFlight.remove(callId);
  }

  bool _isCurrentAcceptFlow(String callId, int version) {
    return _acceptFlowVersions[callId] == version;
  }

  Map<String, dynamic> _validationRejectExtra({
    required CallSession session,
    required CallAcceptDecision decision,
  }) {
    return _mergeExtraMaps(
      session.callData.extra,
      <String, dynamic>{
        CallEventExtraKeys.outcomeReason:
            (decision.reason ?? CallAcceptRejectReason.unknown).name,
        if (decision.extra != null) ...decision.extra!,
      },
    );
  }

  Map<String, dynamic> _mergeExtraMaps(
    Map<String, dynamic>? base,
    Map<String, dynamic>? extra,
  ) {
    final merged = <String, dynamic>{};
    if (base != null) {
      merged.addAll(base);
    }
    if (extra != null) {
      merged.addAll(extra);
    }
    return merged;
  }

  CallData _callDataFromEvent(
    CallEvent event, {
    required CallData? fallback,
  }) {
    final fallbackData = fallback ?? _fallbackCallData(event.callId);
    final callerName = _readNonEmptyString(event.extra, 'callerName') ??
        fallbackData.callerName;
    final handle =
        _readNonEmptyString(event.extra, 'handle') ?? fallbackData.handle;
    final avatarUrl =
        _readString(event.extra, 'avatarUrl') ?? fallbackData.avatarUrl;
    final callType =
        _readCallType(event.extra?['callType']) ?? fallbackData.callType;

    return CallData(
      callId: event.callId,
      callerName: callerName,
      handle: handle,
      avatarUrl: avatarUrl,
      timeout: fallbackData.timeout,
      callType: callType,
      extra: event.extra ?? fallbackData.extra,
    );
  }

  CallData _fallbackCallData(String callId) {
    return CallData(
      callId: callId,
      callerName: 'Unknown',
      handle: '',
      callType: CallType.audio,
      extra: const <String, dynamic>{},
    );
  }

  void _requireEngineConfigured() {
    if (_engine != null) {
      return;
    }
    throw StateError(
      'CallwaveEngine is not set. Call setEngine(...) or configure(...) before session operations.',
    );
  }

  String? _readNonEmptyString(Map<String, dynamic>? map, String key) {
    final value = map?[key];
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _readString(Map<String, dynamic>? map, String key) {
    final value = map?[key];
    return value is String ? value : null;
  }

  CallType? _readCallType(Object? raw) {
    if (raw is! String) {
      return null;
    }
    for (final callType in CallType.values) {
      if (callType.name == raw) {
        return callType;
      }
    }
    return null;
  }

  /// True when [extra] contains [CallEventExtraKeys.launchAction] set to
  /// [CallEventExtraKeys.launchActionOpenOngoing] (user tapped ongoing notification).
  bool _isOpenOngoingLaunchAction(Map<String, dynamic>? extra) {
    return extra?[CallEventExtraKeys.launchAction] ==
        CallEventExtraKeys.launchActionOpenOngoing;
  }

  platform.CallDataDto _toDto(CallData data) {
    return _toDtoWithStrategy(
      data,
      incomingAcceptStrategy: platform.IncomingAcceptStrategy.openImmediately,
    );
  }

  platform.CallDataDto _toDtoWithStrategy(
    CallData data, {
    required platform.IncomingAcceptStrategy incomingAcceptStrategy,
  }) {
    final backgroundValidatorHandles =
        _backgroundIncomingCallValidatorHandlesOrNull();
    return platform.CallDataDto(
      callId: data.callId,
      callerName: data.callerName,
      handle: data.handle,
      avatarUrl: data.avatarUrl,
      timeoutSeconds: data.timeout.inSeconds,
      callType: _dtoCallTypeFromPublic(data.callType),
      extra: data.extra,
      incomingAcceptStrategy: incomingAcceptStrategy,
      backgroundDispatcherHandle:
          backgroundValidatorHandles?.backgroundDispatcherHandle,
      backgroundCallbackHandle:
          backgroundValidatorHandles?.backgroundCallbackHandle,
    );
  }

  Future<void> _syncBackgroundIncomingCallValidatorRegistration() async {
    final handles = _backgroundIncomingCallValidatorHandlesOrNull();
    if (handles == null) {
      await _platform.clearBackgroundIncomingCallValidator();
      return;
    }

    await _platform.registerBackgroundIncomingCallValidator(
      backgroundDispatcherHandle: handles.backgroundDispatcherHandle,
      backgroundCallbackHandle: handles.backgroundCallbackHandle,
    );
  }

  _BackgroundIncomingCallValidatorHandles?
      _backgroundIncomingCallValidatorHandlesOrNull() {
    final validator = _backgroundIncomingCallValidator;
    if (validator == null) {
      return null;
    }

    final dispatcherHandle = ui.PluginUtilities.getCallbackHandle(
      _backgroundIncomingCallDispatcher,
    );
    final callbackHandle = ui.PluginUtilities.getCallbackHandle(validator);
    if (dispatcherHandle == null || callbackHandle == null) {
      throw ArgumentError(
        'backgroundIncomingCallValidator must be a top-level or static function.',
      );
    }

    return _BackgroundIncomingCallValidatorHandles(
      backgroundDispatcherHandle: dispatcherHandle.toRawHandle(),
      backgroundCallbackHandle: callbackHandle.toRawHandle(),
    );
  }

  CallEventType _eventTypeFromDto(
    platform.CallEventType dtoType,
  ) {
    switch (dtoType) {
      case platform.CallEventType.incoming:
        return CallEventType.incoming;
      case platform.CallEventType.accepted:
        return CallEventType.accepted;
      case platform.CallEventType.declined:
        return CallEventType.declined;
      case platform.CallEventType.ended:
        return CallEventType.ended;
      case platform.CallEventType.timeout:
        return CallEventType.timeout;
      case platform.CallEventType.missed:
        return CallEventType.missed;
      case platform.CallEventType.callback:
        return CallEventType.callback;
      case platform.CallEventType.started:
        return CallEventType.started;
    }
  }

  platform.CallType _dtoCallTypeFromPublic(
    CallType callType,
  ) {
    switch (callType) {
      case CallType.audio:
        return platform.CallType.audio;
      case CallType.video:
        return platform.CallType.video;
    }
  }

  platform.PostCallBehavior _dtoPostCallBehaviorFromPublic(
    PostCallBehavior behavior,
  ) {
    switch (behavior) {
      case PostCallBehavior.stayOpen:
        return platform.PostCallBehavior.stayOpen;
      case PostCallBehavior.backgroundOnEnded:
        return platform.PostCallBehavior.backgroundOnEnded;
    }
  }
}

const MethodChannel _backgroundValidationChannel = MethodChannel(
  'callwave_flutter/background',
);

@pragma('vm:entry-point')
Future<void> _backgroundIncomingCallDispatcher() async {
  WidgetsFlutterBinding.ensureInitialized();
  ui.DartPluginRegistrant.ensureInitialized();
  _backgroundValidationChannel.setMethodCallHandler((call) async {
    if (call.method != 'validateBackgroundIncomingCall') {
      throw MissingPluginException(
        'Unsupported background validation method: ${call.method}',
      );
    }
    final arguments = call.arguments as Map<Object?, Object?>?;
    if (arguments == null) {
      return const <String, dynamic>{
        'isAllowed': false,
        'reason': 'unknown',
      };
    }

    final callbackHandleRaw = arguments['backgroundCallbackHandle'];
    if (callbackHandleRaw is! int) {
      return const <String, dynamic>{
        'isAllowed': false,
        'reason': 'unknown',
      };
    }

    final callback = ui.PluginUtilities.getCallbackFromHandle(
      ui.CallbackHandle.fromRawHandle(callbackHandleRaw),
    );
    if (callback is! BackgroundIncomingCallValidator) {
      return const <String, dynamic>{
        'isAllowed': false,
        'reason': 'unknown',
      };
    }

    final rawPayload = arguments['callData'];
    if (rawPayload is! Map) {
      return const <String, dynamic>{
        'isAllowed': false,
        'reason': 'unknown',
      };
    }

    final payload = rawPayload.map<String, dynamic>((key, value) {
      return MapEntry(key.toString(), value);
    });
    final dto = platform.PayloadCodec.callDataFromMap(payload);
    final decision = await callback(
      BackgroundIncomingCallValidationRequest(
        callId: dto.callId,
        callerName: dto.callerName,
        handle: dto.handle,
        avatarUrl: dto.avatarUrl,
        callType: dto.callType == platform.CallType.video
            ? CallType.video
            : CallType.audio,
        extra: dto.extra,
      ),
    );
    return <String, dynamic>{
      'isAllowed': decision.isAllowed,
      'reason': decision.reason?.name,
      'extra': decision.extra,
    };
  });
  await _backgroundValidationChannel.invokeMethod<void>(
    'backgroundDispatcherReady',
  );
}

final class _BackgroundIncomingCallValidatorHandles {
  const _BackgroundIncomingCallValidatorHandles({
    required this.backgroundDispatcherHandle,
    required this.backgroundCallbackHandle,
  });

  final int backgroundDispatcherHandle;
  final int backgroundCallbackHandle;
}
