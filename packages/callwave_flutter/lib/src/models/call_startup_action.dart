import '../enums/call_startup_action_type.dart';
import '../enums/call_type.dart';

/// One-shot action captured when the app was launched from a missed-call
/// notification (e.g. tap body or "Call Back").
class CallStartupAction {
  const CallStartupAction({
    required this.type,
    required this.callId,
    required this.callerName,
    required this.handle,
    this.avatarUrl,
    this.callType = CallType.audio,
    this.extra,
  });

  final CallStartupActionType type;
  final String callId;
  final String callerName;
  final String handle;
  final String? avatarUrl;
  final CallType callType;
  final Map<String, dynamic>? extra;
}
