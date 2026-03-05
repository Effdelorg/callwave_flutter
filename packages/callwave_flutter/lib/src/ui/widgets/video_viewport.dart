import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A media viewport that preserves source geometry and applies fit behavior.
///
/// This widget is useful when rendering RTC/camera surfaces inside fixed-shape
/// containers (for example square split/PiP call tiles).
class VideoViewport extends StatelessWidget {
  const VideoViewport({
    required this.child,
    this.aspectRatio,
    this.fit = BoxFit.cover,
    this.backgroundColor = Colors.black,
    super.key,
  });

  /// Media widget to render (for example an RTC or camera preview view).
  final Widget child;

  /// Source aspect ratio as `width / height`. When omitted, the viewport ratio
  /// is used and the child is shown without distortion by shape.
  final double? aspectRatio;

  /// Fit mode for the media frame within available space.
  final BoxFit fit;

  /// Matte color shown behind/around the media frame.
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.maxWidth;
        final boxHeight = constraints.maxHeight;
        if (!boxWidth.isFinite || !boxHeight.isFinite) {
          return ColoredBox(
            color: backgroundColor,
            child: const SizedBox.shrink(),
          );
        }
        if (boxWidth <= 0 || boxHeight <= 0) {
          return const SizedBox.shrink();
        }

        final resolvedAspectRatio = _resolveAspectRatio(
          boxWidth: boxWidth,
          boxHeight: boxHeight,
        );
        final frame = _fittedFrame(
          boxWidth: boxWidth,
          boxHeight: boxHeight,
          sourceAspectRatio: resolvedAspectRatio,
          fit: fit,
        );

        return ColoredBox(
          color: backgroundColor,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.center,
              minWidth: frame.width,
              maxWidth: frame.width,
              minHeight: frame.height,
              maxHeight: frame.height,
              child: SizedBox(
                width: frame.width,
                height: frame.height,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }

  double _resolveAspectRatio({
    required double boxWidth,
    required double boxHeight,
  }) {
    final ratio = aspectRatio;
    if (ratio != null && ratio.isFinite && ratio > 0) {
      return ratio;
    }
    return boxWidth / boxHeight;
  }

  Size _fittedFrame({
    required double boxWidth,
    required double boxHeight,
    required double sourceAspectRatio,
    required BoxFit fit,
  }) {
    final boxRatio = boxWidth / boxHeight;
    switch (fit) {
      case BoxFit.fill:
        return Size(boxWidth, boxHeight);
      case BoxFit.fitWidth:
        return Size(boxWidth, boxWidth / sourceAspectRatio);
      case BoxFit.fitHeight:
        return Size(boxHeight * sourceAspectRatio, boxHeight);
      case BoxFit.contain:
      case BoxFit.scaleDown:
        if (boxRatio < sourceAspectRatio) {
          return Size(boxWidth, boxWidth / sourceAspectRatio);
        }
        return Size(boxHeight * sourceAspectRatio, boxHeight);
      case BoxFit.none:
        final width = math.min(boxWidth, boxHeight * sourceAspectRatio);
        final height = math.min(boxHeight, boxWidth / sourceAspectRatio);
        return Size(width, height);
      case BoxFit.cover:
        if (boxRatio > sourceAspectRatio) {
          return Size(boxWidth, boxWidth / sourceAspectRatio);
        }
        return Size(boxHeight * sourceAspectRatio, boxHeight);
    }
  }
}
