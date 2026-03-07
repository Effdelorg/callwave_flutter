import 'package:flutter/material.dart';

import '../call_screen_controller.dart';
import '../theme/call_screen_theme.dart';
import 'call_timer.dart';

/// Displays caller name, phone handle, and a status / timer label with
/// an animated crossfade between status values.
class CallerInfo extends StatelessWidget {
  const CallerInfo({
    required this.callerName,
    required this.handle,
    required this.status,
    required this.statusText,
    required this.elapsed,
    super.key,
  });

  final String callerName;
  final String handle;
  final CallStatus status;
  final String statusText;
  final Duration elapsed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          callerName,
          style: CallScreenTheme.callerNameStyle,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Text(
          handle,
          style: CallScreenTheme.handleStyle,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: CallScreenTheme.statusCrossfadeDuration,
          child: status == CallStatus.connected
              ? CallTimer(key: const ValueKey('timer'), elapsed: elapsed)
              : Text(
                  statusText,
                  key: ValueKey(status),
                  style: CallScreenTheme.statusStyle,
                ),
        ),
      ],
    );
  }
}
