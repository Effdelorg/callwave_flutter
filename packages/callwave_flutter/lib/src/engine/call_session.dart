// ignore_for_file: library_private_types_in_public_api

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../enums/call_event_type.dart';
import '../enums/call_session_state.dart';
import '../models/call_data.dart';
import '../models/call_event.dart';
import '../models/call_participant.dart';
import '../models/conference_state.dart';
import 'callwave_engine.dart';

typedef _CallwaveEngineProvider = CallwaveEngine? Function();
typedef _CallIdAction = Future<void> Function(String callId);
typedef _OutgoingStartAction = Future<void> Function(CallData callData);

enum _SessionToggleControl { mute, speaker, camera }

/// Single source of truth for one call's UI state.
///
/// Apps receive [CallSession] from [CallwaveFlutter.sessions] or
/// [CallwaveFlutter.getSession]. Do not construct directly.
///
/// Lifecycle: idle → ringing → validating → connecting → connected →
/// ended/failed.
/// Use [state], [elapsed], [isMuted], etc. to drive [CallScreen].
/// Call [reportConnected], [reportEnded], etc. from your [CallwaveEngine]
/// to update state.
class CallSession extends ChangeNotifier {
  CallSession({
    required CallData callData,
    required this.isOutgoing,
    CallSessionState initialState = CallSessionState.idle,
    ConferenceState initialConferenceState = ConferenceState.empty,
    DateTime? initialConnectedAt,
    _CallwaveEngineProvider? engineProvider,
    _CallIdAction? acceptNative,
    _CallIdAction? declineNative,
    _CallIdAction? endNative,
    _OutgoingStartAction? startOutgoingNative,
  })  : _callData = callData,
        _state = initialState,
        _connectedAt = initialConnectedAt,
        _conferenceState = _normalizeConferenceState(initialConferenceState),
        _engineProvider = engineProvider ?? _defaultEngineProvider,
        _acceptNative = acceptNative ?? _defaultCallIdAction,
        _declineNative = declineNative ?? _defaultCallIdAction,
        _endNative = endNative ?? _defaultCallIdAction,
        _startOutgoingNative = startOutgoingNative ?? _defaultOutgoingAction {
    if (_state == CallSessionState.connected ||
        (_state == CallSessionState.reconnecting && _connectedAt != null)) {
      _connectedAt ??= DateTime.now();
      _elapsed = DateTime.now().difference(_connectedAt!);
      _startTimerIfNeeded();
    }
  }

  static CallwaveEngine? _defaultEngineProvider() => null;

  static Future<void> _defaultCallIdAction(String _) async {}

  static Future<void> _defaultOutgoingAction(CallData _) async {}

  final bool isOutgoing;
  final _CallwaveEngineProvider _engineProvider;
  final _CallIdAction _acceptNative;
  final _CallIdAction _declineNative;
  final _CallIdAction _endNative;
  final _OutgoingStartAction _startOutgoingNative;

  CallData _callData;
  CallSessionState _state;
  DateTime? _connectedAt;
  Duration _elapsed = Duration.zero;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isCameraOn = true;
  Object? _error;
  ConferenceState _conferenceState;
  Timer? _timer;
  final Map<_SessionToggleControl, int> _toggleOperationVersions =
      <_SessionToggleControl, int>{};

  bool _acceptRequested = false;
  bool _declineRequested = false;
  bool _endRequested = false;
  bool _startRequested = false;
  bool _answerEngineInvoked = false;
  bool _startEngineInvoked = false;
  bool _resumeEngineInvoked = false;
  bool _endEngineInvoked = false;
  bool _declineEngineInvoked = false;
  bool _disposed = false;

  String get callId => _callData.callId;
  CallData get callData => _callData;
  CallSessionState get state => _state;
  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isCameraOn => _isCameraOn;
  DateTime? get connectedAt => _connectedAt;
  Duration get elapsed => _elapsed;
  Object? get error => _error;
  bool get didAttemptResume => _resumeEngineInvoked;
  ConferenceState get conferenceState => _conferenceState;
  int get participantCount => _conferenceState.participants.length;
  bool get isEnded =>
      _state == CallSessionState.ended || _state == CallSessionState.failed;

  void updateCallData(CallData next) {
    if (next.callId != callId) {
      return;
    }
    _callData = next;
    notifyListeners();
  }

  void updateConferenceState(ConferenceState next) {
    if (isEnded) {
      return;
    }
    final normalized = _normalizeConferenceState(next);
    if (normalized.updatedAtMs < _conferenceState.updatedAtMs) {
      return;
    }
    _conferenceState = normalized;
    notifyListeners();
  }

  Future<void> accept() async {
    if (isEnded || _acceptRequested) {
      return;
    }
    _acceptRequested = true;
    try {
      await _acceptNative(callId);
    } catch (error, stackTrace) {
      _logError('accept', error, stackTrace);
      reportFailed(error);
    }
  }

  Future<void> decline() async {
    if (isEnded || _declineRequested) {
      return;
    }
    _declineRequested = true;
    try {
      await _declineNative(callId);
      await _invokeDeclineEngineOnce();
    } catch (error, stackTrace) {
      _logError('decline', error, stackTrace);
      reportFailed(error);
    }
  }

  Future<void> end() async {
    if (isEnded || _endRequested) {
      return;
    }
    _endRequested = true;
    try {
      await _endNative(callId);
    } catch (error, stackTrace) {
      _logError('end', error, stackTrace);
      reportFailed(error);
    }
  }

  Future<void> start() async {
    if (isEnded || _startRequested || !isOutgoing) {
      return;
    }
    _startRequested = true;
    try {
      await _startOutgoingNative(_callData);
      reportConnecting();
    } catch (error, stackTrace) {
      _logError('start', error, stackTrace);
      reportFailed(error);
    }
  }

  Future<void> toggleMute() async {
    await _toggleControl(
      control: _SessionToggleControl.mute,
      action: 'toggleMute',
      onChanged: (enabled) async {
        await _engineProvider()?.onMuteChanged(this, enabled);
      },
    );
  }

  Future<void> toggleSpeaker() async {
    await _toggleControl(
      control: _SessionToggleControl.speaker,
      action: 'toggleSpeaker',
      onChanged: (enabled) async {
        await _engineProvider()?.onSpeakerChanged(this, enabled);
      },
    );
  }

  Future<void> toggleCamera() async {
    await _toggleControl(
      control: _SessionToggleControl.camera,
      action: 'toggleCamera',
      onChanged: (enabled) async {
        await _engineProvider()?.onCameraChanged(this, enabled);
      },
    );
  }

  Future<void> _toggleControl({
    required _SessionToggleControl control,
    required String action,
    required Future<void> Function(bool enabled) onChanged,
  }) async {
    if (isEnded) {
      return;
    }
    final previous = _controlValue(control);
    final next = !previous;
    _setControlValue(control, next);
    notifyListeners();
    final operationVersion = (_toggleOperationVersions[control] ?? 0) + 1;
    _toggleOperationVersions[control] = operationVersion;
    try {
      await onChanged(next);
    } catch (error, stackTrace) {
      final latestOperation = _toggleOperationVersions[control] ?? 0;
      final isLatestOperation = latestOperation == operationVersion;
      final stateUnchangedSinceRequest = _controlValue(control) == next;
      if (!isEnded && isLatestOperation && stateUnchangedSinceRequest) {
        _setControlValue(control, previous);
        notifyListeners();
      }
      _logError(action, error, stackTrace);
    }
  }

  bool _controlValue(_SessionToggleControl control) {
    switch (control) {
      case _SessionToggleControl.mute:
        return _isMuted;
      case _SessionToggleControl.speaker:
        return _isSpeakerOn;
      case _SessionToggleControl.camera:
        return _isCameraOn;
    }
  }

  void _setControlValue(_SessionToggleControl control, bool value) {
    switch (control) {
      case _SessionToggleControl.mute:
        _isMuted = value;
        return;
      case _SessionToggleControl.speaker:
        _isSpeakerOn = value;
        return;
      case _SessionToggleControl.camera:
        _isCameraOn = value;
        return;
    }
  }

  Future<void> switchCamera() async {
    if (isEnded) {
      return;
    }
    try {
      await _engineProvider()?.onCameraSwitch(this);
    } catch (error, stackTrace) {
      _logError('switchCamera', error, stackTrace);
    }
  }

  Future<void> applyNativeEvent(CallEvent event) async {
    if (event.callId != callId || isEnded) {
      return;
    }
    switch (event.type) {
      case CallEventType.incoming:
        reportRinging();
        return;
      case CallEventType.accepted:
        return;
      case CallEventType.started:
        await beginOutgoingStart();
        return;
      case CallEventType.ended:
        reportEnded();
        return;
      case CallEventType.declined:
        await _invokeDeclineEngineOnce();
        reportEnded();
        return;
      case CallEventType.timeout:
      case CallEventType.missed:
        if (_state == CallSessionState.idle ||
            _state == CallSessionState.ringing ||
            _state == CallSessionState.validating) {
          reportEnded();
        }
        return;
      case CallEventType.callback:
        return;
    }
  }

  void reportRinging() => _transitionTo(CallSessionState.ringing);

  void reportValidating() => _transitionTo(CallSessionState.validating);

  void reportConnecting() => _transitionTo(CallSessionState.connecting);

  void reportConnected() => _transitionTo(CallSessionState.connected);

  void reportReconnecting() => _transitionTo(CallSessionState.reconnecting);

  void reportEnded() => _transitionTo(CallSessionState.ended);

  void reportFailed([Object? error]) {
    _error = error ?? StateError('Call session failed.');
    _transitionTo(CallSessionState.failed);
  }

  Future<void> beginAnswering() async {
    if (_state == CallSessionState.connected ||
        _state == CallSessionState.reconnecting) {
      return;
    }
    reportConnecting();
    await _invokeAnswerEngineOnce();
  }

  Future<void> beginOutgoingStart() async {
    if (_state == CallSessionState.connected ||
        _state == CallSessionState.reconnecting) {
      return;
    }
    reportConnecting();
    await _invokeStartEngineOnce();
  }

  /// Resumes a previously ongoing call after cold start; invokes [CallwaveEngine.onResumeCall].
  Future<void> beginResume() async {
    if (isEnded || _resumeEngineInvoked) {
      return;
    }
    reportReconnecting();
    await _invokeResumeEngineOnce();
  }

  /// Updates [connectedAt] and [elapsed] for restored ongoing calls.
  void restoreConnectedTimeline(DateTime connectedAt) {
    if (isEnded) {
      return;
    }
    if (_connectedAt == null || connectedAt.isBefore(_connectedAt!)) {
      _connectedAt = connectedAt;
    }
    _elapsed = DateTime.now().difference(_connectedAt!);
    _startTimerIfNeeded();
    notifyListeners();
  }

  Future<void> _invokeAnswerEngineOnce() async {
    if (_answerEngineInvoked || isEnded) {
      return;
    }
    _answerEngineInvoked = true;
    try {
      await _engineProvider()?.onAnswerCall(this);
    } catch (error, stackTrace) {
      _logError('onAnswerCall', error, stackTrace);
      reportFailed(error);
    }
  }

  Future<void> _invokeStartEngineOnce() async {
    if (_startEngineInvoked || isEnded) {
      return;
    }
    _startEngineInvoked = true;
    try {
      await _engineProvider()?.onStartCall(this);
    } catch (error, stackTrace) {
      _logError('onStartCall', error, stackTrace);
      reportFailed(error);
    }
  }

  Future<void> _invokeResumeEngineOnce() async {
    if (_resumeEngineInvoked || isEnded) {
      return;
    }
    _resumeEngineInvoked = true;
    try {
      await _engineProvider()?.onResumeCall(this);
    } catch (error, stackTrace) {
      _logError('onResumeCall', error, stackTrace);
      reportFailed(error);
    }
  }

  Future<void> _invokeEndEngineOnce() async {
    if (_endEngineInvoked) {
      return;
    }
    _endEngineInvoked = true;
    try {
      await _engineProvider()?.onEndCall(this);
    } catch (error, stackTrace) {
      _logError('onEndCall', error, stackTrace);
    }
  }

  Future<void> _invokeDeclineEngineOnce() async {
    if (_declineEngineInvoked) {
      return;
    }
    _declineEngineInvoked = true;
    try {
      await _engineProvider()?.onDeclineCall(this);
    } catch (error, stackTrace) {
      _logError('onDeclineCall', error, stackTrace);
    }
  }

  void _transitionTo(CallSessionState next) {
    if (_state == next || isEnded) {
      return;
    }
    _state = next;
    if (next == CallSessionState.connected ||
        (next == CallSessionState.reconnecting && _connectedAt != null)) {
      _connectedAt ??= DateTime.now();
      _elapsed = DateTime.now().difference(_connectedAt!);
      _startTimerIfNeeded();
    }
    if (next == CallSessionState.ended || next == CallSessionState.failed) {
      _stopTimer();
      unawaited(_invokeEndEngineOnce());
    }
    notifyListeners();
  }

  void _startTimerIfNeeded() {
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      final connectedAt = _connectedAt;
      if (connectedAt == null) {
        _elapsed = Duration.zero;
      } else {
        _elapsed = DateTime.now().difference(connectedAt);
      }
      notifyListeners();
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _logError(String action, Object error, StackTrace stackTrace) {
    debugPrint('CallSession $action failed for callId=$callId: $error');
    debugPrintStack(
      label: 'CallSession $action stack trace',
      stackTrace: stackTrace,
    );
  }

  static ConferenceState _normalizeConferenceState(ConferenceState state) {
    final deduped = <String, CallParticipant>{};
    for (final participant in state.participants) {
      final id = participant.participantId.trim();
      if (id.isEmpty) {
        continue;
      }
      deduped.remove(id);
      deduped[id] = participant;
    }

    final participants = deduped.values.toList(growable: false)
      ..sort((a, b) {
        final orderA = a.sortOrder ?? 1 << 30;
        final orderB = b.sortOrder ?? 1 << 30;
        if (orderA != orderB) {
          return orderA.compareTo(orderB);
        }
        return a.displayName
            .toLowerCase()
            .compareTo(b.displayName.toLowerCase());
      });

    final participantIds = participants.map((p) => p.participantId).toSet();
    final pinnedParticipantId =
        participantIds.contains(state.pinnedParticipantId)
            ? state.pinnedParticipantId
            : null;
    final activeSpeakerId = participantIds.contains(state.activeSpeakerId)
        ? state.activeSpeakerId
        : null;

    return ConferenceState(
      participants: participants,
      activeSpeakerId: activeSpeakerId,
      pinnedParticipantId: pinnedParticipantId,
      updatedAtMs: state.updatedAtMs,
    );
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _stopTimer();
    unawaited(_engineProvider()?.onDispose(this));
    super.dispose();
  }
}
