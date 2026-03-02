import '../enums/call_event_type.dart';

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
  final Map<String, dynamic>? extra;
}
