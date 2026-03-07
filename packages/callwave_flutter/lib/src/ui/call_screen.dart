import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/call_session.dart';
import '../models/call_data.dart';
import '../models/call_data_extra_keys.dart';
import 'call_screen_builders.dart';
import 'call_screen_controller.dart';
import 'theme/callwave_theme.dart';
import 'theme/call_screen_theme.dart';
import 'theme/callwave_theme_data.dart';
import 'widgets/call_actions_row.dart';
import 'widgets/caller_avatar.dart';
import 'widgets/caller_info.dart';
import 'widgets/conference_call_view.dart';
import 'widgets/local_video_fallback.dart';
import 'widgets/one_to_one_stage_background.dart';
import 'widgets/video_panel.dart';
import 'widgets/video_viewport.dart';

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
    this.oneToOneRemoteVideoBuilder,
    this.oneToOneLocalVideoBuilder,
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
  final OneToOneRemoteVideoBuilder? oneToOneRemoteVideoBuilder;
  final OneToOneLocalVideoBuilder? oneToOneLocalVideoBuilder;
  final ParticipantTileBuilder? participantTileBuilder;
  final ConferenceControlsBuilder? conferenceControlsBuilder;
  final CallwaveThemeData? theme;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

enum _OneToOneVideoLayoutMode { split, pip }

enum _OneToOneVideoSource { remote, local }

class _CallScreenState extends State<CallScreen>
    with SingleTickerProviderStateMixin {
  late CallScreenController _controller;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  bool _dismissed = false;
  _OneToOneVideoLayoutMode _oneToOneVideoLayoutMode =
      _OneToOneVideoLayoutMode.split;
  _OneToOneVideoSource _oneToOnePrimarySource = _OneToOneVideoSource.remote;

  @override
  void initState() {
    super.initState();

    _bindController();

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

  void _bindController() {
    _controller = CallScreenController(
      session: widget.session,
    )..addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant CallScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session == widget.session) {
      return;
    }
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    _bindController();
    _dismissed = false;
    _resetOneToOneLayout();
  }

  void _resetOneToOneLayout() {
    _oneToOneVideoLayoutMode = _OneToOneVideoLayoutMode.split;
    _oneToOnePrimarySource = _OneToOneVideoSource.remote;
  }

  void _onControllerChanged() {
    if (!mounted) return;

    if (_controller.status != CallStatus.connected &&
        _oneToOneVideoLayoutMode != _OneToOneVideoLayoutMode.split) {
      _resetOneToOneLayout();
    }
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
            statusText: _controller.statusText,
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
    if (_controller.status != CallStatus.connected) {
      return _buildOneToOnePreConnectedVideoView(displayData);
    }
    return Stack(
      key: const ValueKey<String>('one-to-one-video-view'),
      children: [
        const Positioned.fill(child: OneToOneStageBackground()),
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: CallScreenTheme.oneToOneLayoutSwitchDuration,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _oneToOneVideoLayoutMode == _OneToOneVideoLayoutMode.split
                ? _buildConnectedOneToOneSplitView(displayData)
                : _buildConnectedOneToOnePipView(displayData),
          ),
        ),
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: CallScreenTheme.oneToOneConnectedOverlayGradient,
              ),
            ),
          ),
        ),
        _buildConnectedVideoChrome(displayData),
      ],
    );
  }

  Widget _buildOneToOnePreConnectedVideoView(CallData displayData) {
    return Stack(
      key: const ValueKey<String>('one-to-one-video-view'),
      children: [
        Positioned.fill(
          child: VideoPanel(
            borderRadius: BorderRadius.zero,
            child: _buildOneToOneVideoSurface(
              surface: _resolveVideoSource(
                source: _OneToOneVideoSource.remote,
                displayData: displayData,
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.56),
                    Colors.black.withValues(alpha: 0.2),
                    Colors.black.withValues(alpha: 0.68),
                  ],
                  stops: const [0.0, 0.46, 1.0],
                ),
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
                  statusText: _controller.statusText,
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

  Widget _buildConnectedOneToOneSplitView(CallData displayData) {
    final remote = _resolveVideoSource(
      source: _OneToOneVideoSource.remote,
      displayData: displayData,
    );
    final local = _resolveVideoSource(
      source: _OneToOneVideoSource.local,
      displayData: displayData,
    );
    return LayoutBuilder(
      key: const ValueKey<String>('one-to-one-video-split-view'),
      builder: (context, constraints) {
        final stageInsets = _oneToOneStageInsets;
        final stageWidth = math.max(
          0.0,
          constraints.maxWidth - stageInsets.horizontal,
        );
        final stageHeight = math.max(
          0.0,
          constraints.maxHeight - stageInsets.vertical,
        );
        final squareSize = CallScreenTheme.oneToOneSplitSquareSizeFor(
          stageWidth: stageWidth,
          stageHeight: stageHeight,
        );
        if (squareSize <= 0) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: stageInsets,
          child: Center(
            child: SizedBox(
              width: squareSize,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: squareSize,
                    child: GestureDetector(
                      key: const ValueKey<String>(
                        'one-to-one-video-split-remote-tap',
                      ),
                      onTap: () => _promoteToPip(_OneToOneVideoSource.remote),
                      child: _buildOneToOneVideoSurface(
                        key: const ValueKey<String>(
                          'one-to-one-video-split-remote-surface',
                        ),
                        surface: remote,
                      ),
                    ),
                  ),
                  const SizedBox(height: CallScreenTheme.oneToOneSplitGap),
                  SizedBox.square(
                    dimension: squareSize,
                    child: GestureDetector(
                      key: const ValueKey<String>(
                        'one-to-one-video-split-local-tap',
                      ),
                      onTap: () => _promoteToPip(_OneToOneVideoSource.local),
                      child: _buildOneToOneVideoSurface(
                        key: const ValueKey<String>(
                          'one-to-one-video-split-local-surface',
                        ),
                        surface: local,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildConnectedOneToOnePipView(CallData displayData) {
    final primary = _oneToOnePrimarySource;
    final secondary = primary == _OneToOneVideoSource.remote
        ? _OneToOneVideoSource.local
        : _OneToOneVideoSource.remote;
    final primarySurface = _resolveVideoSource(
      source: primary,
      displayData: displayData,
    );
    final secondarySurface = _resolveVideoSource(
      source: secondary,
      displayData: displayData,
    );
    return LayoutBuilder(
      key: const ValueKey<String>('one-to-one-video-pip-view'),
      builder: (context, constraints) {
        final stageInsets = _oneToOnePipStageInsets;
        final stageWidth = math.max(
          0.0,
          constraints.maxWidth - stageInsets.horizontal,
        );
        final stageHeight = math.max(
          0.0,
          constraints.maxHeight - stageInsets.vertical,
        );
        final primaryLeadingInset =
            CallScreenTheme.oneToOnePipPrimaryLeadingInset;
        final detachedGap = CallScreenTheme.oneToOnePipDetachedGap;
        final primarySize =
            CallScreenTheme.oneToOnePrimarySquareSizeForDetachedPip(
          stageWidth: stageWidth,
          stageHeight: stageHeight,
          primaryLeadingInset: primaryLeadingInset,
          detachedGap: detachedGap,
        );
        if (primarySize <= 0) {
          return const SizedBox.shrink();
        }
        final pipSize = CallScreenTheme.oneToOnePipSquareSizeFor(primarySize);
        final footprintWidth = math.max(
          primaryLeadingInset + primarySize,
          pipSize,
        );
        final footprintHeight = primarySize + detachedGap + pipSize;
        return Padding(
          padding: stageInsets,
          child: Align(
            alignment: Alignment.bottomRight,
            child: SizedBox(
              key: const ValueKey<String>('one-to-one-video-pip-cluster'),
              width: footprintWidth,
              height: footprintHeight,
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: primaryLeadingInset,
                    width: primarySize,
                    height: primarySize,
                    child: GestureDetector(
                      key: const ValueKey<String>(
                        'one-to-one-video-primary-tap-target',
                      ),
                      onTap: _returnToSplit,
                      child: _buildOneToOneVideoSurface(
                        key: const ValueKey<String>(
                          'one-to-one-video-primary-surface',
                        ),
                        surface: primarySurface,
                      ),
                    ),
                  ),
                  if (pipSize > 0)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      width: pipSize,
                      height: pipSize,
                      child: GestureDetector(
                        key: const ValueKey<String>(
                          'one-to-one-video-pip-tap-target',
                        ),
                        onTap: _swapPrimarySource,
                        child: _buildOneToOneVideoSurface(
                          key: const ValueKey<String>(
                            'one-to-one-video-pip-surface',
                          ),
                          borderRadius: BorderRadius.circular(
                            CallScreenTheme.oneToOnePipBorderRadius,
                          ),
                          surface: secondarySurface,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  EdgeInsets get _oneToOnePipStageInsets {
    return const EdgeInsets.fromLTRB(
      CallScreenTheme.oneToOnePipStageHorizontalPadding,
      CallScreenTheme.oneToOnePipStageTopPadding,
      CallScreenTheme.oneToOnePipStageHorizontalPadding,
      CallScreenTheme.oneToOnePipStageBottomPadding,
    );
  }

  EdgeInsets get _oneToOneStageInsets {
    return const EdgeInsets.fromLTRB(
      CallScreenTheme.oneToOneStageHorizontalPadding,
      CallScreenTheme.oneToOneStageTopPadding,
      CallScreenTheme.oneToOneStageHorizontalPadding,
      CallScreenTheme.oneToOneStageBottomPadding,
    );
  }

  Widget _buildOneToOneVideoSurface({
    required _OneToOneSurface surface,
    Key? key,
    BorderRadius? borderRadius,
  }) {
    final content = surface.isCustomBuilder
        ? VideoViewport(
            aspectRatio: CallScreenTheme.oneToOneMediaAspectRatio,
            fit: BoxFit.cover,
            backgroundColor: CallScreenTheme.oneToOneTileMatteColor,
            child: surface.widget,
          )
        : surface.widget;
    final resolvedBorderRadius = borderRadius ??
        BorderRadius.circular(CallScreenTheme.oneToOneDefaultBorderRadius);
    return VideoPanel(
      key: key,
      borderRadius: resolvedBorderRadius,
      child: content,
    );
  }

  Widget _buildConnectedVideoChrome(CallData displayData) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: CallerInfo(
                callerName: displayData.callerName,
                handle: displayData.handle,
                status: _controller.status,
                statusText: _controller.statusText,
                elapsed: _controller.elapsed,
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ConferenceControlsRow(controller: _controller),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _promoteToPip(_OneToOneVideoSource source) {
    if (_oneToOneVideoLayoutMode == _OneToOneVideoLayoutMode.pip &&
        _oneToOnePrimarySource == source) {
      return;
    }
    setState(() {
      _oneToOnePrimarySource = source;
      _oneToOneVideoLayoutMode = _OneToOneVideoLayoutMode.pip;
    });
  }

  void _swapPrimarySource() {
    setState(() {
      _oneToOnePrimarySource =
          _oneToOnePrimarySource == _OneToOneVideoSource.remote
              ? _OneToOneVideoSource.local
              : _OneToOneVideoSource.remote;
    });
  }

  void _returnToSplit() {
    setState(_resetOneToOneLayout);
  }

  _OneToOneSurface _resolveVideoSource({
    required _OneToOneVideoSource source,
    required CallData displayData,
  }) {
    switch (source) {
      case _OneToOneVideoSource.remote:
        final remoteBuilder = widget.oneToOneRemoteVideoBuilder;
        if (remoteBuilder != null) {
          return _OneToOneSurface(
            widget: remoteBuilder(context, widget.session),
            isCustomBuilder: true,
          );
        }
        return _OneToOneSurface(
          widget: _buildRemoteFallback(displayData),
          isCustomBuilder: false,
        );
      case _OneToOneVideoSource.local:
        final localBuilder = widget.oneToOneLocalVideoBuilder;
        if (localBuilder != null) {
          return _OneToOneSurface(
            widget: localBuilder(context, widget.session),
            isCustomBuilder: true,
          );
        }
        return _OneToOneSurface(
          widget: _buildLocalFallback(),
          isCustomBuilder: false,
        );
    }
  }

  Widget _buildRemoteFallback(CallData displayData) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF174747),
            Color(0xFF0C1818),
          ],
        ),
      ),
      child: Center(
        child: CallerAvatar(
          callerName: displayData.callerName,
          avatarUrl: displayData.avatarUrl,
          status: _controller.status,
        ),
      ),
    );
  }

  Widget _buildLocalFallback() {
    final localNameRaw =
        widget.session.callData.extra?[CallDataExtraKeys.localDisplayName];
    // Accept only non-empty strings; any other type safely falls back to "You".
    final localName = switch (localNameRaw) {
      final String name when name.trim().isNotEmpty => name,
      _ => 'You',
    };
    return LocalVideoFallback(
      displayName: localName,
      cameraOn: _controller.isCameraOn,
    );
  }
}

class _OneToOneSurface {
  const _OneToOneSurface({
    required this.widget,
    required this.isCustomBuilder,
  });

  final Widget widget;
  final bool isCustomBuilder;
}
