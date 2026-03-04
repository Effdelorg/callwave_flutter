import 'dart:async';

import 'package:callwave_flutter_platform_interface/callwave_flutter_platform_interface.dart'
    as platform;

import 'engine/callwave_engine.dart';
import 'engine/call_session.dart';
import 'enums/call_event_type.dart';
import 'enums/call_session_state.dart';
import 'enums/post_call_behavior.dart';
import 'enums/call_type.dart';
import 'models/call_data.dart';
import 'models/call_event.dart';
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
  final StreamController<CallSession> _sessionController =
      StreamController<CallSession>.broadcast();

  StreamSubscription<CallEvent>? _engineEventSubscription;
  CallwaveEngine? _engine;

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

  void setEngine(CallwaveEngine engine) {
    _disposeAllSessions();
    // Set the engine before wiring the listener so newly routed events always
    // see the current engine via CallSession.engineProvider.
    _engine = engine;
    final previousSubscription = _engineEventSubscription;
    _engineEventSubscription = null;
    unawaited(previousSubscription?.cancel());
    _engineEventSubscription = events.listen(
      _onEngineEvent,
      onError: _onEngineEventStreamError,
    );
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
    final listener = () => _onSessionChanged(callData.callId);
    _sessionListeners[callData.callId] = listener;
    session.addListener(listener);
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
          initialState: CallSessionState.connecting,
        );
        await session.applyNativeEvent(event);
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
    return _platform.showIncomingCall(_toDto(data));
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

  /// Declines an active incoming call.
  ///
  /// The returned future fails if [callId] does not map to an active incoming
  /// call on the current platform runtime.
  Future<void> declineCall(String callId) {
    return _platform.declineCall(callId);
  }

  Future<void> endCall(String callId) {
    return _platform.endCall(callId);
  }

  Future<void> markMissed(String callId) {
    return _platform.markMissed(callId);
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
          initialState: CallSessionState.connecting,
        );
        unawaited(session.applyNativeEvent(event));
        return;
      case CallEventType.started:
        final session = _ensureSessionFromEvent(
          event: event,
          isOutgoing: true,
          initialState: CallSessionState.connecting,
        );
        unawaited(session.applyNativeEvent(event));
        return;
      case CallEventType.declined:
      case CallEventType.ended:
      case CallEventType.timeout:
      case CallEventType.missed:
        final session = _sessions[event.callId];
        if (session != null) {
          unawaited(session.applyNativeEvent(event));
        }
        return;
      case CallEventType.callback:
        return;
    }
  }

  void _onEngineEventStreamError(Object error, StackTrace stackTrace) {
    Zone.current.handleUncaughtError(error, stackTrace);
  }

  void _onSessionChanged(String callId) {
    final session = _sessions[callId];
    if (session == null) {
      return;
    }
    if (session.isEnded) {
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
    _sessionCleanupTimers.remove(callId)?.cancel();
  }

  void _disposeSession(String callId) {
    _sessionCleanupTimers.remove(callId)?.cancel();
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
      case CallSessionState.connecting:
        if (session.state == CallSessionState.idle ||
            session.state == CallSessionState.ringing) {
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
      'CallwaveEngine is not set. Call setEngine(...) before session operations.',
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

  platform.CallDataDto _toDto(CallData data) {
    return platform.CallDataDto(
      callId: data.callId,
      callerName: data.callerName,
      handle: data.handle,
      avatarUrl: data.avatarUrl,
      timeoutSeconds: data.timeout.inSeconds,
      callType: _dtoCallTypeFromPublic(data.callType),
      extra: data.extra,
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
