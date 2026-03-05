import 'dart:async';
import 'dart:math' as math;

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
  late CallScreenController _callScreenController;

  @override
  void initState() {
    super.initState();
    _callScreenController = CallScreenController(session: widget.session);
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
    if (oldWidget.session != widget.session) {
      _callScreenController.dispose();
      _callScreenController = CallScreenController(session: widget.session);
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
    _callScreenController.dispose();
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
    final isIncoming = session.state == CallSessionState.idle ||
        session.state == CallSessionState.ringing;
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
          if (isIncoming)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: _IncomingPulseAvatar(
                    callerName: session.callData.callerName,
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
                  CallActionsRow(controller: _callScreenController),
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
    final initials = getInitials(callerName);
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

class _IncomingPulseAvatar extends StatefulWidget {
  const _IncomingPulseAvatar({
    required this.callerName,
  });

  final String callerName;

  @override
  State<_IncomingPulseAvatar> createState() => _IncomingPulseAvatarState();
}

class _IncomingPulseAvatarState extends State<_IncomingPulseAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const avatarRadius = 56.0;
    return SizedBox(
      width: avatarRadius * 3.6,
      height: avatarRadius * 3.6,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return CustomPaint(
            painter: _PulseRingPainter(
              progress: _pulseController.value,
              color: const Color(0x4D26A69A),
              avatarRadius: avatarRadius,
            ),
            child: child,
          );
        },
        child: Center(
          child: CircleAvatar(
            radius: avatarRadius,
            backgroundColor: const Color(0xFF1A6B6B),
            child: Text(
              getInitials(widget.callerName),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PulseRingPainter extends CustomPainter {
  _PulseRingPainter({
    required this.progress,
    required this.color,
    required this.avatarRadius,
  });

  final double progress;
  final Color color;
  final double avatarRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) / 2;
    for (int i = 0; i < 3; i++) {
      final phase = (progress + i / 3) % 1.0;
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
  bool shouldRepaint(_PulseRingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
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
    final initial = getInitials(label);
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
            initial,
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
