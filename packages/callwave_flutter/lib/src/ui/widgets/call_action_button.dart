import 'package:flutter/material.dart';

import '../theme/call_screen_theme.dart';

/// A circular action button with icon, label, and animated active/inactive
/// state transitions.
class CallActionButton extends StatelessWidget {
  const CallActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isActive = false,
    this.isDestructive = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  /// When `true` the button renders with a white background and dark icon.
  final bool isActive;

  /// When `true` (e.g. End Call) the button uses a red background.
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final double size = isDestructive
        ? CallScreenTheme.endCallButtonSize
        : CallScreenTheme.actionButtonSize;

    final Color background = isDestructive
        ? CallScreenTheme.endCallColor
        : isActive
            ? CallScreenTheme.actionButtonActive
            : CallScreenTheme.actionButtonInactive;

    final Color iconColor = isDestructive
        ? Colors.white
        : isActive
            ? CallScreenTheme.actionIconActive
            : CallScreenTheme.actionIconInactive;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: CallScreenTheme.buttonToggleDuration,
          curve: Curves.easeInOut,
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: background,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(icon, color: iconColor, size: size * 0.4),
            splashRadius: size / 2,
            padding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: CallScreenTheme.buttonLabelStyle),
      ],
    );
  }
}
