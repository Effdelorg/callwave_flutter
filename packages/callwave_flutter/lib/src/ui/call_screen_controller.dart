import 'dart:async';

import 'package:flutter/foundation.dart';

import '../engine/call_session.dart';
import '../enums/call_session_state.dart';
import '../enums/call_type.dart';

/// Possible states for the in-app call screen.
enum CallStatus { ringing, connecting, connected, ended }

/// Session-driven state machine for [CallScreen].
///
/// This controller always depends on a [CallSession] and does not subscribe
/// directly to platform event streams.
class CallScreenController extends ChangeNotifier {
  CallScreenController({
    required this.session,
  }) {
    _syncFromSession(notify: false);
    session.addListener(_onSessionChanged);
  }

  final CallSession session;

  CallStatus get status => _status;
  CallStatus _status = CallStatus.ringing;

  Duration get elapsed => _elapsed;
  Duration _elapsed = Duration.zero;

  bool get isMuted => _isMuted;
  bool _isMuted = false;

  bool get isSpeakerOn => _isSpeakerOn;
  bool _isSpeakerOn = false;

  bool get isCameraOn => _isCameraOn;
  bool _isCameraOn = true;

  bool get isVideo => session.callData.callType == CallType.video;

  String get statusText => _statusText();

  void toggleMute() {
    unawaited(session.toggleMute());
  }

  void toggleSpeaker() {
    unawaited(session.toggleSpeaker());
  }

  void toggleCamera() {
    unawaited(session.toggleCamera());
  }

  void endCall() {
    unawaited(session.end());
  }

  void acceptCall() {
    unawaited(session.accept());
  }

  void declineCall() {
    unawaited(session.decline());
  }

  void _onSessionChanged() {
    _syncFromSession();
  }

  void _syncFromSession({bool notify = true}) {
    _status = _statusFromSession(session.state);
    _elapsed = session.elapsed;
    _isMuted = session.isMuted;
    _isSpeakerOn = session.isSpeakerOn;
    _isCameraOn = session.isCameraOn;
    if (notify) {
      notifyListeners();
    }
  }

  CallStatus _statusFromSession(CallSessionState state) {
    switch (state) {
      case CallSessionState.idle:
      case CallSessionState.ringing:
        return CallStatus.ringing;
      case CallSessionState.validating:
      case CallSessionState.connecting:
        return CallStatus.connecting;
      case CallSessionState.connected:
      case CallSessionState.reconnecting:
        return CallStatus.connected;
      case CallSessionState.ended:
      case CallSessionState.failed:
        return CallStatus.ended;
    }
  }

  String _statusText() {
    if (session.state == CallSessionState.failed && session.didAttemptResume) {
      return 'Unable to rejoin call';
    }
    switch (_status) {
      case CallStatus.ringing:
        return 'Ringing...';
      case CallStatus.connecting:
        return 'Connecting...';
      case CallStatus.connected:
        return '';
      case CallStatus.ended:
        return 'Call Ended';
    }
  }

  @override
  void dispose() {
    session.removeListener(_onSessionChanged);
    super.dispose();
  }
}
