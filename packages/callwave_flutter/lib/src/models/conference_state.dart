import 'call_participant.dart';

/// Snapshot of conference participants and speaker state.
///
/// Pass to [CallSession.updateConferenceState]. Older [updatedAtMs] snapshots
/// are ignored. Updates are ignored once the session is ended/failed.
class ConferenceState {
  const ConferenceState({
    this.participants = const <CallParticipant>[],
    this.activeSpeakerId,
    this.pinnedParticipantId,
    this.updatedAtMs = 0,
  });

  static const ConferenceState empty = ConferenceState();

  final List<CallParticipant> participants;
  final String? activeSpeakerId;
  final String? pinnedParticipantId;
  final int updatedAtMs;

  ConferenceState copyWith({
    List<CallParticipant>? participants,
    String? activeSpeakerId,
    String? pinnedParticipantId,
    int? updatedAtMs,
  }) {
    return ConferenceState(
      participants: participants ?? this.participants,
      activeSpeakerId: activeSpeakerId ?? this.activeSpeakerId,
      pinnedParticipantId: pinnedParticipantId ?? this.pinnedParticipantId,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }
}
