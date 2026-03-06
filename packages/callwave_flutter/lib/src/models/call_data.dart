import '../enums/call_type.dart';

class CallData {
  static const Object _sentinel = Object();

  const CallData({
    required this.callId,
    required this.callerName,
    required this.handle,
    this.avatarUrl,
    this.timeout = const Duration(seconds: 30),
    this.callType = CallType.audio,
    this.extra,
  });

  final String callId;
  final String callerName;
  final String handle;
  final String? avatarUrl;
  final Duration timeout;
  final CallType callType;
  final Map<String, dynamic>? extra;

  CallData copyWith({
    String? callId,
    String? callerName,
    String? handle,
    Object? avatarUrl = _sentinel,
    Duration? timeout,
    CallType? callType,
    Object? extra = _sentinel,
  }) {
    return CallData(
      callId: callId ?? this.callId,
      callerName: callerName ?? this.callerName,
      handle: handle ?? this.handle,
      avatarUrl: identical(avatarUrl, _sentinel)
          ? this.avatarUrl
          : avatarUrl as String?,
      timeout: timeout ?? this.timeout,
      callType: callType ?? this.callType,
      extra: identical(extra, _sentinel)
          ? this.extra
          : extra as Map<String, dynamic>?,
    );
  }
}
