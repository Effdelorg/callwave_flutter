import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Visual constants for the call screen UI.
abstract final class CallScreenTheme {
  // ── Gradient ──────────────────────────────────────────────────────────
  static const Color gradientTop = Color(0xFF0D4F4F);
  static const Color gradientBottom = Color(0xFF0A0E0E);

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [gradientTop, gradientBottom],
  );

  // ── Avatar ────────────────────────────────────────────────────────────
  static const double avatarRadius = 56.0;
  static const Color avatarBackground = Color(0xFF1A6B6B);
  static const Color pulseRingColor = Color(0x4D26A69A);

  // ── Text styles ───────────────────────────────────────────────────────
  static const TextStyle callerNameStyle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    letterSpacing: 0.3,
  );

  static const TextStyle handleStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: Color(0xBBFFFFFF),
  );

  static const TextStyle statusStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: Color(0xFF4DB6AC),
  );

  static const TextStyle timerStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    color: Colors.white,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle buttonLabelStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: Color(0xCCFFFFFF),
  );

  // ── Action buttons ────────────────────────────────────────────────────
  static const double actionButtonSize = 72.0;
  static const Color actionButtonInactive = Color(0x33FFFFFF);
  static const Color actionButtonActive = Colors.white;
  static const Color actionIconInactive = Colors.white;
  static const Color actionIconActive = Color(0xFF0D4F4F);

  /// Green background for the Accept call button.
  static const Color acceptCallColor = Color(0xFF2E7D32);

  /// Icon color for the Accept call button.
  static const Color acceptCallIconColor = Colors.white;

  /// Red background for End/Decline call actions.
  static const Color endCallColor = Color(0xFFD32F2F);

  /// Maximum rotation angle (radians) for the accept button wiggle animation.
  static const double acceptCallWiggleRadians = 0.22;

  /// Duration of one wiggle cycle for the accept button.
  static const Duration acceptCallWiggleDuration = Duration(milliseconds: 380);

  // ── One-to-one video layout ────────────────────────────────────────────
  static const LinearGradient oneToOneStageBackgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF106361),
      Color(0xFF0A2C2C),
      Color(0xFF071112),
    ],
    stops: [0.0, 0.48, 1.0],
  );
  static const Color oneToOneStageAuraPrimary = Color(0x6B3AD5C4);
  static const Color oneToOneStageAuraSecondary = Color(0x4D1D7F74);
  static const Color oneToOneStageAuraTertiary = Color(0x3D2AB3A5);
  static const LinearGradient oneToOneConnectedOverlayGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x2A061B1A),
      Colors.transparent,
      Color(0x4A041111),
    ],
    stops: [0.0, 0.44, 1.0],
  );
  static const Color oneToOneTileMatteColor = Color(0xFF102221);
  static const double oneToOneStageHorizontalPadding = 20.0;
  static const double oneToOneStageTopPadding = 100.0;
  static const double oneToOneStageBottomPadding = 172.0;
  static const double oneToOneSplitGap = 14.0;
  static const double oneToOneSplitSquareMinSize = 116.0;
  static const double oneToOneSplitSquareMaxSize = 348.0;
  static const double oneToOnePrimarySquareMinSize = 188.0;
  static const double oneToOnePrimarySquareMaxSize = 376.0;
  static const double oneToOnePrimarySquareMaxSizePip = double.infinity;
  static const double oneToOnePipStageHorizontalPadding = 0.0;
  static const double oneToOnePipStageTopPadding = 88.0;
  static const double oneToOnePipStageBottomPadding = 152.0;
  static const double oneToOnePipOutsideOffset = 24.0;
  static const double oneToOnePipPrimaryLeadingInset = 20.0;
  static const double oneToOnePipDetachedGap = 12.0;
  static const double oneToOnePipWidthRatio = 0.38;
  static const double oneToOnePipMinWidth = 96.0;
  static const double oneToOnePipMaxWidth = 148.0;
  static const double oneToOnePipAspectRatio = 1.0;
  static const double oneToOnePipInset = 14.0;
  static const double oneToOneMediaAspectRatio = 9 / 16;
  static const double oneToOneDefaultBorderRadius = 26.0;
  static const double oneToOnePipBorderRadius = 20.0;
  static const Duration oneToOneLayoutSwitchDuration =
      Duration(milliseconds: 260);

  /// Computes split tile side size for one-to-one split layout.
  static double oneToOneSplitSquareSizeFor({
    required double stageWidth,
    required double stageHeight,
  }) {
    final safeWidth = math.max(0.0, stageWidth);
    final safeHeight = math.max(0.0, stageHeight);
    final availableByHeight = math.max(0.0, safeHeight - oneToOneSplitGap) / 2;
    final available = math.min(safeWidth, availableByHeight);
    if (available <= 0) {
      return 0;
    }
    final preferred = available
        .clamp(oneToOneSplitSquareMinSize, oneToOneSplitSquareMaxSize)
        .toDouble();
    return math.min(available, preferred);
  }

  /// Computes primary square side for one-to-one PiP layout.
  static double oneToOnePrimarySquareSizeFor({
    required double stageWidth,
    required double stageHeight,
  }) {
    final safeWidth = math.max(0.0, stageWidth);
    final safeHeight = math.max(0.0, stageHeight);
    final available = math.min(safeWidth, safeHeight);
    if (available <= 0) {
      return 0;
    }
    final preferred = available
        .clamp(oneToOnePrimarySquareMinSize, oneToOnePrimarySquareMaxSize)
        .toDouble();
    return math.min(available, preferred);
  }

  /// Computes primary square side for one-to-one PiP layout.
  ///
  /// `outsideOffset` reserves space for the PiP overlap so the promoted
  /// surface can be larger while still leaving room for outside placement.
  static double oneToOnePrimarySquareSizeForPip({
    required double stageWidth,
    required double stageHeight,
    required double outsideOffset,
  }) {
    final safeWidth = math.max(0.0, stageWidth - outsideOffset);
    final safeHeight = math.max(0.0, stageHeight - outsideOffset);
    final available = math.min(safeWidth, safeHeight);
    if (available <= 0) {
      return 0;
    }
    final preferred = available
        .clamp(oneToOnePrimarySquareMinSize, oneToOnePrimarySquareMaxSizePip)
        .toDouble();
    return math.min(available, preferred);
  }

  /// Computes primary square side for detached one-to-one PiP layout.
  ///
  /// Detached PiP places the mini tile below the primary tile with a fixed
  /// gap, then finds the largest primary size that fits.
  static double oneToOnePrimarySquareSizeForDetachedPip({
    required double stageWidth,
    required double stageHeight,
    required double primaryLeadingInset,
    required double detachedGap,
  }) {
    final safeWidth = math.max(0.0, stageWidth);
    final safeHeight = math.max(0.0, stageHeight);
    final minClusterWidth = math.max(
      primaryLeadingInset,
      oneToOnePipMinWidth,
    );
    final minClusterHeight = detachedGap + oneToOnePipMinWidth;
    if (safeWidth < minClusterWidth || safeHeight < minClusterHeight) {
      return 0;
    }

    bool fits(double primarySize) {
      final pipSize = oneToOnePipSquareSizeFor(primarySize);
      final footprintWidth = math.max(
        primaryLeadingInset + primarySize,
        pipSize,
      );
      return footprintWidth <= safeWidth &&
          primarySize + detachedGap + pipSize <= safeHeight;
    }

    double low = 0.0;
    double high = math.max(
      0.0,
      math.min(
        safeWidth - primaryLeadingInset,
        safeHeight - minClusterHeight,
      ),
    );
    if (oneToOnePrimarySquareMaxSizePip.isFinite) {
      high = math.min(high, oneToOnePrimarySquareMaxSizePip);
    }
    if (!fits(0)) {
      return 0;
    }

    for (var i = 0; i < 24; i++) {
      final mid = (low + high) / 2;
      if (fits(mid)) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return low;
  }

  /// Computes PiP side for one-to-one PiP layout.
  static double oneToOnePipSquareSizeFor(double primarySquareSize) {
    final dynamic = primarySquareSize * oneToOnePipWidthRatio;
    return dynamic.clamp(oneToOnePipMinWidth, oneToOnePipMaxWidth).toDouble();
  }

  // ── Durations ─────────────────────────────────────────────────────────
  static const Duration fadeInDuration = Duration(milliseconds: 400);
  static const Duration statusCrossfadeDuration = Duration(milliseconds: 300);
  static const Duration buttonToggleDuration = Duration(milliseconds: 200);
  static const Duration pulseAnimationDuration = Duration(milliseconds: 1500);
  static const Duration autoDismissDelay = Duration(seconds: 1);
}
