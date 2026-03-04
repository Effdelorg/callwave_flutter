import 'dart:async';

import 'package:flutter/material.dart';

import '../callwave_flutter_impl.dart';
import '../engine/call_session.dart';
import 'call_screen.dart';
import 'inherited_call_session.dart';

typedef CallScreenBuilder = Widget Function(
  BuildContext context,
  CallSession session,
);

/// Listens to [CallwaveFlutter.sessions] and auto-pushes [CallScreen] per call.
///
/// Place in [MaterialApp.builder], passing the same [navigatorKey] used by
/// [MaterialApp.navigatorKey]. Pushes are post-frame and retried while the
/// navigator is attaching during startup.
///
/// Does not auto-pop when a call ends; the screen dismisses itself.
class CallwaveScope extends StatefulWidget {
  const CallwaveScope({
    required this.navigatorKey,
    required this.child,
    this.callScreenBuilder,
    super.key,
  });

  /// Must be the same key as [MaterialApp.navigatorKey].
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  final CallScreenBuilder? callScreenBuilder;

  @override
  State<CallwaveScope> createState() => _CallwaveScopeState();
}

class _CallwaveScopeState extends State<CallwaveScope> {
  final Map<String, CallSession> _pendingByCallId = <String, CallSession>{};
  final Set<String> _openedCallIds = <String>{};
  StreamSubscription<CallSession>? _subscription;
  bool _flushScheduled = false;

  @override
  void initState() {
    super.initState();
    _subscription = CallwaveFlutter.instance.sessions.listen(
      _onSession,
      onError: _onSessionStreamError,
    );
  }

  void _onSession(CallSession session) {
    if (session.isEnded) {
      return;
    }
    _pendingByCallId[session.callId] = session;
    _scheduleFlush();
  }

  void _scheduleFlush() {
    if (_flushScheduled) {
      return;
    }
    _flushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushScheduled = false;
      if (!mounted) {
        return;
      }
      _flushPendingSessions();
    });
  }

  void _flushPendingSessions() {
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) {
      if (_pendingByCallId.isNotEmpty) {
        _scheduleFlush();
      }
      return;
    }
    if (_pendingByCallId.isEmpty) {
      return;
    }
    final pending = _pendingByCallId.values.toList(growable: false);
    _pendingByCallId.clear();

    for (final session in pending) {
      if (session.isEnded || _openedCallIds.contains(session.callId)) {
        continue;
      }
      _openedCallIds.add(session.callId);
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (context) {
            final callScreen =
                widget.callScreenBuilder?.call(context, session) ??
                    CallScreen(session: session);
            return InheritedCallSession(
              session: session,
              child: callScreen,
            );
          },
        ),
      ).whenComplete(() {
        _openedCallIds.remove(session.callId);
      });
    }
  }

  void _onSessionStreamError(Object error, StackTrace stackTrace) {
    debugPrint('CallwaveScope session stream error: $error');
    debugPrintStack(
      label: 'CallwaveScope session stream stack trace',
      stackTrace: stackTrace,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _pendingByCallId.clear();
    _openedCallIds.clear();
    _flushScheduled = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
