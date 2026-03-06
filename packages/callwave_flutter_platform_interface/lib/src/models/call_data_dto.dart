import '../enums/call_type.dart';
import '../enums/incoming_accept_strategy.dart';

class CallDataDto {
  const CallDataDto({
    required this.callId,
    required this.callerName,
    required this.handle,
    this.avatarUrl,
    this.timeoutSeconds = 30,
    this.callType = CallType.audio,
    this.extra,
    this.incomingAcceptStrategy = IncomingAcceptStrategy.openImmediately,
    this.backgroundDispatcherHandle,
    this.backgroundCallbackHandle,
  });

  final String callId;
  final String callerName;
  final String handle;
  final String? avatarUrl;
  final int timeoutSeconds;
  final CallType callType;
  final Map<String, dynamic>? extra;
  final IncomingAcceptStrategy incomingAcceptStrategy;
  final int? backgroundDispatcherHandle;
  final int? backgroundCallbackHandle;

  CallDataDto copyWith({
    String? callId,
    String? callerName,
    String? handle,
    String? avatarUrl,
    int? timeoutSeconds,
    CallType? callType,
    Map<String, dynamic>? extra,
    IncomingAcceptStrategy? incomingAcceptStrategy,
    int? backgroundDispatcherHandle,
    int? backgroundCallbackHandle,
  }) {
    return CallDataDto(
      callId: callId ?? this.callId,
      callerName: callerName ?? this.callerName,
      handle: handle ?? this.handle,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      callType: callType ?? this.callType,
      extra: extra ?? this.extra,
      incomingAcceptStrategy:
          incomingAcceptStrategy ?? this.incomingAcceptStrategy,
      backgroundDispatcherHandle:
          backgroundDispatcherHandle ?? this.backgroundDispatcherHandle,
      backgroundCallbackHandle:
          backgroundCallbackHandle ?? this.backgroundCallbackHandle,
    );
  }
}
