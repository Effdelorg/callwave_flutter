import 'dart:async';

import 'package:callwave_flutter/callwave_flutter.dart';
import 'package:flutter/foundation.dart';

class MockCallwaveEngine extends CallwaveEngine {
  @override
  Future<void> onAnswerCall(CallSession session) async {
    debugPrint('MockCallwaveEngine onAnswerCall: ${session.callId}');
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!session.isEnded) {
      session.reportConnected();
    }
  }

  @override
  Future<void> onStartCall(CallSession session) async {
    debugPrint('MockCallwaveEngine onStartCall: ${session.callId}');
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!session.isEnded) {
      session.reportConnected();
    }
  }

  @override
  Future<void> onEndCall(CallSession session) async {
    debugPrint('MockCallwaveEngine onEndCall: ${session.callId}');
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  @override
  Future<void> onDeclineCall(CallSession session) async {
    debugPrint('MockCallwaveEngine onDeclineCall: ${session.callId}');
  }

  @override
  Future<void> onMuteChanged(CallSession session, bool muted) async {
    debugPrint('MockCallwaveEngine onMuteChanged: ${session.callId} -> $muted');
  }

  @override
  Future<void> onSpeakerChanged(CallSession session, bool speakerOn) async {
    debugPrint(
        'MockCallwaveEngine onSpeakerChanged: ${session.callId} -> $speakerOn');
  }

  @override
  Future<void> onCameraChanged(CallSession session, bool enabled) async {
    debugPrint(
        'MockCallwaveEngine onCameraChanged: ${session.callId} -> $enabled');
  }

  @override
  Future<void> onCameraSwitch(CallSession session) async {
    debugPrint('MockCallwaveEngine onCameraSwitch: ${session.callId}');
  }

  @override
  Future<void> onDispose(CallSession session) async {
    debugPrint('MockCallwaveEngine onDispose: ${session.callId}');
  }
}
