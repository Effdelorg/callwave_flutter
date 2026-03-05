import 'dart:async';

import 'package:callwave_flutter/callwave_flutter.dart';
import 'package:flutter/material.dart';

import 'example_camera_controller.dart';

class ExampleVideoCallScreen extends StatefulWidget {
  const ExampleVideoCallScreen({
    required this.session,
    required this.cameraController,
    this.onCallEnded,
    super.key,
  });

  final CallSession session;
  final ExampleCameraHandle cameraController;
  final VoidCallback? onCallEnded;

  @override
  State<ExampleVideoCallScreen> createState() => _ExampleVideoCallScreenState();
}

class _ExampleVideoCallScreenState extends State<ExampleVideoCallScreen> {
  bool _dismissed = false;
  bool _sessionBindingReady = false;
  int _bindOperationVersion = 0;
  late bool _lastCameraOn = widget.session.isCameraOn;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSessionChanged);
    widget.cameraController.addListener(_onCameraControllerChanged);
    unawaited(_bindSession());
  }

  @override
  void didUpdateWidget(ExampleVideoCallScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session == widget.session &&
        oldWidget.cameraController == widget.cameraController) {
      return;
    }
    oldWidget.session.removeListener(_onSessionChanged);
    oldWidget.cameraController.removeListener(_onCameraControllerChanged);
    widget.session.addListener(_onSessionChanged);
    widget.cameraController.addListener(_onCameraControllerChanged);
    _bindOperationVersion += 1;
    unawaited(
        oldWidget.cameraController.detachSession(oldWidget.session.callId));
    _lastCameraOn = widget.session.isCameraOn;
    _sessionBindingReady = false;
    unawaited(_bindSession());
  }

  Future<void> _bindSession() async {
    final session = widget.session;
    final cameraController = widget.cameraController;
    final callId = session.callId;
    final operationVersion = ++_bindOperationVersion;
    await cameraController.attachSession(callId);
    if (!_isCurrentBind(
      operationVersion: operationVersion,
      session: session,
      cameraController: cameraController,
    )) {
      unawaited(cameraController.detachSession(callId));
      return;
    }

    if (session.isCameraOn) {
      await session.toggleCamera();
      if (!_isCurrentBind(
        operationVersion: operationVersion,
        session: session,
        cameraController: cameraController,
      )) {
        return;
      }
    }
    _lastCameraOn = session.isCameraOn;
    await cameraController.setCameraEnabled(callId, _lastCameraOn);
    if (_isCurrentBind(
      operationVersion: operationVersion,
      session: session,
      cameraController: cameraController,
    )) {
      setState(() {
        _sessionBindingReady = true;
      });
    }
  }

  bool _isCurrentBind({
    required int operationVersion,
    required CallSession session,
    required ExampleCameraHandle cameraController,
  }) {
    return mounted &&
        operationVersion == _bindOperationVersion &&
        identical(session, widget.session) &&
        identical(cameraController, widget.cameraController);
  }

  void _onSessionChanged() {
    final session = widget.session;
    final nextCameraOn = session.isCameraOn;
    if (nextCameraOn != _lastCameraOn) {
      _lastCameraOn = nextCameraOn;
      unawaited(
        widget.cameraController.setCameraEnabled(session.callId, nextCameraOn),
      );
    }

    if (session.isEnded && !_dismissed) {
      _dismissed = true;
      Future<void>.delayed(const Duration(seconds: 3), _dismiss);
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _onCameraControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _dismiss() {
    if (!mounted) {
      return;
    }
    if (widget.onCallEnded != null) {
      widget.onCallEnded!();
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  @override
  void dispose() {
    final session = widget.session;
    _bindOperationVersion += 1;
    session.removeListener(_onSessionChanged);
    widget.cameraController.removeListener(_onCameraControllerChanged);
    unawaited(widget.cameraController.detachSession(session.callId));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_sessionBindingReady) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.6),
          ),
        ),
      );
    }

    if (widget.session.participantCount > 1) {
      return _buildConferenceCall();
    }
    return _buildOneToOneVideoCall();
  }

  Widget _buildConferenceCall() {
    return CallScreen(
      session: widget.session,
      onCallEnded: _dismiss,
      participantTileBuilder: (context, session, participant, isPrimary) {
        return _ExampleConferenceParticipantTile(
          participant: participant,
          isPrimary: isPrimary,
          shouldShowPreview: _shouldShowPreview,
          previewAspectRatio: widget.cameraController.previewAspectRatio,
          cameraController: widget.cameraController,
          showPermissionCard: participant.isLocal && _shouldShowPermissionCard,
          permissionMessage: _permissionMessage,
          onRetryPermission: () {
            unawaited(widget.cameraController.retryPermission(session.callId));
          },
          onOpenSettings: () {
            unawaited(widget.cameraController.openSystemSettings());
          },
        );
      },
    );
  }

  Widget _buildOneToOneVideoCall() {
    final session = widget.session;
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _shouldShowPreview
                ? _CoverFittedMedia(
                    key: const ValueKey<String>('video-preview-fit-one-to-one'),
                    aspectRatio: widget.cameraController.previewAspectRatio,
                    child: widget.cameraController.buildPreview(
                      key: const ValueKey<String>('video-preview-one-to-one'),
                    ),
                  )
                : _buildFallbackSurface(
                    callerName: session.callData.callerName,
                  ),
          ),
          Positioned.fill(
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
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                children: [
                  _CallHeader(
                    callerName: session.callData.callerName,
                    handle: session.callData.handle,
                    statusLabel: _statusLabel,
                    statusStyle: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  if (_shouldShowPermissionCard)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PermissionCard(
                        message: _permissionMessage,
                        onRetry: () {
                          unawaited(
                            widget.cameraController
                                .retryPermission(session.callId),
                          );
                        },
                        onOpenSettings: () {
                          unawaited(
                              widget.cameraController.openSystemSettings());
                        },
                        showSettingsButton: widget.cameraController.state ==
                            ExampleCameraState.errorPermissionDenied,
                      ),
                    ),
                  _CallControls(
                    session: session,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _shouldShowPreview {
    return widget.session.isCameraOn &&
        widget.cameraController.state == ExampleCameraState.ready &&
        widget.cameraController.isPreviewReady;
  }

  bool get _shouldShowPermissionCard {
    if (!widget.session.isCameraOn) {
      return false;
    }
    final state = widget.cameraController.state;
    return state == ExampleCameraState.errorPermissionDenied ||
        state == ExampleCameraState.errorUnavailable;
  }

  String get _permissionMessage {
    return widget.cameraController.errorMessage ??
        'Camera permission is needed for video preview.';
  }

  String get _statusLabel {
    switch (widget.session.state) {
      case CallSessionState.idle:
      case CallSessionState.ringing:
        return 'Incoming call';
      case CallSessionState.connecting:
      case CallSessionState.reconnecting:
        return 'Connecting...';
      case CallSessionState.connected:
        final elapsed = widget.session.elapsed;
        final minutes =
            elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
        final seconds =
            elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
        return '$minutes:$seconds';
      case CallSessionState.ended:
      case CallSessionState.failed:
        return 'Call ended';
    }
  }

  Widget _buildFallbackSurface({required String callerName}) {
    final trimmed = callerName.trim();
    final initials = trimmed.isEmpty
        ? '?'
        : trimmed
            .split(RegExp(r'\s+'))
            .where((part) => part.isNotEmpty)
            .take(2)
            .map((part) => part[0].toUpperCase())
            .join();
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A6B6B), Color(0xFF0D4F4F)],
        ),
      ),
      child: Center(
        child: CircleAvatar(
          radius: 54,
          backgroundColor: const Color(0x3326A69A),
          child: Text(
            initials,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _CallHeader extends StatelessWidget {
  const _CallHeader({
    required this.callerName,
    required this.handle,
    required this.statusLabel,
    required this.statusStyle,
  });

  final String callerName;
  final String handle;
  final String statusLabel;
  final TextStyle? statusStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          callerName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          handle,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          statusLabel,
          style: statusStyle,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _CallControls extends StatelessWidget {
  const _CallControls({
    required this.session,
  });

  final CallSession session;

  bool get _showIncomingControls {
    return session.state == CallSessionState.idle ||
        session.state == CallSessionState.ringing;
  }

  @override
  Widget build(BuildContext context) {
    if (_showIncomingControls) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RoundActionButton(
            icon: Icons.call_end,
            label: 'Decline',
            backgroundColor: const Color(0xFFB71C1C),
            onPressed: () {
              unawaited(session.decline());
            },
          ),
          _RoundActionButton(
            icon: Icons.call,
            label: 'Accept',
            backgroundColor: const Color(0xFF2E7D32),
            onPressed: () {
              unawaited(session.accept());
            },
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundActionButton(
          icon: session.isMuted ? Icons.mic_off : Icons.mic,
          label: session.isMuted ? 'Unmute' : 'Mute',
          backgroundColor: session.isMuted
              ? const Color(0x331B5E20)
              : const Color(0x33FFFFFF),
          onPressed: () {
            unawaited(session.toggleMute());
          },
        ),
        _RoundActionButton(
          icon:
              session.isSpeakerOn ? Icons.volume_up : Icons.volume_up_outlined,
          label: 'Speaker',
          backgroundColor: session.isSpeakerOn
              ? const Color(0x331565C0)
              : const Color(0x33FFFFFF),
          onPressed: () {
            unawaited(session.toggleSpeaker());
          },
        ),
        _RoundActionButton(
          icon: Icons.call_end,
          label: 'End',
          backgroundColor: const Color(0xFFB71C1C),
          onPressed: () {
            unawaited(session.end());
          },
        ),
        _RoundActionButton(
          icon: session.isCameraOn ? Icons.videocam : Icons.videocam_off,
          label: 'Cam',
          backgroundColor: session.isCameraOn
              ? const Color(0x331E88E5)
              : const Color(0x33FFFFFF),
          onPressed: () {
            unawaited(session.toggleCamera());
          },
        ),
      ],
    );
  }
}

class _RoundActionButton extends StatelessWidget {
  const _RoundActionButton({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkResponse(
          onTap: onPressed,
          radius: 34,
          child: CircleAvatar(
            radius: 28,
            backgroundColor: backgroundColor,
            child: Icon(icon, color: Colors.white),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.message,
    required this.onRetry,
    required this.onOpenSettings,
    required this.showSettingsButton,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;
  final bool showSettingsButton;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                TextButton(
                  onPressed: onRetry,
                  child: const Text('Retry'),
                ),
                if (showSettingsButton)
                  TextButton(
                    onPressed: onOpenSettings,
                    child: const Text('Open Settings'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExampleConferenceParticipantTile extends StatelessWidget {
  const _ExampleConferenceParticipantTile({
    required this.participant,
    required this.isPrimary,
    required this.shouldShowPreview,
    required this.previewAspectRatio,
    required this.cameraController,
    required this.showPermissionCard,
    required this.permissionMessage,
    required this.onRetryPermission,
    required this.onOpenSettings,
  });

  final CallParticipant participant;
  final bool isPrimary;
  final bool shouldShowPreview;
  final double? previewAspectRatio;
  final ExampleCameraHandle cameraController;
  final bool showPermissionCard;
  final String permissionMessage;
  final VoidCallback onRetryPermission;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final shouldShowLocalPreview = shouldShowPreview && participant.isLocal;
    final content = shouldShowLocalPreview
        ? _CoverFittedMedia(
            key: ValueKey<String>(
              'video-preview-fit-conference-${participant.participantId}',
            ),
            aspectRatio: previewAspectRatio,
            child: cameraController.buildPreview(
              key: ValueKey<String>(
                'video-preview-conference-${participant.participantId}',
              ),
            ),
          )
        : _ConferenceFallbackTile(
            label: participant.isLocal ? 'You' : participant.displayName,
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        content,
        if (showPermissionCard)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: _PermissionCard(
                message: permissionMessage,
                onRetry: onRetryPermission,
                onOpenSettings: onOpenSettings,
                showSettingsButton: cameraController.state ==
                    ExampleCameraState.errorPermissionDenied,
              ),
            ),
          ),
      ],
    );
  }
}

class _ConferenceFallbackTile extends StatelessWidget {
  const _ConferenceFallbackTile({
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    final trimmed = label.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed.substring(0, 1);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A6B6B), Color(0xFF0D4F4F)],
        ),
      ),
      child: Center(
        child: CircleAvatar(
          radius: 24,
          backgroundColor: const Color(0x3326A69A),
          child: Text(
            initial.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _CoverFittedMedia extends StatelessWidget {
  const _CoverFittedMedia({
    required this.child,
    this.aspectRatio,
    super.key,
  });

  final Widget child;
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
          return child;
        }
        final resolvedAspectRatio = _resolveAspectRatio(width, height);
        final frame = _containFrame(
          boxWidth: width,
          boxHeight: height,
          aspectRatio: resolvedAspectRatio,
        );
        return ColoredBox(
          color: Colors.black,
          child: Center(
            child: SizedBox(
              width: frame.width,
              height: frame.height,
              child: child,
            ),
          ),
        );
      },
    );
  }

  double _resolveAspectRatio(double width, double height) {
    final ratio = aspectRatio;
    if (ratio != null && ratio.isFinite && ratio > 0) {
      return ratio;
    }
    return width / height;
  }

  Size _containFrame({
    required double boxWidth,
    required double boxHeight,
    required double aspectRatio,
  }) {
    final boxRatio = boxWidth / boxHeight;
    if (boxRatio < aspectRatio) {
      return Size(boxWidth, boxWidth / aspectRatio);
    }
    return Size(boxHeight * aspectRatio, boxHeight);
  }
}
