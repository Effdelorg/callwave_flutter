import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'enums/post_call_behavior.dart';
import 'models/call_data_dto.dart';
import 'models/call_event_dto.dart';

abstract class CallwaveFlutterPlatform extends PlatformInterface {
  CallwaveFlutterPlatform() : super(token: _token);

  static final Object _token = Object();

  static CallwaveFlutterPlatform _instance = _StubCallwaveFlutterPlatform();

  static CallwaveFlutterPlatform get instance => _instance;

  static set instance(CallwaveFlutterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Stream<CallEventDto> get events;

  Future<void> initialize();

  Future<void> showIncomingCall(CallDataDto data);

  Future<void> showOutgoingCall(CallDataDto data);

  Future<void> endCall(String callId);

  Future<void> markMissed(String callId);

  Future<List<String>> getActiveCallIds();

  Future<bool> requestNotificationPermission();

  Future<void> requestFullScreenIntentPermission();

  /// Configures post-call behavior when the user ends a call via [endCall].
  ///
  /// On Android, [PostCallBehavior.backgroundOnEnded] moves the app to
  /// background. On iOS, the setting is accepted but has no effect.
  Future<void> setPostCallBehavior(PostCallBehavior behavior);
}

class _StubCallwaveFlutterPlatform extends CallwaveFlutterPlatform {
  @override
  Stream<CallEventDto> get events => const Stream<CallEventDto>.empty();

  @override
  Future<void> endCall(String callId) {
    throw UnimplementedError('endCall() has not been implemented.');
  }

  @override
  Future<List<String>> getActiveCallIds() {
    throw UnimplementedError('getActiveCallIds() has not been implemented.');
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> markMissed(String callId) {
    throw UnimplementedError('markMissed() has not been implemented.');
  }

  @override
  Future<void> requestFullScreenIntentPermission() {
    throw UnimplementedError(
      'requestFullScreenIntentPermission() has not been implemented.',
    );
  }

  @override
  Future<bool> requestNotificationPermission() {
    throw UnimplementedError(
      'requestNotificationPermission() has not been implemented.',
    );
  }

  @override
  Future<void> setPostCallBehavior(PostCallBehavior behavior) {
    throw UnimplementedError(
      'setPostCallBehavior() has not been implemented.',
    );
  }

  @override
  Future<void> showIncomingCall(CallDataDto data) {
    throw UnimplementedError('showIncomingCall() has not been implemented.');
  }

  @override
  Future<void> showOutgoingCall(CallDataDto data) {
    throw UnimplementedError('showOutgoingCall() has not been implemented.');
  }
}
