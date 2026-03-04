import 'call_session.dart';

/// Bridge between callwave_flutter and your WebRTC/call provider.
///
/// Implement this to connect call UI (accept, decline, mute, etc.) to your
/// actual call logic. The package handles native notifications, CallKit,
/// and session state; you handle connection, media, and signaling.
///
/// Must be set via [CallwaveFlutter.setEngine] before any session operations.
abstract class CallwaveEngine {
  /// Called when the user accepts an incoming call.
  ///
  /// Join your call/room here (e.g. via WebRTC provider), then call
  /// [CallSession.reportConnected] when the connection is established.
  Future<void> onAnswerCall(CallSession session);

  /// Called when an outgoing call starts.
  ///
  /// Initiate your call here, then call [CallSession.reportConnected]
  /// when the connection is established.
  Future<void> onStartCall(CallSession session);

  /// Called when the call ends (user or remote).
  ///
  /// Leave your call/room and release resources here.
  Future<void> onEndCall(CallSession session);

  /// Called when the user declines an incoming call.
  Future<void> onDeclineCall(CallSession session);

  /// Called when the user toggles mute.
  Future<void> onMuteChanged(CallSession session, bool muted);

  /// Called when the user toggles speaker.
  Future<void> onSpeakerChanged(CallSession session, bool speakerOn);

  /// Called when the user toggles camera on/off.
  Future<void> onCameraChanged(CallSession session, bool enabled);

  /// Called when the user switches camera (e.g. front/back).
  Future<void> onCameraSwitch(CallSession session);

  /// Called when the session is disposed.
  ///
  /// Use for cleanup tied to the session lifecycle.
  Future<void> onDispose(CallSession session);
}
