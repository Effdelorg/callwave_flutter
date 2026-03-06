import '../enums/call_type.dart';

/// Serializable request passed to background incoming-call validators.
class BackgroundIncomingCallValidationRequest {
  const BackgroundIncomingCallValidationRequest({
    required this.callId,
    required this.callerName,
    required this.handle,
    required this.callType,
    this.avatarUrl,
    this.extra,
  });

  final String callId;
  final String callerName;
  final String handle;
  final String? avatarUrl;
  final CallType callType;
  final Map<String, dynamic>? extra;
}
