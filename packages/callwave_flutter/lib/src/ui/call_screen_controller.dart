import 'dart:async';

import 'package:flutter/foundation.dart';

import '../callwave_flutter_impl.dart';
import '../enums/call_event_type.dart';
import '../enums/call_type.dart';
import '../models/call_event.dart';

/// Possible states for the in-app call screen.
enum CallStatus { ringing, connecting, connected, ended }

/// State machine that drives [CallScreen].
///
/// Listens to [CallwaveFlutter.instance.events] filtered by [callId] and
/// manages status transitions, an elapsed-time timer, and local UI toggles
/// (mute / speaker).
class CallScreenController extends ChangeNotifier {
  static const Duration _simulatedConnectingDelay = Duration(milliseconds: 800);

  CallScreenController({
    required this.callId,
    required this.callType,
    bool isOutgoing = false,
  }) : _status = isOutgoing ? CallStatus.connecting : CallStatus.ringing {
    _subscription = CallwaveFlutter.instance.events
        .where((e) => e.callId == callId)
        .listen(_onEvent, onError: _onEventStreamError);
  }

  final String callId;
  final CallType callType;

  // ── Public state ──────────────────────────────────────────────────────

  CallStatus get status => _status;
  CallStatus _status;

  Duration get elapsed => _elapsed;
  Duration _elapsed = Duration.zero;

  bool get isMuted => _isMuted;
  bool _isMuted = false;

  bool get isSpeakerOn => _isSpeakerOn;
  bool _isSpeakerOn = false;

  bool get isVideo => callType == CallType.video;

  // ── Internals ─────────────────────────────────────────────────────────

  StreamSubscription<CallEvent>? _subscription;
  Timer? _timer;

  // ── Actions ───────────────────────────────────────────────────────────

  void toggleMute() {
    _isMuted = !_isMuted;
    notifyListeners();
  }

  void toggleSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;
    notifyListeners();
  }

  void endCall() {
    CallwaveFlutter.instance.endCall(callId);
  }

  // ── Event handling ────────────────────────────────────────────────────

  void _onEvent(CallEvent event) {
    switch (event.type) {
      case CallEventType.accepted:
      case CallEventType.started:
        _transitionTo(CallStatus.connecting);
        // Simulate brief connecting phase then move to connected.
        Future<void>.delayed(_simulatedConnectingDelay, () {
          if (_status == CallStatus.connecting) {
            _transitionTo(CallStatus.connected);
          }
        });
      case CallEventType.ended:
      case CallEventType.declined:
      case CallEventType.timeout:
      case CallEventType.missed:
        _transitionTo(CallStatus.ended);
      case CallEventType.callback:
        break;
    }
  }

  void _onEventStreamError(Object error, StackTrace stackTrace) {
    debugPrint('CallScreenController event stream error: $error');
    debugPrintStack(
      label: 'CallScreenController event stream stack trace',
      stackTrace: stackTrace,
    );
  }

  void _transitionTo(CallStatus next) {
    if (_status == next || _status == CallStatus.ended) return;
    _status = next;

    if (next == CallStatus.connected) {
      _startTimer();
    } else if (next == CallStatus.ended) {
      _stopTimer();
    }

    notifyListeners();
  }

  // ── Timer ─────────────────────────────────────────────────────────────

  void _startTimer() {
    _timer?.cancel();
    _elapsed = Duration.zero;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsed += const Duration(seconds: 1);
      notifyListeners();
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────

  @override
  void dispose() {
    _stopTimer();
    _subscription?.cancel();
    super.dispose();
  }
}
