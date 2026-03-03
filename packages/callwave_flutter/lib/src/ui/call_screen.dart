import 'package:flutter/material.dart';

import '../models/call_data.dart';
import 'call_screen_controller.dart';
import 'theme/call_screen_theme.dart';
import 'widgets/call_actions_row.dart';
import 'widgets/caller_avatar.dart';
import 'widgets/caller_info.dart';

/// Full-screen call UI.
///
/// ```dart
/// Navigator.of(context).push(
///   MaterialPageRoute(
///     builder: (_) => CallScreen(callData: data),
///   ),
/// );
/// ```
class CallScreen extends StatefulWidget {
  const CallScreen({
    required this.callData,
    this.isOutgoing = false,
    this.onCallEnded,
    super.key,
  });

  /// Caller information to display.
  final CallData callData;

  /// When `true` the initial status label shows "Calling..." instead of
  /// "Ringing...".
  final bool isOutgoing;

  /// Invoked after the call ends. If `null` the screen auto-pops after a
  /// brief delay.
  final VoidCallback? onCallEnded;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen>
    with SingleTickerProviderStateMixin {
  late final CallScreenController _controller;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();

    _controller = CallScreenController(
      callId: widget.callData.callId,
      callType: widget.callData.callType,
      isOutgoing: widget.isOutgoing,
    )..addListener(_onControllerChanged);

    _fadeController = AnimationController(
      vsync: this,
      duration: CallScreenTheme.fadeInDuration,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _fadeController.forward();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});

    if (_controller.status == CallStatus.ended && !_dismissed) {
      _dismissed = true;
      Future<void>.delayed(CallScreenTheme.autoDismissDelay, _dismiss);
    }
  }

  void _dismiss() {
    if (!mounted) return;
    if (widget.onCallEnded != null) {
      widget.onCallEnded!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: CallScreenTheme.backgroundGradient,
          ),
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  CallerAvatar(
                    callerName: widget.callData.callerName,
                    avatarUrl: widget.callData.avatarUrl,
                    status: _controller.status,
                  ),
                  const SizedBox(height: 32),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: CallerInfo(
                      callerName: widget.callData.callerName,
                      handle: widget.callData.handle,
                      status: _controller.status,
                      elapsed: _controller.elapsed,
                    ),
                  ),
                  const Spacer(flex: 3),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: CallActionsRow(controller: _controller),
                  ),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
