import 'package:flutter/material.dart';

import 'call_screen_theme.dart';

/// Theme tokens used by Callwave built-in UI.
///
/// Defaults intentionally match the current Callwave call-screen style.
class CallwaveThemeData {
  const CallwaveThemeData({
    this.backgroundGradient = CallScreenTheme.backgroundGradient,
    this.conferenceTileColor = const Color(0x1FFFFFFF),
    this.conferenceTileBorderColor = const Color(0x29FFFFFF),
    this.conferenceBadgeColor = const Color(0x8A000000),
    this.conferenceLabelColor = const Color(0x73000000),
    this.conferencePrimaryLabelStyle = const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    ),
    this.conferenceSecondaryLabelStyle = const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: Color(0xCCFFFFFF),
    ),
  });

  final Gradient backgroundGradient;
  final Color conferenceTileColor;
  final Color conferenceTileBorderColor;
  final Color conferenceBadgeColor;
  final Color conferenceLabelColor;
  final TextStyle conferencePrimaryLabelStyle;
  final TextStyle conferenceSecondaryLabelStyle;

  CallwaveThemeData copyWith({
    Gradient? backgroundGradient,
    Color? conferenceTileColor,
    Color? conferenceTileBorderColor,
    Color? conferenceBadgeColor,
    Color? conferenceLabelColor,
    TextStyle? conferencePrimaryLabelStyle,
    TextStyle? conferenceSecondaryLabelStyle,
  }) {
    return CallwaveThemeData(
      backgroundGradient: backgroundGradient ?? this.backgroundGradient,
      conferenceTileColor: conferenceTileColor ?? this.conferenceTileColor,
      conferenceTileBorderColor:
          conferenceTileBorderColor ?? this.conferenceTileBorderColor,
      conferenceBadgeColor: conferenceBadgeColor ?? this.conferenceBadgeColor,
      conferenceLabelColor: conferenceLabelColor ?? this.conferenceLabelColor,
      conferencePrimaryLabelStyle:
          conferencePrimaryLabelStyle ?? this.conferencePrimaryLabelStyle,
      conferenceSecondaryLabelStyle:
          conferenceSecondaryLabelStyle ?? this.conferenceSecondaryLabelStyle,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is CallwaveThemeData &&
        other.backgroundGradient == backgroundGradient &&
        other.conferenceTileColor == conferenceTileColor &&
        other.conferenceTileBorderColor == conferenceTileBorderColor &&
        other.conferenceBadgeColor == conferenceBadgeColor &&
        other.conferenceLabelColor == conferenceLabelColor &&
        other.conferencePrimaryLabelStyle == conferencePrimaryLabelStyle &&
        other.conferenceSecondaryLabelStyle == conferenceSecondaryLabelStyle;
  }

  @override
  int get hashCode => Object.hash(
        backgroundGradient,
        conferenceTileColor,
        conferenceTileBorderColor,
        conferenceBadgeColor,
        conferenceLabelColor,
        conferencePrimaryLabelStyle,
        conferenceSecondaryLabelStyle,
      );
}
