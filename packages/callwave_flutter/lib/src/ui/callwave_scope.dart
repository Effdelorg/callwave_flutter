import 'dart:async';

import 'package:flutter/material.dart';

import '../callwave_flutter_impl.dart';
import '../engine/call_session.dart';
import '../enums/call_session_state.dart';
import 'call_screen.dart';
import 'call_screen_builders.dart';
import 'inherited_call_session.dart';
import 'theme/callwave_theme.dart';
import 'theme/callwave_theme_data.dart';

typedef CallScreenBuilder = Widget Function(
  BuildContext context,
  CallSession session,
);

typedef CallSessionRouteHandler = bool Function(
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
    this.conferenceScreenBuilder,
    this.oneToOneRemoteVideoBuilder,
    this.oneToOneLocalVideoBuilder,
    this.participantTileBuilder,
    this.conferenceControlsBuilder,
    this.theme,
    this.preRoutedCallIds = const <String>{},
    this.onRouteSession,
    super.key,
  });

  /// Must be the same key as [MaterialApp.navigatorKey].
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  final CallScreenBuilder? callScreenBuilder;
  final ConferenceScreenBuilder? conferenceScreenBuilder;
  final OneToOneRemoteVideoBuilder? oneToOneRemoteVideoBuilder;
  final OneToOneLocalVideoBuilder? oneToOneLocalVideoBuilder;
  final ParticipantTileBuilder? participantTileBuilder;
  final ConferenceControlsBuilder? conferenceControlsBuilder;
  final CallwaveThemeData? theme;

  /// Sessions that were already routed by app startup logic.
  final Set<String> preRoutedCallIds;

  /// Optional app-level route hook. Return `true` to skip auto-push.
  final CallSessionRouteHandler? onRouteSession;

  @override
  State<CallwaveScope> createState() => _CallwaveScopeState();
}

class _CallwaveScopeState extends State<CallwaveScope> {
  final Map<String, CallSession> _pendingByCallId = <String, CallSession>{};
  final Set<String> _openedCallIds = <String>{};
  StreamSubscription<CallSession>? _subscription;
  bool _flushScheduled = false;
  bool _readyToPush = false;

  @override
  void initState() {
    super.initState();
    _subscription = CallwaveFlutter.instance.sessions.listen(
      _onSession,
      onError: _onSessionStreamError,
    );
    _hydrateExistingSessions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _readyToPush = true;
      if (_pendingByCallId.isNotEmpty) {
        _scheduleFlush();
      }
    });
  }

  void _hydrateExistingSessions() {
    final existingSessions = CallwaveFlutter.instance.activeSessions;
    for (final session in existingSessions) {
      if (_isRoutableSession(session)) {
        _pendingByCallId[session.callId] = session;
      }
    }
    if (existingSessions.isNotEmpty) {
      _scheduleFlush();
    }
  }

  void _onSession(CallSession session) {
    if (session.isEnded) {
      _pendingByCallId.remove(session.callId);
      _openedCallIds.remove(session.callId);
      return;
    }
    if (!_isRoutableSession(session)) {
      _pendingByCallId.remove(session.callId);
      return;
    }
    _pendingByCallId[session.callId] = session;
    _scheduleFlush();
  }

  bool _isRoutableSession(CallSession session) {
    return session.state != CallSessionState.validating &&
        session.state != CallSessionState.ended &&
        session.state != CallSessionState.failed;
  }

  void _scheduleFlush() {
    if (!_readyToPush) {
      return;
    }
    if (_flushScheduled) {
      return;
    }
    _flushScheduled = true;
    WidgetsBinding.instance.scheduleFrame();
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
      if (session.isEnded ||
          _openedCallIds.contains(session.callId) ||
          widget.preRoutedCallIds.contains(session.callId)) {
        continue;
      }

      final routeHandler = widget.onRouteSession;
      if (routeHandler != null) {
        final handled = routeHandler(navigator.context, session);
        if (handled) {
          _openedCallIds.add(session.callId);
          continue;
        }
      }

      _openedCallIds.add(session.callId);
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (context) {
            final callScreen = widget.callScreenBuilder
                    ?.call(context, session) ??
                CallScreen(
                  session: session,
                  conferenceScreenBuilder: widget.conferenceScreenBuilder,
                  oneToOneRemoteVideoBuilder: widget.oneToOneRemoteVideoBuilder,
                  oneToOneLocalVideoBuilder: widget.oneToOneLocalVideoBuilder,
                  participantTileBuilder: widget.participantTileBuilder,
                  conferenceControlsBuilder: widget.conferenceControlsBuilder,
                  theme: widget.theme,
                );
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
    _readyToPush = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallwaveTheme(
      data: widget.theme ?? const CallwaveThemeData(),
      child: widget.child,
    );
  }
}
