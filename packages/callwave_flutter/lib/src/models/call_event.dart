import '../enums/call_event_type.dart';
import 'call_event_extra_keys.dart';

class CallEvent {
  const CallEvent({
    required this.callId,
    required this.type,
    required this.timestamp,
    this.extra,
  });

  final String callId;
  final CallEventType type;
  final DateTime timestamp;

  /// Platform-provided metadata. May include [CallEventExtraKeys.launchAction]
  /// (e.g. when the user taps the ongoing call notification on Android) for
  /// routing decisions.
  final Map<String, dynamic>? extra;
}
