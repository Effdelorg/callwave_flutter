import 'dart:math' as math;

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
    this.backgroundColor,
    this.iconColor,
    this.isWiggling = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  /// When `true` the button renders with a white background and dark icon.
  final bool isActive;

  /// When `true` (e.g. End Call) the button uses a red background.
  final bool isDestructive;

  /// Overrides the default background color. If `null`, uses theme defaults.
  final Color? backgroundColor;

  /// Overrides the default icon color. If `null`, uses theme defaults.
  final Color? iconColor;

  /// When `true`, plays a wiggle animation on the icon (e.g. for incoming
  /// Accept button).
  final bool isWiggling;

  @override
  Widget build(BuildContext context) {
    final double size = CallScreenTheme.actionButtonSize;

    final Color background = backgroundColor ??
        (isDestructive
            ? CallScreenTheme.endCallColor
            : isActive
                ? CallScreenTheme.actionButtonActive
                : CallScreenTheme.actionButtonInactive);

    final Color resolvedIconColor = iconColor ??
        (isDestructive
            ? Colors.white
            : isActive
                ? CallScreenTheme.actionIconActive
                : CallScreenTheme.actionIconInactive);

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
            icon: _AnimatedActionIcon(
              icon: icon,
              color: resolvedIconColor,
              size: size * 0.4,
              isWiggling: isWiggling,
            ),
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

class _AnimatedActionIcon extends StatefulWidget {
  const _AnimatedActionIcon({
    required this.icon,
    required this.color,
    required this.size,
    required this.isWiggling,
  });

  final IconData icon;
  final Color color;
  final double size;
  final bool isWiggling;

  @override
  State<_AnimatedActionIcon> createState() => _AnimatedActionIconState();
}

class _AnimatedActionIconState extends State<_AnimatedActionIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: CallScreenTheme.acceptCallWiggleDuration,
  );

  @override
  void initState() {
    super.initState();
    _syncWiggleAnimation();
  }

  @override
  void didUpdateWidget(covariant _AnimatedActionIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncWiggleAnimation();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncWiggleAnimation() {
    if (widget.isWiggling) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
      return;
    }
    _controller
      ..stop()
      ..value = 0;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isWiggling) {
      return Icon(widget.icon, color: widget.color, size: widget.size);
    }

    return AnimatedBuilder(
      animation: _controller,
      child: Icon(widget.icon, color: widget.color, size: widget.size),
      builder: (context, child) {
        final angle = math.sin(_controller.value * math.pi) *
            CallScreenTheme.acceptCallWiggleRadians;
        return Transform.rotate(
          angle: angle,
          child: child,
        );
      },
    );
  }
}
