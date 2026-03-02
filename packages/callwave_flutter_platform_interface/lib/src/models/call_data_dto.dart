import '../enums/call_type.dart';

class CallDataDto {
  const CallDataDto({
    required this.callId,
    required this.callerName,
    required this.handle,
    this.avatarUrl,
    this.timeoutSeconds = 30,
    this.callType = CallType.audio,
    this.extra,
  });

  final String callId;
  final String callerName;
  final String handle;
  final String? avatarUrl;
  final int timeoutSeconds;
  final CallType callType;
  final Map<String, dynamic>? extra;

  CallDataDto copyWith({
    String? callId,
    String? callerName,
    String? handle,
    String? avatarUrl,
    int? timeoutSeconds,
    CallType? callType,
    Map<String, dynamic>? extra,
  }) {
    return CallDataDto(
      callId: callId ?? this.callId,
      callerName: callerName ?? this.callerName,
      handle: handle ?? this.handle,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      callType: callType ?? this.callType,
      extra: extra ?? this.extra,
    );
  }
}
