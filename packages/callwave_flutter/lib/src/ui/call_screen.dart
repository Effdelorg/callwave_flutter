import 'package:flutter/material.dart';

import '../engine/call_session.dart';
import '../models/call_data.dart';
import 'call_screen_builders.dart';
import 'call_screen_controller.dart';
import 'theme/callwave_theme.dart';
import 'theme/call_screen_theme.dart';
import 'theme/callwave_theme_data.dart';
import 'widgets/call_actions_row.dart';
import 'widgets/conference_call_view.dart';
import 'widgets/caller_avatar.dart';
import 'widgets/caller_info.dart';

/// Full-screen call UI.
///
/// ```dart
/// Navigator.of(context).push(
///   MaterialPageRoute(
///     builder: (_) => CallScreen(session: session),
///   ),
/// );
/// ```
class CallScreen extends StatefulWidget {
  const CallScreen({
    required this.session,
    this.onCallEnded,
    this.conferenceScreenBuilder,
    this.participantTileBuilder,
    this.conferenceControlsBuilder,
    this.theme,
    super.key,
  });

  /// Session that owns this call screen.
  final CallSession session;

  /// Invoked after the call ends. If `null` the screen auto-pops after a
  /// brief delay when a previous route exists.
  final VoidCallback? onCallEnded;
  final ConferenceScreenBuilder? conferenceScreenBuilder;
  final ParticipantTileBuilder? participantTileBuilder;
  final ConferenceControlsBuilder? conferenceControlsBuilder;
  final CallwaveThemeData? theme;

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
      session: widget.session,
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
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop();
      }
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
    final displayData = widget.session.callData;
    final themeData = widget.theme ??
        CallwaveTheme.maybeOf(context) ??
        const CallwaveThemeData();
    final isConference = widget.session.participantCount > 1;
    final conferenceScreenBuilder = widget.conferenceScreenBuilder;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: themeData.backgroundGradient,
          ),
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: isConference
                ? (conferenceScreenBuilder != null
                    ? conferenceScreenBuilder(context, widget.session)
                    : SafeArea(
                        child: ConferenceCallView(
                          session: widget.session,
                          controller: _controller,
                          participantTileBuilder: widget.participantTileBuilder,
                          conferenceControlsBuilder:
                              widget.conferenceControlsBuilder,
                        ),
                      ))
                : SafeArea(
                    child: _controller.isVideo
                        ? _buildOneToOneVideoView(displayData)
                        : _buildOneToOneAudioView(displayData),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildOneToOneAudioView(CallData displayData) {
    return Column(
      children: [
        const Spacer(flex: 2),
        CallerAvatar(
          callerName: displayData.callerName,
          avatarUrl: displayData.avatarUrl,
          status: _controller.status,
        ),
        const SizedBox(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: CallerInfo(
            callerName: displayData.callerName,
            handle: displayData.handle,
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
    );
  }

  Widget _buildOneToOneVideoView(CallData displayData) {
    return Stack(
      key: const ValueKey<String>('one-to-one-video-view'),
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.92),
                  Colors.black.withValues(alpha: 0.8),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Center(
            child: CallerAvatar(
              callerName: displayData.callerName,
              avatarUrl: displayData.avatarUrl,
              status: _controller.status,
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.62),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.58),
                ],
                stops: const [0.0, 0.42, 1.0],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: CallerInfo(
                  callerName: displayData.callerName,
                  handle: displayData.handle,
                  status: _controller.status,
                  elapsed: _controller.elapsed,
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: CallActionsRow(controller: _controller),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }
}
