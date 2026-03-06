import 'package:flutter/material.dart';

import '../theme/call_screen_theme.dart';

/// Shared atmospheric backdrop for connected 1:1 video layouts.
class OneToOneStageBackground extends StatelessWidget {
  const OneToOneStageBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: CallScreenTheme.oneToOneStageBackgroundGradient,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: const [
          Positioned(
            left: -120,
            top: -150,
            width: 360,
            height: 360,
            child: _StageAura(
              color: CallScreenTheme.oneToOneStageAuraPrimary,
            ),
          ),
          Positioned(
            right: -160,
            top: 220,
            width: 420,
            height: 420,
            child: _StageAura(
              color: CallScreenTheme.oneToOneStageAuraSecondary,
            ),
          ),
          Positioned(
            left: -100,
            bottom: -150,
            width: 320,
            height: 320,
            child: _StageAura(
              color: CallScreenTheme.oneToOneStageAuraTertiary,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x15000000),
                    Colors.transparent,
                    Color(0x33000000),
                  ],
                  stops: [0.0, 0.56, 1.0],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StageAura extends StatelessWidget {
  const _StageAura({
    required this.color,
  });

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color,
            color.withValues(alpha: 0.2),
            Colors.transparent,
          ],
          stops: const [0.0, 0.48, 1.0],
        ),
      ),
    );
  }
}
