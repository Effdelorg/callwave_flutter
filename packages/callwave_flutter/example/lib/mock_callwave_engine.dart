import 'dart:async';

import 'package:callwave_flutter/callwave_flutter.dart';
import 'package:flutter/widgets.dart';

import 'example_camera_controller.dart';

class MockCallwaveEngine extends CallwaveEngine {
  MockCallwaveEngine({
    ExampleCameraHandle? cameraController,
  }) : _cameraController = cameraController ?? _NoopCameraHandle.instance;

  final ExampleCameraHandle _cameraController;

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
    await _cameraController.setCameraEnabled(session.callId, false);
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
    await _cameraController.setCameraEnabled(session.callId, enabled);
    debugPrint(
        'MockCallwaveEngine onCameraChanged: ${session.callId} -> $enabled');
  }

  @override
  Future<void> onCameraSwitch(CallSession session) async {
    debugPrint('MockCallwaveEngine onCameraSwitch: ${session.callId}');
  }

  @override
  Future<void> onDispose(CallSession session) async {
    await _cameraController.setCameraEnabled(session.callId, false);
    await _cameraController.detachSession(session.callId);
    debugPrint('MockCallwaveEngine onDispose: ${session.callId}');
  }
}

class _NoopCameraHandle extends ExampleCameraHandle {
  _NoopCameraHandle._();

  static final _NoopCameraHandle instance = _NoopCameraHandle._();

  @override
  ExampleCameraState get state => ExampleCameraState.idle;

  @override
  bool get isPreviewReady => false;

  @override
  double? get previewAspectRatio => null;

  @override
  String? get errorMessage => null;

  @override
  Future<void> attachSession(String callId) async {}

  @override
  Widget buildPreview({Key? key}) => const SizedBox.shrink();

  @override
  Future<void> detachSession(String callId) async {}

  @override
  Future<void> openSystemSettings() async {}

  @override
  Future<void> retryPermission(String callId) async {}

  @override
  Future<void> setCameraEnabled(String callId, bool enabled) async {}
}
