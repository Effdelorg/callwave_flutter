import 'package:flutter/material.dart';

import '../call_screen_controller.dart';
import 'call_action_button.dart';

/// Composes the bottom action buttons: Mute, Speaker, End Call
/// (+ Camera toggle for video calls).
class CallActionsRow extends StatelessWidget {
  const CallActionsRow({
    required this.controller,
    super.key,
  });

  final CallScreenController controller;

  @override
  Widget build(BuildContext context) {
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
