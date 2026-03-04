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
  static const double actionButtonSize = 64.0;
  static const double endCallButtonSize = 72.0;
  static const Color actionButtonInactive = Color(0x33FFFFFF);
  static const Color actionButtonActive = Colors.white;
  static const Color actionIconInactive = Colors.white;
  static const Color actionIconActive = Color(0xFF0D4F4F);

  /// Green background for the Accept call button.
  static const Color acceptCallColor = Color(0xFF2E7D32);

  /// Icon color for the Accept call button.
  static const Color acceptCallIconColor = Colors.white;
  static const Color endCallColor = Color(0xFFEF5350);

  /// Maximum rotation angle (radians) for the accept button wiggle animation.
  static const double acceptCallWiggleRadians = 0.22;

  /// Duration of one wiggle cycle for the accept button.
  static const Duration acceptCallWiggleDuration = Duration(milliseconds: 380);

  // ── Durations ─────────────────────────────────────────────────────────
  static const Duration fadeInDuration = Duration(milliseconds: 400);
  static const Duration statusCrossfadeDuration = Duration(milliseconds: 300);
  static const Duration buttonToggleDuration = Duration(milliseconds: 200);
  static const Duration pulseAnimationDuration = Duration(milliseconds: 1500);
  static const Duration autoDismissDelay = Duration(seconds: 1);
}
