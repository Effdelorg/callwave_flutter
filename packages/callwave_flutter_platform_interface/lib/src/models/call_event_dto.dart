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

  /// Platform-provided metadata. Implementations may include `launchAction` for
  /// routing (e.g. Android sets it when the user taps the ongoing call
  /// notification). Use `CallEventExtraKeys` from the main package for constants.
  final Map<String, dynamic>? extra;
}
