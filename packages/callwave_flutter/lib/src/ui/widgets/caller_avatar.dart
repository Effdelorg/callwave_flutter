import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/initials.dart';
import '../call_screen_controller.dart';
import '../theme/call_screen_theme.dart';

/// Displays the caller's avatar with animated pulsing rings during
/// [CallStatus.ringing] and [CallStatus.connecting].
class CallerAvatar extends StatefulWidget {
  const CallerAvatar({
    required this.callerName,
    required this.status,
    this.avatarUrl,
    super.key,
  });

  final String callerName;
  final String? avatarUrl;
  final CallStatus status;

  @override
  State<CallerAvatar> createState() => _CallerAvatarState();
}

class _CallerAvatarState extends State<CallerAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  bool get _shouldPulse =>
      widget.status == CallStatus.ringing ||
      widget.status == CallStatus.connecting;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: CallScreenTheme.pulseAnimationDuration,
    );
    if (_shouldPulse) _pulseController.repeat();
  }

  @override
  void didUpdateWidget(CallerAvatar old) {
    super.didUpdateWidget(old);
    if (_shouldPulse && !_pulseController.isAnimating) {
      _pulseController.repeat();
    } else if (!_shouldPulse && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double r = CallScreenTheme.avatarRadius;
    return SizedBox(
      width: r * 3.6,
      height: r * 3.6,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return CustomPaint(
            painter: _PulseRingPainter(
              progress: _pulseController.value,
              animate: _shouldPulse,
              color: CallScreenTheme.pulseRingColor,
              avatarRadius: r,
            ),
            child: child,
          );
        },
        child: Center(child: _avatar()),
      ),
    );
  }

  Widget _avatar() {
    const double r = CallScreenTheme.avatarRadius;
    final url = widget.avatarUrl;

    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
        radius: r,
        backgroundColor: CallScreenTheme.avatarBackground,
        backgroundImage: NetworkImage(url),
        onBackgroundImageError: (_, __) {},
        child: Text(
          _initials(),
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: r,
      backgroundColor: CallScreenTheme.avatarBackground,
      child: Text(
        _initials(),
        style: const TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }

  String _initials() => getInitials(widget.callerName);
}

class _PulseRingPainter extends CustomPainter {
  _PulseRingPainter({
    required this.progress,
    required this.animate,
    required this.color,
    required this.avatarRadius,
  });

  final double progress;
  final bool animate;
  final Color color;
  final double avatarRadius;

  static const int _ringCount = 3;

  @override
  void paint(Canvas canvas, Size size) {
    if (!animate) return;

    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) / 2;

    for (int i = 0; i < _ringCount; i++) {
      final phase = (progress + i / _ringCount) % 1.0;
      final radius = avatarRadius + (maxRadius - avatarRadius) * phase;
      final opacity = (1.0 - phase).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = color.withValues(alpha: opacity * 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_PulseRingPainter old) =>
      old.progress != progress || old.animate != animate;
}
