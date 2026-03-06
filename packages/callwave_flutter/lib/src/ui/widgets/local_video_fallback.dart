import 'package:flutter/material.dart';

import '../../utils/initials.dart';

/// Fallback surface when local video is off or unavailable.
class LocalVideoFallback extends StatelessWidget {
  const LocalVideoFallback({
    required this.displayName,
    required this.cameraOn,
    super.key,
  });

  final String displayName;
  final bool cameraOn;

  @override
  Widget build(BuildContext context) {
    final initials = getInitials(displayName);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF205656),
            Color(0xFF0E2020),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: Colors.white24,
              child: cameraOn
                  ? Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : const Icon(
                      Icons.videocam_off,
                      color: Colors.white,
                      size: 24,
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              cameraOn ? displayName : 'Camera Off',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
