import 'package:flutter/material.dart';

import '../../engine/call_session.dart';
import '../../utils/initials.dart';
import '../../enums/call_type.dart';
import '../../models/call_participant.dart';
import '../call_screen_builders.dart';
import '../call_screen_controller.dart';
import '../theme/callwave_theme.dart';
import 'call_action_button.dart';

class ConferenceCallView extends StatelessWidget {
  const ConferenceCallView({
    required this.session,
    required this.controller,
    this.participantTileBuilder,
    this.conferenceControlsBuilder,
    super.key,
  });

  final CallSession session;
  final CallScreenController controller;
  final ParticipantTileBuilder? participantTileBuilder;
  final ConferenceControlsBuilder? conferenceControlsBuilder;

  @override
  Widget build(BuildContext context) {
    final participants = _resolvedParticipants();
    final primary = _selectPrimaryParticipant(participants);
    CallParticipant? local;
    for (final participant in participants) {
      if (participant.isLocal) {
        local = participant;
        break;
      }
    }
    final railParticipants = participants
        .where(
          (participant) =>
              participant.participantId != primary.participantId &&
              participant.participantId != local?.participantId,
        )
        .toList(growable: false);
    final showLocalPanel =
        local != null && local.participantId != primary.participantId;

    return Column(
      key: const ValueKey<String>('conference-view'),
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    key: const ValueKey<String>('conference-left-column'),
                    children: [
                      Expanded(
                        child: _ParticipantPanel(
                          key: const ValueKey<String>(
                            'conference-primary-panel',
                          ),
                          session: session,
                          participant: primary,
                          index: 0,
                          isPrimary: true,
                          title: 'Current Speaker',
                          participantTileBuilder: participantTileBuilder,
                        ),
                      ),
                      if (showLocalPanel) const SizedBox(height: 12),
                      if (showLocalPanel)
                        Expanded(
                          child: _ParticipantPanel(
                            key: const ValueKey<String>(
                                'conference-local-panel'),
                            session: session,
                            participant: local,
                            index: 0,
                            isPrimary: false,
                            participantTileBuilder: participantTileBuilder,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  key: const ValueKey<String>('conference-right-rail'),
                  width: 128,
                  child: _ParticipantRail(
                    session: session,
                    participants: railParticipants,
                    participantTileBuilder: participantTileBuilder,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: conferenceControlsBuilder?.call(context, session) ??
              ConferenceControlsRow(controller: controller),
        ),
      ],
    );
  }

  List<CallParticipant> _resolvedParticipants() {
    final fromState = session.conferenceState.participants;
    if (fromState.isNotEmpty) {
      return fromState;
    }
    return [
      CallParticipant(
        participantId: session.callId,
        displayName: session.callData.callerName,
        avatarUrl: session.callData.avatarUrl,
        isVideoOn: session.callData.callType == CallType.video,
      ),
    ];
  }

  CallParticipant _selectPrimaryParticipant(
      List<CallParticipant> participants) {
    if (participants.isEmpty) {
      return CallParticipant(
        participantId: session.callId.isEmpty ? 'unknown-call' : session.callId,
        displayName: session.callData.callerName.isEmpty
            ? 'Unknown'
            : session.callData.callerName,
        avatarUrl: session.callData.avatarUrl,
      );
    }

    final pinnedId = session.conferenceState.pinnedParticipantId;
    if (pinnedId != null) {
      for (final participant in participants) {
        if (participant.participantId == pinnedId) {
          return participant;
        }
      }
    }

    final activeSpeakerId = session.conferenceState.activeSpeakerId;
    if (activeSpeakerId != null) {
      for (final participant in participants) {
        if (participant.participantId == activeSpeakerId) {
          return participant;
        }
      }
    }

    for (final participant in participants) {
      if (!participant.isLocal) {
        return participant;
      }
    }
    return participants.first;
  }
}

class ConferenceControlsRow extends StatelessWidget {
  const ConferenceControlsRow({
    required this.controller,
    super.key,
  });

  final CallScreenController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey<String>('conference-controls-row'),
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        CallActionButton(
          icon: controller.isMuted ? Icons.mic_off : Icons.mic,
          label: 'Mic',
          isActive: controller.isMuted,
          onPressed: controller.toggleMute,
        ),
        CallActionButton(
          icon: controller.isSpeakerOn
              ? Icons.volume_up
              : Icons.volume_up_outlined,
          label: 'Speaker',
          isActive: controller.isSpeakerOn,
          onPressed: controller.toggleSpeaker,
        ),
        if (controller.isVideo)
          CallActionButton(
            icon: controller.isCameraOn ? Icons.videocam : Icons.videocam_off,
            label: 'Cam',
            isActive: controller.isCameraOn,
            onPressed: controller.toggleCamera,
          ),
        CallActionButton(
          icon: Icons.call_end,
          label: 'End',
          isDestructive: true,
          onPressed: controller.endCall,
        ),
      ],
    );
  }
}

class _ParticipantRail extends StatelessWidget {
  const _ParticipantRail({
    required this.session,
    required this.participants,
    this.participantTileBuilder,
  });

  final CallSession session;
  final List<CallParticipant> participants;
  final ParticipantTileBuilder? participantTileBuilder;

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) {
      return const SizedBox.shrink();
    }

    return ListView.separated(
      key: const ValueKey<String>('conference-right-rail-list'),
      itemCount: participants.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final participant = participants[index];
        return SizedBox(
          height: 152,
          child: _ParticipantPanel(
            session: session,
            participant: participant,
            index: index + 1,
            isPrimary: false,
            participantTileBuilder: participantTileBuilder,
          ),
        );
      },
    );
  }
}

class _ParticipantPanel extends StatelessWidget {
  const _ParticipantPanel({
    required this.session,
    required this.participant,
    required this.index,
    required this.isPrimary,
    required this.participantTileBuilder,
    this.title,
    super.key,
  });

  final CallSession session;
  final CallParticipant participant;
  final int index;
  final bool isPrimary;
  final ParticipantTileBuilder? participantTileBuilder;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final theme = CallwaveTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.conferenceTileBorderColor),
        color: theme.conferenceTileColor,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned.fill(
              child: participantTileBuilder?.call(
                    context,
                    session,
                    participant,
                    isPrimary,
                  ) ??
                  _FallbackParticipantSurface(
                    participant: participant,
                    isPrimary: isPrimary,
                  ),
            ),
            if (title != null)
              Positioned(
                top: 10,
                left: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.conferenceBadgeColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(
                      title!,
                      style: theme.conferenceSecondaryLabelStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            if (title == null && index > 0)
              Positioned(
                top: 8,
                left: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.conferenceBadgeColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      '$index',
                      style: theme.conferenceSecondaryLabelStyle,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.conferenceLabelColor,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Text(
                    participant.isLocal ? 'You' : participant.displayName,
                    style: theme.conferencePrimaryLabelStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FallbackParticipantSurface extends StatelessWidget {
  const _FallbackParticipantSurface({
    required this.participant,
    required this.isPrimary,
  });

  final CallParticipant participant;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final initials = getInitials(participant.displayName);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1A6B6B),
            Color(0xFF0D4F4F),
          ],
        ),
      ),
      child: Center(
        child: CircleAvatar(
          radius: isPrimary ? 44 : 28,
          backgroundColor: const Color(0x3326A69A),
          child: Text(
            initials,
            style: TextStyle(
              fontSize: isPrimary ? 26 : 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
