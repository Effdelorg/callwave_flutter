import 'package:callwave_flutter/callwave_flutter.dart';

/// Builds fallback accepted events from native active call ids.
///
/// Why this exists:
/// On cold-start answer flows, Android can occasionally deliver active call
/// state before the buffered accepted event reaches Dart. This helper lets the
/// UI recover that accepted transition in one isolated place.
List<CallEvent> recoverAcceptedEventsFromActiveIds({
  required List<String> activeCallIds,
  required Set<String> acceptedCallIds,
  required Set<String> incomingCallIds,
  required Map<String, CallData> knownCallsById,
  DateTime? timestamp,
}) {
  if (activeCallIds.isEmpty) {
    return const <CallEvent>[];
  }

  final now = timestamp ?? DateTime.now();
  final recovered = <CallEvent>[];
  for (final callId in activeCallIds) {
    if (acceptedCallIds.contains(callId)) {
      continue;
    }
    // If we've already seen an incoming event for this call, keep it in
    // ringing state and wait for an explicit accepted event.
    if (incomingCallIds.contains(callId)) {
      continue;
    }
    recovered.add(
      CallEvent(
        callId: callId,
        type: CallEventType.accepted,
        timestamp: now,
        extra: knownCallsById[callId]?.extra,
      ),
    );
  }
  return recovered;
}
