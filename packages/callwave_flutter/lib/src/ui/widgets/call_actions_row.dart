import 'package:flutter/material.dart';

import '../call_screen_controller.dart';
import '../theme/call_screen_theme.dart';
import 'call_action_button.dart';

/// Composes call actions for both incoming (Accept/Decline) and active call
/// states (Mute/Speaker/End + Camera for video).
class CallActionsRow extends StatelessWidget {
  const CallActionsRow({
    required this.controller,
    super.key,
  });

  final CallScreenController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.status == CallStatus.ringing) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          CallActionButton(
            icon: Icons.call_end,
            label: 'Decline',
            isDestructive: true,
            onPressed: controller.declineCall,
          ),
          CallActionButton(
            icon: Icons.call,
            label: 'Accept',
            backgroundColor: CallScreenTheme.acceptCallColor,
            iconColor: CallScreenTheme.acceptCallIconColor,
            isWiggling: true,
            onPressed: controller.acceptCall,
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        CallActionButton(
          icon: controller.isMuted ? Icons.mic_off : Icons.mic,
          label: controller.isMuted ? 'Unmute' : 'Mute',
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
        CallActionButton(
          icon: Icons.call_end,
          label: 'End',
          isDestructive: true,
          onPressed: controller.endCall,
        ),
        if (controller.isVideo)
          CallActionButton(
            icon: Icons.videocam,
            label: 'Camera',
            onPressed: () {}, // placeholder for camera toggle
          ),
      ],
    );
  }
}
