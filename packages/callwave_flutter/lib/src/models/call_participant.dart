/// A participant in a conference call.
///
/// Pass to [ConferenceState] and update via [CallSession.updateConferenceState].
/// Duplicate [participantId] entries are deduped (latest wins).
class CallParticipant {
  const CallParticipant({
    required this.participantId,
    required this.displayName,
    this.avatarUrl,
    this.isLocal = false,
    this.isMuted = false,
    this.isVideoOn = true,
    this.isSpeaking = false,
    this.isScreenSharing = false,
    this.sortOrder,
  });

  final String participantId;
  final String displayName;
  final String? avatarUrl;
  final bool isLocal;
  final bool isMuted;
  final bool isVideoOn;
  final bool isSpeaking;
  final bool isScreenSharing;
  final int? sortOrder;

  CallParticipant copyWith({
    String? participantId,
    String? displayName,
    String? avatarUrl,
    bool? isLocal,
    bool? isMuted,
    bool? isVideoOn,
    bool? isSpeaking,
    bool? isScreenSharing,
    int? sortOrder,
  }) {
    return CallParticipant(
      participantId: participantId ?? this.participantId,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isLocal: isLocal ?? this.isLocal,
      isMuted: isMuted ?? this.isMuted,
      isVideoOn: isVideoOn ?? this.isVideoOn,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      isScreenSharing: isScreenSharing ?? this.isScreenSharing,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
