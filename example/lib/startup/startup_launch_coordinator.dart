import 'dart:async';

import 'package:flutter/foundation.dart';

enum StartupLaunchMode {
  loading,
  startupJoinedCall,
  demo,
}

/// Owns startup launch state transitions for cold-start call recovery.
///
/// Coordinates loading, joined-call, and demo modes during app startup. Keeps
/// startup race logic out of UI widgets so call-event rendering and startup
/// state are maintained independently.
class StartupLaunchCoordinator extends ChangeNotifier {
  StartupLaunchCoordinator({
    Duration checkInterval = const Duration(milliseconds: 200),
    Duration maxWait = const Duration(milliseconds: 1200),
  })  : _checkInterval = checkInterval,
        _maxWait = maxWait;

  final Duration _checkInterval;
  final Duration _maxWait;

  bool _didRestoreActiveCalls = false;
  bool _startupCallRequested = false;
  bool _startupResolutionComplete = false;
  StartupLaunchMode _launchMode = StartupLaunchMode.demo;
  String? _startupJoinedCallId;
  bool _isDisposed = false;

  StartupLaunchMode get launchMode => _launchMode;
  bool get startupResolutionComplete => _startupResolutionComplete;
  bool get startupCallRequested => _startupCallRequested;
  String? get startupJoinedCallId => _startupJoinedCallId;

  bool shouldRunRestore({bool force = false}) {
    if (_didRestoreActiveCalls && !force) {
      return false;
    }
    if (!force) {
      _didRestoreActiveCalls = true;
    }
    return true;
  }

  void markAcceptedSignal() {
    if (_startupCallRequested) {
      return;
    }
    _startupCallRequested = true;
    if (!_startupResolutionComplete &&
        _launchMode != StartupLaunchMode.startupJoinedCall) {
      _launchMode = StartupLaunchMode.loading;
    }
    _safeNotify();
  }

  bool shouldOpenAsStartupJoinedCall({required bool hasOpenCallScreens}) {
    if (_startupResolutionComplete || !_startupCallRequested) {
      return false;
    }
    return !hasOpenCallScreens;
  }

  void openStartupJoinedCall(String callId) {
    if (_launchMode == StartupLaunchMode.startupJoinedCall &&
        _startupJoinedCallId == callId) {
      return;
    }
    _launchMode = StartupLaunchMode.startupJoinedCall;
    _startupJoinedCallId = callId;
    _safeNotify();
  }

  bool isStartupJoinedCall(String callId) {
    return _launchMode == StartupLaunchMode.startupJoinedCall &&
        _startupJoinedCallId == callId;
  }

  void showDemoMode() {
    if (_launchMode == StartupLaunchMode.demo && _startupJoinedCallId == null) {
      return;
    }
    _launchMode = StartupLaunchMode.demo;
    _startupJoinedCallId = null;
    _safeNotify();
  }

  Future<void> completeStartupResolution({
    required Future<void> Function({required bool force}) restoreActiveCalls,
    required bool Function() hasJoinSignal,
  }) async {
    try {
      await restoreActiveCalls(force: false);
      if (!hasJoinSignal()) {
        final maxChecks =
            (_maxWait.inMilliseconds / _checkInterval.inMilliseconds).ceil();
        var checks = 0;
        while (!_isDisposed && !hasJoinSignal() && checks < maxChecks) {
          await Future<void>.delayed(_checkInterval);
          if (_isDisposed || hasJoinSignal()) {
            break;
          }
          await restoreActiveCalls(force: true);
          checks += 1;
        }
      }
    } finally {
      if (!_isDisposed) {
        _startupResolutionComplete = true;
        if (_launchMode == StartupLaunchMode.loading) {
          _launchMode = StartupLaunchMode.demo;
        }
        _safeNotify();
      }
    }
  }

  void _safeNotify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
