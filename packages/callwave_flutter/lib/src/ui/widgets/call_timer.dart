import 'package:flutter/material.dart';

import '../theme/call_screen_theme.dart';

/// Renders an elapsed duration in HH:MM:SS (or MM:SS when under 1 hour).
class CallTimer extends StatelessWidget {
  const CallTimer({required this.elapsed, super.key});

  final Duration elapsed;

  @override
  Widget build(BuildContext context) {
    return Text(_format(elapsed), style: CallScreenTheme.timerStyle);
  }

  String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }
}
