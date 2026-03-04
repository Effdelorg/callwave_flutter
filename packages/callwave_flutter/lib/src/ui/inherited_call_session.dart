import 'package:flutter/widgets.dart';

import '../engine/call_session.dart';

/// Provides [CallSession] to descendants.
///
/// [CallwaveScope] wraps each [CallScreen] with this widget. Use [of] or
/// [maybeOf] in child widgets (e.g. custom call controls) to access the
/// session without prop drilling.
class InheritedCallSession extends InheritedWidget {
  const InheritedCallSession({
    required this.session,
    required super.child,
    super.key,
  });

  final CallSession session;

  /// Returns the [CallSession] from the nearest ancestor, or null if none.
  static CallSession? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<InheritedCallSession>()
        ?.session;
  }

  /// Returns the [CallSession] from the nearest ancestor.
  ///
  /// Throws if no [InheritedCallSession] ancestor exists.
  static CallSession of(BuildContext context) {
    final session = maybeOf(context);
    if (session == null) {
      throw FlutterError(
        'InheritedCallSession.of() called with no InheritedCallSession ancestor.',
      );
    }
    return session;
  }

  @override
  bool updateShouldNotify(InheritedCallSession oldWidget) {
    return oldWidget.session != session;
  }
}
