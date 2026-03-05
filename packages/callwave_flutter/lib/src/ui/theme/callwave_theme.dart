import 'package:flutter/widgets.dart';

import 'callwave_theme_data.dart';

class CallwaveTheme extends InheritedWidget {
  const CallwaveTheme({
    required this.data,
    required super.child,
    super.key,
  });

  final CallwaveThemeData data;

  static CallwaveThemeData of(BuildContext context) {
    return maybeOf(context) ?? const CallwaveThemeData();
  }

  static CallwaveThemeData? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<CallwaveTheme>()?.data;
  }

  @override
  bool updateShouldNotify(CallwaveTheme oldWidget) => oldWidget.data != data;
}
