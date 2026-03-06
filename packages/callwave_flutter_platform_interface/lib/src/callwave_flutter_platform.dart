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

  Future<void> registerBackgroundIncomingCallValidator({
    required int backgroundDispatcherHandle,
    required int backgroundCallbackHandle,
  }) async {
    throw UnimplementedError(
      'registerBackgroundIncomingCallValidator() has not been implemented.',
    );
  }

  Future<void> clearBackgroundIncomingCallValidator() async {
    throw UnimplementedError(
      'clearBackgroundIncomingCallValidator() has not been implemented.',
    );
  }

  /// Accepts an active incoming call.
  ///
  /// Implementations should throw if [callId] is unknown or no longer active.
  Future<void> acceptCall(String callId);

  /// Marks an accepted call as safe to open/connect.
  ///
  /// Only used when [IncomingAcceptStrategy.deferOpenUntilConfirmed]. Default:
  /// no-op. Override for platforms that support deferred confirmation.
  Future<void> confirmAcceptedCall(String callId) async {}

  /// Declines an active incoming call.
  ///
  /// Implementations should throw if [callId] is unknown or no longer active.
  Future<void> declineCall(String callId);

  Future<void> endCall(String callId);

  /// Marks a call as missed. [extra] can include outcome reason for validation
  /// rejections (e.g. `outcomeReason`).
  Future<void> markMissed(String callId, {Map<String, dynamic>? extra});

  Future<List<String>> getActiveCallIds();

  /// Returns a snapshot of active call event state (as opposed to emitting via
  /// the event stream).
  ///
  /// Used by startup restoration to avoid event-stream delivery races.
  /// Typical entries are `incoming`, `accepted`, or `started`.
  Future<List<CallEventDto>> getActiveCallEventSnapshots() async {
    return const <CallEventDto>[];
  }

  /// Re-emits native snapshots for currently active calls.
  ///
  /// Implementations should publish synthetic events (incoming/accepted/started)
  /// with the latest known payload. Used during cold-start restoration to
  /// hydrate metadata and replay engine hooks when event delivery raced app
  /// startup.
  Future<void> syncActiveCallsToEvents() async {}

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
  Future<void> acceptCall(String callId) {
    throw UnimplementedError('acceptCall() has not been implemented.');
  }

  @override
  Future<void> confirmAcceptedCall(String callId) {
    throw UnimplementedError(
      'confirmAcceptedCall() has not been implemented.',
    );
  }

  @override
  Future<void> declineCall(String callId) {
    throw UnimplementedError('declineCall() has not been implemented.');
  }

  @override
  Future<List<String>> getActiveCallIds() {
    throw UnimplementedError('getActiveCallIds() has not been implemented.');
  }

  @override
  Future<List<CallEventDto>> getActiveCallEventSnapshots() async {
    return const <CallEventDto>[];
  }

  @override
  Future<void> syncActiveCallsToEvents() async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> markMissed(String callId, {Map<String, dynamic>? extra}) {
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

  @override
  Future<void> registerBackgroundIncomingCallValidator({
    required int backgroundDispatcherHandle,
    required int backgroundCallbackHandle,
  }) {
    throw UnimplementedError(
      'registerBackgroundIncomingCallValidator() has not been implemented.',
    );
  }

  @override
  Future<void> clearBackgroundIncomingCallValidator() {
    throw UnimplementedError(
      'clearBackgroundIncomingCallValidator() has not been implemented.',
    );
  }
}
