import '../enums/call_type.dart';

class CallData {
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
}
