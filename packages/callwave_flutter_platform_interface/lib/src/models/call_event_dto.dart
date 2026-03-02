import '../enums/call_event_type.dart';

class CallEventDto {
  const CallEventDto({
    required this.callId,
    required this.type,
    required this.timestampMs,
    this.extra,
  });

  final String callId;
  final CallEventType type;
  final int timestampMs;
  final Map<String, dynamic>? extra;
}
