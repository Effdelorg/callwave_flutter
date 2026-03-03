import 'package:callwave_flutter_platform_interface/callwave_flutter_platform_interface.dart'
    as platform;

import 'enums/call_event_type.dart';
import 'enums/post_call_behavior.dart';
import 'enums/call_type.dart';
import 'models/call_data.dart';
import 'models/call_event.dart';

class CallwaveFlutter {
  CallwaveFlutter._();

  static final CallwaveFlutter instance = CallwaveFlutter._();

  platform.CallwaveFlutterPlatform get _platform =>
      platform.CallwaveFlutterPlatform.instance;

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
