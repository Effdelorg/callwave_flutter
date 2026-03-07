import 'dart:async';
import 'dart:io';

import 'package:callwave_flutter/callwave_flutter.dart';
import 'package:flutter/material.dart';

import 'example_camera_controller.dart';
import 'example_video_call_screen.dart';
import 'mock_callwave_engine.dart';

enum IncomingDemoMode {
  realtime('Realtime'),
  validatedAllow('Validated Allow'),
  validatedReject('Validated Reject'),
  declineReported('Decline Reported'),
  declineFailed('Decline Failed');

  const IncomingDemoMode(this.label);

  final String label;
}

enum CallbackSessionMode {
  oneToOne('One-to-one'),
  conference('Conference');

  const CallbackSessionMode(this.label);

  final String label;
}

abstract final class _ExampleExtraKeys {
  static const String roomType = 'roomType';
  static const String roomTypeOneToOne = 'oneToOne';
  static const String roomTypeConference = 'conference';
}

class _IncomingDemoModeStore {
  static File get _file => File(
        '${Directory.systemTemp.path}/callwave_example_incoming_mode.txt',
      );

  static Future<IncomingDemoMode> load() async {
    try {
      final raw = (await _file.readAsString()).trim();
      return IncomingDemoMode.values.firstWhere(
        (mode) => mode.name == raw,
        orElse: () => IncomingDemoMode.realtime,
      );
    } catch (_) {
      return IncomingDemoMode.realtime;
    }
  }

  static Future<void> save(IncomingDemoMode mode) async {
    await _file.writeAsString(mode.name, flush: true);
  }

  static Future<void> clear() async {
    if (await _file.exists()) {
      await _file.delete();
    }
  }
}

Future<IncomingDemoMode> loadPersistedIncomingDemoMode() {
  return _IncomingDemoModeStore.load();
}

Future<void> persistIncomingDemoMode(IncomingDemoMode mode) {
  return _IncomingDemoModeStore.save(mode);
}

Future<void> clearPersistedIncomingDemoMode() {
  return _IncomingDemoModeStore.clear();
}

IncomingCallHandling exampleIncomingCallHandling({
  required IncomingDemoMode incomingDemoMode,
  required CallAcceptValidator foregroundValidator,
}) {
  return switch (incomingDemoMode) {
    IncomingDemoMode.realtime ||
    IncomingDemoMode.declineReported ||
    IncomingDemoMode.declineFailed =>
      const IncomingCallHandling.realtime(),
    IncomingDemoMode.validatedAllow ||
    IncomingDemoMode.validatedReject =>
      IncomingCallHandling.validated(
        validator: foregroundValidator,
      ),
  };
}

void configureExampleCallwave({
  required CallwaveEngine engine,
  required IncomingDemoMode incomingDemoMode,
  required CallAcceptValidator foregroundValidator,
}) {
  CallwaveFlutter.instance.configure(
    CallwaveConfiguration(
      engine: engine,
      incomingCallHandling: exampleIncomingCallHandling(
        incomingDemoMode: incomingDemoMode,
        foregroundValidator: foregroundValidator,
      ),
      backgroundIncomingCallValidator: exampleBackgroundIncomingCallValidator,
      backgroundIncomingCallDeclineValidator:
          exampleBackgroundIncomingCallDeclineValidator,
    ),
  );
}

Future<CallAcceptDecision> _decisionForMode({
  required IncomingDemoMode mode,
  required String callId,
}) async {
  await Future<void>.delayed(const Duration(milliseconds: 700));
  switch (mode) {
    case IncomingDemoMode.realtime:
    case IncomingDemoMode.validatedAllow:
    case IncomingDemoMode.declineReported:
    case IncomingDemoMode.declineFailed:
      return CallAcceptDecision.allow(
        extra: <String, dynamic>{
          'validatedByExample': true,
          'validatedCallId': callId,
        },
      );
    case IncomingDemoMode.validatedReject:
      return const CallAcceptDecision.reject(
        reason: CallAcceptRejectReason.cancelled,
        extra: <String, dynamic>{
          'validatedByExample': true,
        },
      );
  }
}

Future<CallDeclineDecision> _declineDecisionForMode({
  required IncomingDemoMode mode,
  required String callId,
}) async {
  await Future<void>.delayed(const Duration(milliseconds: 700));
  switch (mode) {
    case IncomingDemoMode.declineFailed:
      return const CallDeclineDecision.failed(
        reason: CallDeclineFailureReason.failed,
        extra: <String, dynamic>{
          'declineReportedByExample': false,
        },
      );
    case IncomingDemoMode.realtime:
    case IncomingDemoMode.validatedAllow:
    case IncomingDemoMode.validatedReject:
    case IncomingDemoMode.declineReported:
      return CallDeclineDecision.reported(
        extra: <String, dynamic>{
          'declineReportedByExample': true,
          'declineReportedCallId': callId,
        },
      );
  }
}

@pragma('vm:entry-point')
Future<CallAcceptDecision> exampleBackgroundIncomingCallValidator(
  BackgroundIncomingCallValidationRequest request,
) async {
  final mode = await loadPersistedIncomingDemoMode();
  return _decisionForMode(
    mode: mode,
    callId: request.callId,
  );
}

@pragma('vm:entry-point')
Future<CallDeclineDecision> exampleBackgroundIncomingCallDeclineValidator(
  BackgroundIncomingCallValidationRequest request,
) async {
  final mode = await loadPersistedIncomingDemoMode();
  return _declineDecisionForMode(
    mode: mode,
    callId: request.callId,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameraController = ExampleCameraController();
  final engine = MockCallwaveEngine(
    cameraController: cameraController,
  );
  final initialIncomingDemoMode = await loadPersistedIncomingDemoMode();
  configureExampleCallwave(
    engine: engine,
    incomingDemoMode: initialIncomingDemoMode,
    foregroundValidator: (session) {
      return _decisionForMode(
        mode: initialIncomingDemoMode,
        callId: session.callId,
      );
    },
  );
  final startupDecision =
      await CallwaveFlutter.instance.prepareStartupRouteDecision();
  runApp(
    CallwaveExampleApp(
      startupDecision: startupDecision,
      cameraController: cameraController,
      engine: engine,
      initialIncomingDemoMode: initialIncomingDemoMode,
      disposeCameraControllerOnDispose: true,
    ),
  );
}

abstract final class _Routes {
  static const String home = '/home';
  static const String call = '/call';
}

class CallwaveExampleApp extends StatefulWidget {
  const CallwaveExampleApp({
    CallStartupRouteDecision? startupDecision,
    this.cameraController,
    this.engine,
    this.oneToOneRemoteVideoBuilder,
    this.oneToOneLocalVideoBuilder,
    this.initialIncomingDemoMode = IncomingDemoMode.realtime,
    this.disposeCameraControllerOnDispose = false,
    super.key,
  }) : startupDecision =
            startupDecision ?? const CallStartupRouteDecision.home();

  final CallStartupRouteDecision startupDecision;

  /// Handle for camera preview in video calls. If null, a default is created.
  final ExampleCameraHandle? cameraController;
  final CallwaveEngine? engine;
  final OneToOneRemoteVideoBuilder? oneToOneRemoteVideoBuilder;
  final OneToOneLocalVideoBuilder? oneToOneLocalVideoBuilder;
  final IncomingDemoMode initialIncomingDemoMode;

  /// If true and [cameraController] is provided, the app disposes it when
  /// disposed. Use when the app creates the controller (e.g. in main).
  final bool disposeCameraControllerOnDispose;

  @override
  State<CallwaveExampleApp> createState() => _CallwaveExampleAppState();
}

class _CallwaveExampleAppState extends State<CallwaveExampleApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final ExampleCameraHandle _cameraController =
      widget.cameraController ?? ExampleCameraController();
  late final bool _ownsCameraController = widget.cameraController == null ||
      widget.disposeCameraControllerOnDispose;
  late final CallwaveEngine _engine =
      widget.engine ?? MockCallwaveEngine(cameraController: _cameraController);
  late final Set<String> _preRoutedCallIds =
      widget.startupDecision.callId == null
          ? const <String>{}
          : <String>{widget.startupDecision.callId!};

  @override
  void dispose() {
    if (_ownsCameraController) {
      _cameraController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      title: 'Callwave Example',
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFC4441A),
          brightness: Brightness.light,
        ).copyWith(
          primary: const Color(0xFFC4441A),
          onPrimary: Colors.white,
          secondary: const Color(0xFFC4441A),
          onSecondary: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFFAF8F5),
        cardColor: const Color(0xFFFFFDFB),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF5F2EE),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFD9D3CB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFD9D3CB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: Color(0xFFC4441A), width: 1.5),
          ),
          labelStyle: const TextStyle(color: Color(0xFF7A7267)),
          hintStyle: const TextStyle(color: Color(0xFFB5AFA7)),
          helperStyle: const TextStyle(color: Color(0xFFB5AFA7)),
        ),
        dividerColor: const Color(0xFFE8E3DC),
        useMaterial3: true,
      ),
      builder: (context, child) {
        return CallwaveScope(
          navigatorKey: _navigatorKey,
          preRoutedCallIds: _preRoutedCallIds,
          callScreenBuilder: (context, session) {
            return _buildCallScreen(
              session: session,
              cameraController: _cameraController,
              oneToOneRemoteVideoBuilder: widget.oneToOneRemoteVideoBuilder,
              oneToOneLocalVideoBuilder: widget.oneToOneLocalVideoBuilder,
            );
          },
          child: child ?? const SizedBox.shrink(),
        );
      },
      initialRoute:
          widget.startupDecision.shouldOpenCall ? _Routes.call : _Routes.home,
      routes: <String, WidgetBuilder>{
        _Routes.home: (_) => CallDemoScreen(
              engine: _engine,
              initialIncomingDemoMode: widget.initialIncomingDemoMode,
              initialPendingAction: widget.startupDecision.pendingAction,
            ),
        _Routes.call: (_) => _StartupCallRoute(
              startupDecision: widget.startupDecision,
              cameraController: _cameraController,
              engine: _engine,
              initialIncomingDemoMode: widget.initialIncomingDemoMode,
              oneToOneRemoteVideoBuilder: widget.oneToOneRemoteVideoBuilder,
              oneToOneLocalVideoBuilder: widget.oneToOneLocalVideoBuilder,
            ),
      },
    );
  }
}

class _StartupCallRoute extends StatelessWidget {
  const _StartupCallRoute({
    required this.startupDecision,
    required this.cameraController,
    required this.engine,
    required this.initialIncomingDemoMode,
    this.oneToOneRemoteVideoBuilder,
    this.oneToOneLocalVideoBuilder,
  });

  final CallStartupRouteDecision startupDecision;
  final ExampleCameraHandle cameraController;
  final CallwaveEngine engine;
  final IncomingDemoMode initialIncomingDemoMode;
  final OneToOneRemoteVideoBuilder? oneToOneRemoteVideoBuilder;
  final OneToOneLocalVideoBuilder? oneToOneLocalVideoBuilder;

  @override
  Widget build(BuildContext context) {
    final callId = startupDecision.callId;
    if (callId == null) {
      return CallDemoScreen(
        engine: engine,
        initialIncomingDemoMode: initialIncomingDemoMode,
        initialPendingAction: startupDecision.pendingAction,
      );
    }

    final session = CallwaveFlutter.instance.getSession(callId);
    if (session == null || session.isEnded) {
      return CallDemoScreen(
        engine: engine,
        initialIncomingDemoMode: initialIncomingDemoMode,
        initialPendingAction: startupDecision.pendingAction,
      );
    }

    return InheritedCallSession(
      session: session,
      child: _buildCallScreen(
        session: session,
        cameraController: cameraController,
        oneToOneRemoteVideoBuilder: oneToOneRemoteVideoBuilder,
        oneToOneLocalVideoBuilder: oneToOneLocalVideoBuilder,
        onCallEnded: () {
          Navigator.of(context).pushReplacementNamed(_Routes.home);
        },
      ),
    );
  }
}

Widget _buildCallScreen({
  required CallSession session,
  required ExampleCameraHandle cameraController,
  OneToOneRemoteVideoBuilder? oneToOneRemoteVideoBuilder,
  OneToOneLocalVideoBuilder? oneToOneLocalVideoBuilder,
  VoidCallback? onCallEnded,
}) {
  if (session.callData.callType != CallType.video) {
    return CallScreen(
      session: session,
      onCallEnded: onCallEnded,
      oneToOneRemoteVideoBuilder: oneToOneRemoteVideoBuilder,
      oneToOneLocalVideoBuilder: oneToOneLocalVideoBuilder,
    );
  }
  return ExampleVideoCallScreen(
    session: session,
    cameraController: cameraController,
    oneToOneRemoteVideoBuilder: oneToOneRemoteVideoBuilder,
    oneToOneLocalVideoBuilder: oneToOneLocalVideoBuilder,
    onCallEnded: onCallEnded,
  );
}

class CallDemoScreen extends StatefulWidget {
  const CallDemoScreen({
    required this.engine,
    required this.initialIncomingDemoMode,
    this.initialPendingAction,
    super.key,
  });

  final CallwaveEngine engine;
  final IncomingDemoMode initialIncomingDemoMode;
  final CallStartupAction? initialPendingAction;

  @override
  State<CallDemoScreen> createState() => _CallDemoScreenState();
}

class _CallDemoScreenState extends State<CallDemoScreen> {
  static const String _incomingCallerName = 'Ava';
  static const String _incomingHandle = '+1 555 0101';
  static const String _outgoingCallerName = 'Milo';
  static const String _outgoingHandle = '+1 555 0202';

  final List<String> _eventLog = <String>[];
  final TextEditingController _callIdController =
      TextEditingController(text: 'demo-call-001');
  final TextEditingController _missedNotificationTextController =
      TextEditingController();
  late final CallwaveEngine _engine = widget.engine;
  StreamSubscription<CallEvent>? _subscription;
  bool _isCallActionInFlight = false;
  String? _previewCallId;
  int _speakerCursor = 0;
  late IncomingDemoMode _incomingDemoMode = widget.initialIncomingDemoMode;
  CallStartupAction? _pendingStartupAction;
  CallType _callbackCallType = CallType.audio;
  CallbackSessionMode _callbackSessionMode = CallbackSessionMode.oneToOne;

  @override
  void initState() {
    super.initState();
    _missedNotificationTextController.text = 'You missed a call from {name}.';
    _subscription = CallwaveFlutter.instance.events.listen(_onCallEvent);
    _applyPendingStartupAction(widget.initialPendingAction, logEvent: false);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _callIdController.dispose();
    _missedNotificationTextController.dispose();
    super.dispose();
  }

  void _onCallEvent(CallEvent event) {
    if (!mounted) {
      return;
    }
    if (event.type == CallEventType.callback) {
      _applyPendingStartupAction(
        _startupActionFromEvent(
          event: event,
          type: CallStartupActionType.callback,
        ),
      );
    } else if (event.type == CallEventType.missed &&
        event.extra?[CallEventExtraKeys.launchAction] ==
            CallEventExtraKeys.launchActionOpenMissedCall) {
      _applyPendingStartupAction(
        _startupActionFromEvent(
          event: event,
          type: CallStartupActionType.openMissedCall,
        ),
      );
    }
    if (_previewCallId == event.callId &&
        (event.type == CallEventType.ended ||
            event.type == CallEventType.declined ||
            event.type == CallEventType.timeout ||
            event.type == CallEventType.missed)) {
      _previewCallId = null;
    }
    setState(() {
      _eventLog.insert(
        0,
        '${event.timestamp.toIso8601String()} ${event.callId} ${event.type.name}',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final callId = _callIdController.text.trim();
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final hasActiveSessions =
        CallwaveFlutter.instance.activeSessions.isNotEmpty;
    final incomingModeLocked = hasActiveSessions || _isCallActionInFlight;
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFFFFFDFB),
            border: Border(
              bottom: BorderSide(color: Color(0xFFE8E3DC), width: 1),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.waves_rounded,
                    color: Color(0xFFC4441A),
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Callwave',
                    style: TextStyle(
                      color: Color(0xFF191919),
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDF0EB),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFFC4441A),
                        width: 0.8,
                      ),
                    ),
                    child: const Text(
                      'SDK Demo',
                      style: TextStyle(
                        color: Color(0xFFC4441A),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + bottomInset),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 36,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // ── QUICK START BANNER ───────────────────────────────
                    const _QuickStartBanner(),
                    const SizedBox(height: 16),

                    // Pending startup action card (shown above all sections)
                    if (_pendingStartupAction != null) ...<Widget>[
                      _PendingStartupActionCard(
                        action: _pendingStartupAction!,
                        callbackCallType: _callbackCallType,
                        callbackSessionMode: _callbackSessionMode,
                        actionInFlight: _isCallActionInFlight,
                        onDismiss: _dismissPendingStartupAction,
                        onCallTypeChanged: (callType) {
                          setState(() {
                            _callbackCallType = callType;
                          });
                        },
                        onSessionModeChanged: (sessionMode) {
                          setState(() {
                            _callbackSessionMode = sessionMode;
                          });
                        },
                        onStartCallback: _startCallbackFromPendingAction,
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── CALL CONFIGURATION ───────────────────────────────
                    _SectionCard(
                      icon: Icons.tune_rounded,
                      title: 'CALL CONFIGURATION',
                      subtitle: 'Set the call ID used by all simulate actions below.',
                      accentColor: const Color(0xFFC4441A),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          TextField(
                            controller: _callIdController,
                            style: const TextStyle(
                              color: Color(0xFF191919),
                              fontFamily: 'monospace',
                              fontSize: 15,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Call ID',
                              hintText: 'demo-call-001',
                              helperText:
                                  'Must be unique per call session. Reuse the same ID to control an active call.',
                              prefixIcon: Icon(
                                Icons.tag_rounded,
                                size: 18,
                                color: Color(0xFFB5AFA7),
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _missedNotificationTextController,
                            style: const TextStyle(
                              color: Color(0xFF191919),
                              fontSize: 15,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Missed Notification Text',
                              hintText: 'You missed a call from {name}.',
                              prefixIcon: Icon(
                                Icons.notifications_rounded,
                                size: 18,
                                color: Color(0xFFB5AFA7),
                              ),
                              helperText:
                                  'Shown when a call times out. Use {name} to insert the caller\'s name.',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── PERMISSIONS ──────────────────────────────────────
                    _SectionCard(
                      icon: Icons.lock_open_rounded,
                      title: 'PERMISSIONS',
                      subtitle:
                          'Request OS permissions before triggering calls. Grant these first on a fresh install.',
                      accentColor: const Color(0xFFC27803),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: _PermissionButton(
                              icon: Icons.notifications_rounded,
                              label: 'Notifications',
                              hint: 'Required to show incoming call alerts',
                              onPressed: callId.isEmpty
                                  ? null
                                  : _requestNotificationPermission,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _PermissionButton(
                              icon: Icons.fullscreen_rounded,
                              label: 'Full Screen',
                              hint: 'Android only — shows call over lock screen',
                              onPressed: callId.isEmpty
                                  ? null
                                  : _requestFullScreenPermission,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── INCOMING FLOW MODE ───────────────────────────────
                    _SectionCard(
                      icon: Icons.swap_horiz_rounded,
                      title: 'INCOMING FLOW MODE',
                      subtitle:
                          'Choose how the plugin handles accept/decline from the native call UI.',
                      accentColor: const Color(0xFFC4441A),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: IncomingDemoMode.values.map((mode) {
                              final isSelected = mode == _incomingDemoMode;
                              return _ModeChip(
                                label: mode.label,
                                selected: isSelected,
                                locked: incomingModeLocked,
                                onSelected: () {
                                  if (isSelected) return;
                                  setState(() {
                                    _incomingDemoMode = mode;
                                  });
                                  unawaited(persistIncomingDemoMode(mode));
                                  _applyIncomingMode();
                                },
                              );
                            }).toList(growable: false),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFDF0EB),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFE8C8B8),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                const Icon(
                                  Icons.info_outline_rounded,
                                  size: 15,
                                  color: Color(0xFFC4441A),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _incomingModeDescription,
                                    style: const TextStyle(
                                      color: Color(0xFF3D3731),
                                      fontSize: 13,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (incomingModeLocked) ...<Widget>[
                            const SizedBox(height: 8),
                            const Row(
                              children: <Widget>[
                                Icon(
                                  Icons.lock_rounded,
                                  size: 13,
                                  color: Color(0xFFB5AFA7),
                                ),
                                SizedBox(width: 5),
                                Text(
                                  'Mode locked while a call is active.',
                                  style: TextStyle(
                                    color: Color(0xFFB5AFA7),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── SIMULATE CALL ────────────────────────────────────
                    _SectionCard(
                      icon: Icons.phone_rounded,
                      title: 'SIMULATE CALL',
                      subtitle:
                          'Trigger native call UI flows. Buttons are disabled when Call ID is empty.',
                      accentColor: const Color(0xFF2D8B4E),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          // Incoming
                          const _SubSectionLabel(
                            text: 'INCOMING',
                            color: Color(0xFF2D8B4E),
                            hint: 'Simulates a call arriving on this device',
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: _CallButton(
                                  icon: Icons.call_received_rounded,
                                  label: 'Audio',
                                  color: const Color(0xFF2D8B4E),
                                  onPressed:
                                      callId.isEmpty || _isCallActionInFlight
                                          ? null
                                          : () => _showCall(
                                                callId: callId,
                                                isIncoming: true,
                                                callType: CallType.audio,
                                              ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _CallButton(
                                  icon: Icons.video_call_rounded,
                                  label: 'Video',
                                  color: const Color(0xFF2D8B4E),
                                  onPressed:
                                      callId.isEmpty || _isCallActionInFlight
                                          ? null
                                          : () => _showCall(
                                                callId: callId,
                                                isIncoming: true,
                                                callType: CallType.video,
                                              ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Outgoing
                          const _SubSectionLabel(
                            text: 'OUTGOING',
                            color: Color(0xFF2B6CB0),
                            hint: 'Opens the outgoing call screen immediately',
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: _CallButton(
                                  icon: Icons.call_made_rounded,
                                  label: 'Audio',
                                  color: const Color(0xFF2B6CB0),
                                  onPressed:
                                      callId.isEmpty || _isCallActionInFlight
                                          ? null
                                          : () => _showCall(
                                                callId: callId,
                                                isIncoming: false,
                                                callType: CallType.audio,
                                              ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _CallButton(
                                  icon: Icons.videocam_rounded,
                                  label: 'Video',
                                  color: const Color(0xFF2B6CB0),
                                  onPressed:
                                      callId.isEmpty || _isCallActionInFlight
                                          ? null
                                          : () => _showCall(
                                                callId: callId,
                                                isIncoming: false,
                                                callType: CallType.video,
                                              ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Call Control
                          const _SubSectionLabel(
                            text: 'CALL CONTROL',
                            color: Color(0xFFC53030),
                            hint: 'Control an active call by its ID',
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: _CallButton(
                                  icon: Icons.call_end_rounded,
                                  label: 'End Call',
                                  color: const Color(0xFFC53030),
                                  onPressed: callId.isEmpty
                                      ? null
                                      : () => _endCall(callId),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _CallButton(
                                  icon: Icons.phone_missed_rounded,
                                  label: 'Mark Missed',
                                  color: const Color(0xFFC53030),
                                  onPressed: callId.isEmpty
                                      ? null
                                      : () => _markMissed(callId),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Conference
                          const _SubSectionLabel(
                            text: 'CONFERENCE',
                            color: Color(0xFF6B46C1),
                            hint: 'Preview multi-party call layout with mock participants',
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: _CallButton(
                                  icon: Icons.groups_rounded,
                                  label: 'Audio',
                                  color: const Color(0xFF6B46C1),
                                  onPressed: callId.isEmpty
                                      ? null
                                      : () => _openConferencePreview(
                                            callId,
                                            CallType.audio,
                                          ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _CallButton(
                                  icon: Icons.duo_rounded,
                                  label: 'Video',
                                  color: const Color(0xFF6B46C1),
                                  onPressed: callId.isEmpty
                                      ? null
                                      : () => _openConferencePreview(
                                            callId,
                                            CallType.video,
                                          ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _CallButton(
                                  icon: Icons.sync_rounded,
                                  label: 'Cycle\nSpeaker',
                                  color: const Color(0xFF6B46C1),
                                  onPressed: _previewCallId == null
                                      ? null
                                      : _cycleConferenceSpeaker,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── EVENT LOG ────────────────────────────────────────
                    _SectionCard(
                      icon: Icons.receipt_long_rounded,
                      title: 'EVENT LOG',
                      subtitle: 'Real-time stream of CallEvent callbacks from the plugin.',
                      accentColor: const Color(0xFF7A7267),
                      trailing: TextButton(
                        onPressed: _eventLog.isEmpty
                            ? null
                            : () => setState(() => _eventLog.clear()),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFB5AFA7),
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(48, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Clear',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      child: Container(
                        height: 230,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F2EE),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE8E3DC)),
                        ),
                        child: _eventLog.isEmpty
                            ? const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(
                                      Icons.inbox_rounded,
                                      size: 34,
                                      color: Color(0xFFD9D3CB),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'No events yet',
                                      style: TextStyle(
                                        color: Color(0xFFB5AFA7),
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    SizedBox(height: 3),
                                    Text(
                                      'Simulate a call above to see events here',
                                      style: TextStyle(
                                        color: Color(0xFFD9D3CB),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                itemCount: _eventLog.length,
                                itemBuilder: (context, index) {
                                  final raw = _eventLog[index];
                                  final parts = raw.split(' ');
                                  final timestamp =
                                      parts.isNotEmpty ? parts[0] : raw;
                                  final rest = parts.length > 1
                                      ? parts.sublist(1).join(' ')
                                      : '';
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 3,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        const Text(
                                          '›',
                                          style: TextStyle(
                                            color: Color(0xFFC4441A),
                                            fontFamily: 'monospace',
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text.rich(
                                            TextSpan(
                                              children: <InlineSpan>[
                                                TextSpan(
                                                  text: timestamp,
                                                  style: const TextStyle(
                                                    color: Color(0xFFB5AFA7),
                                                    fontFamily: 'monospace',
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                if (rest.isNotEmpty)
                                                  TextSpan(
                                                    text: '  $rest',
                                                    style: const TextStyle(
                                                      color: Color(0xFF191919),
                                                      fontFamily: 'monospace',
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _requestNotificationPermission() async {
    final granted =
        await CallwaveFlutter.instance.requestNotificationPermission();
    _pushLog('Notification permission granted: $granted');
  }

  Future<void> _requestFullScreenPermission() async {
    await CallwaveFlutter.instance.requestFullScreenIntentPermission();
    _pushLog('Requested full-screen intent permission screen.');
  }

  Future<void> _showCall({
    required String callId,
    required bool isIncoming,
    required CallType callType,
  }) async {
    if (_isCallActionInFlight) {
      return;
    }
    setState(() {
      _isCallActionInFlight = true;
    });

    final callData = isIncoming
        ? _buildCallData(
            callId: callId,
            callerName: _incomingCallerName,
            handle: _incomingHandle,
            callType: callType,
          )
        : _buildCallData(
            callId: callId,
            callerName: _outgoingCallerName,
            handle: _outgoingHandle,
            callType: callType,
          );

    try {
      if (isIncoming) {
        await CallwaveFlutter.instance.showIncomingCall(callData);
      } else {
        await CallwaveFlutter.instance.showOutgoingCall(callData);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCallActionInFlight = false;
        });
      }
    }
  }

  CallData _buildCallData({
    required String callId,
    required String callerName,
    required String handle,
    required CallType callType,
    Duration timeout = const Duration(seconds: 30),
    String? avatarUrl,
    Map<String, dynamic>? extraOverrides,
  }) {
    final customMissedNotificationText =
        _resolvedMissedNotificationText(callerName);
    final extra = <String, dynamic>{
      ...?extraOverrides,
      'callerName': callerName,
      'handle': handle,
      'callType': callType.name,
      CallDataExtraKeys.androidMissedCallNotificationText:
          customMissedNotificationText,
    };
    return CallData(
      callId: callId,
      callerName: callerName,
      handle: handle,
      avatarUrl: avatarUrl,
      timeout: timeout,
      callType: callType,
      extra: extra,
    );
  }

  String _resolvedMissedNotificationText(String callerName) {
    final customText = _missedNotificationTextController.text.trim();
    if (customText.isNotEmpty) {
      return customText.replaceAll('{name}', callerName);
    }
    return 'You missed a call from $callerName.';
  }

  Future<void> _endCall(String callId) async {
    await CallwaveFlutter.instance.endCall(callId);
  }

  Future<void> _markMissed(String callId) async {
    await CallwaveFlutter.instance.markMissed(callId);
  }

  void _applyIncomingMode() {
    configureExampleCallwave(
      engine: _engine,
      incomingDemoMode: _incomingDemoMode,
      foregroundValidator: _foregroundIncomingValidator,
    );
  }

  Future<CallAcceptDecision> _foregroundIncomingValidator(
    CallSession session,
  ) {
    return _decisionForMode(
      mode: _incomingDemoMode,
      callId: session.callId,
    );
  }

  String get _incomingModeDescription {
    switch (_incomingDemoMode) {
      case IncomingDemoMode.realtime:
        return 'Native accept opens the call flow immediately, like WhatsApp-style realtime signaling.';
      case IncomingDemoMode.validatedAllow:
        return 'Native accept waits for backend validation, then opens the call only after approval.';
      case IncomingDemoMode.validatedReject:
        return 'Native accept waits for validation and then fails gracefully into missed-call handling without foreground fallback.';
      case IncomingDemoMode.declineReported:
        return 'Native decline reports to the backend in a headless Flutter isolate and dismisses the call without opening the app.';
      case IncomingDemoMode.declineFailed:
        return 'Native decline simulates a failed backend report, so the plugin falls back to missed-call UX.';
    }
  }

  void _openConferencePreview(String callIdSeed, CallType callType) {
    final callId =
        '$callIdSeed-conference-${DateTime.now().millisecondsSinceEpoch}';
    final session = CallwaveFlutter.instance.createSession(
      callData: _buildCallData(
        callId: callId,
        callerName: 'Conference',
        handle: 'group room',
        callType: callType,
        timeout: const Duration(seconds: 45),
        extraOverrides: const <String, dynamic>{
          _ExampleExtraKeys.roomType: _ExampleExtraKeys.roomTypeConference,
        },
      ),
      isOutgoing: true,
      initialState: CallSessionState.connected,
    );

    _previewCallId = callId;
    _speakerCursor = 0;
    session.updateConferenceState(
      _buildPreviewConferenceState(
        updatedAtMs: 1,
        callType: callType,
      ),
    );
    _pushLog('Conference ${callType.name} preview started for $callId');
    setState(() {});
  }

  void _cycleConferenceSpeaker() {
    final callId = _previewCallId;
    if (callId == null) {
      return;
    }
    final session = CallwaveFlutter.instance.getSession(callId);
    if (session == null || session.isEnded) {
      _pushLog('Conference preview session is not active.');
      return;
    }
    _speakerCursor += 1;
    final updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    final callType = session.callData.callType;
    session.updateConferenceState(
      _buildPreviewConferenceState(
        updatedAtMs: updatedAtMs,
        callType: callType,
      ),
    );
    _pushLog('Conference speaker changed.');
  }

  ConferenceState _buildPreviewConferenceState({
    required int updatedAtMs,
    required CallType callType,
  }) {
    final participants = <CallParticipant>[
      CallParticipant(
        participantId: 'speaker-1',
        displayName: 'Ava',
        isVideoOn: callType == CallType.video,
        sortOrder: 1,
      ),
      CallParticipant(
        participantId: 'speaker-2',
        displayName: 'Milo',
        isVideoOn: callType == CallType.video,
        sortOrder: 2,
      ),
      CallParticipant(
        participantId: 'speaker-3',
        displayName: 'Nora',
        isVideoOn: callType == CallType.video,
        sortOrder: 3,
      ),
      CallParticipant(
        participantId: 'local-you',
        displayName: 'You',
        isLocal: true,
        isVideoOn: callType == CallType.video,
        sortOrder: 4,
      ),
    ];
    final activeSpeaker = participants[_speakerCursor % 3].participantId;
    return ConferenceState(
      participants: participants,
      activeSpeakerId: activeSpeaker,
      updatedAtMs: updatedAtMs,
    );
  }

  void _pushLog(String value) {
    if (!mounted) {
      return;
    }
    setState(() {
      _eventLog.insert(0, '${DateTime.now().toIso8601String()} $value');
    });
  }

  void _dismissPendingStartupAction() {
    if (_pendingStartupAction == null) {
      return;
    }
    setState(() {
      _pendingStartupAction = null;
    });
  }

  void _applyPendingStartupAction(
    CallStartupAction? action, {
    bool logEvent = true,
  }) {
    if (action == null || !mounted) {
      return;
    }
    final isConference = action.extra?[_ExampleExtraKeys.roomType] ==
        _ExampleExtraKeys.roomTypeConference;
    setState(() {
      _pendingStartupAction = action;
      _callbackCallType = action.callType;
      _callbackSessionMode = isConference
          ? CallbackSessionMode.conference
          : CallbackSessionMode.oneToOne;
      _callIdController.text = action.callId;
    });
    if (logEvent) {
      _pushLog(
        action.type == CallStartupActionType.callback
            ? 'Callback requested for ${action.callerName}.'
            : 'Opened missed call from ${action.callerName}.',
      );
    }
  }

  CallStartupAction _startupActionFromEvent({
    required CallEvent event,
    required CallStartupActionType type,
  }) {
    return CallStartupAction(
      type: type,
      callId: event.callId,
      callerName: (event.extra?['callerName'] as String?) ?? 'Unknown',
      handle: (event.extra?['handle'] as String?) ?? '',
      avatarUrl: event.extra?['avatarUrl'] as String?,
      callType: _callTypeFromExtra(event.extra?['callType']),
      extra: event.extra,
    );
  }

  CallType _callTypeFromExtra(Object? raw) {
    return raw == CallType.video.name ? CallType.video : CallType.audio;
  }

  Future<void> _startCallbackFromPendingAction() async {
    final action = _pendingStartupAction;
    if (action == null || _isCallActionInFlight) {
      return;
    }
    setState(() {
      _isCallActionInFlight = true;
    });

    final callbackCallId =
        '${action.callId}-callback-${DateTime.now().millisecondsSinceEpoch}';
    final roomType = _callbackSessionMode == CallbackSessionMode.conference
        ? _ExampleExtraKeys.roomTypeConference
        : _ExampleExtraKeys.roomTypeOneToOne;
    final callData = _buildCallData(
      callId: callbackCallId,
      callerName: action.callerName,
      handle: action.handle,
      avatarUrl: action.avatarUrl,
      callType: _callbackCallType,
      extraOverrides: <String, dynamic>{
        ...?action.extra,
        _ExampleExtraKeys.roomType: roomType,
      },
    );

    try {
      final session = CallwaveFlutter.instance.createSession(
        callData: callData,
        isOutgoing: true,
        initialState: CallSessionState.connecting,
      );
      if (_callbackSessionMode == CallbackSessionMode.conference) {
        _previewCallId = callbackCallId;
        _speakerCursor = 0;
        session.updateConferenceState(
          _buildPreviewConferenceState(
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
            callType: _callbackCallType,
          ),
        );
      } else {
        _previewCallId = null;
      }
      await CallwaveFlutter.instance.showOutgoingCall(callData);
      _pushLog(
        'Started callback ${_callbackCallType.name} for ${action.callerName} '
        '(${_callbackSessionMode.label.toLowerCase()}).',
      );
      if (mounted) {
        setState(() {
          _pendingStartupAction = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCallActionInFlight = false;
        });
      }
    }
  }
}

class _PendingStartupActionCard extends StatelessWidget {
  const _PendingStartupActionCard({
    required this.action,
    required this.callbackCallType,
    required this.callbackSessionMode,
    required this.actionInFlight,
    required this.onDismiss,
    required this.onCallTypeChanged,
    required this.onSessionModeChanged,
    required this.onStartCallback,
  });

  final CallStartupAction action;
  final CallType callbackCallType;
  final CallbackSessionMode callbackSessionMode;
  final bool actionInFlight;
  final VoidCallback onDismiss;
  final ValueChanged<CallType> onCallTypeChanged;
  final ValueChanged<CallbackSessionMode> onSessionModeChanged;
  final Future<void> Function() onStartCallback;

  @override
  Widget build(BuildContext context) {
    final isCallback = action.type == CallStartupActionType.callback;
    return Container(
      key: const ValueKey<String>('pending-startup-action-card'),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEECDB8)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x18C4441A),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Terracotta accent top bar
          Container(height: 4, color: const Color(0xFFC4441A)),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // Header row
                Row(
                  children: <Widget>[
                    Icon(
                      isCallback
                          ? Icons.phone_callback_rounded
                          : Icons.phone_missed_rounded,
                      color: const Color(0xFFC4441A),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isCallback ? 'CALLBACK REQUEST' : 'MISSED CALL',
                      style: const TextStyle(
                        color: Color(0xFFC4441A),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Caller info
                Row(
                  children: <Widget>[
                    const SizedBox(width: 28),
                    Text(
                      action.callerName,
                      key: const ValueKey<String>(
                          'pending-startup-action-summary'),
                      style: const TextStyle(
                        color: Color(0xFF191919),
                        fontWeight: FontWeight.w600,
                        fontSize: 17,
                      ),
                    ),
                    if (action.handle.isNotEmpty) ...<Widget>[
                      const SizedBox(width: 8),
                      Text(
                        action.handle,
                        style: const TextStyle(
                          color: Color(0xFF7A7267),
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ],
                ),
                if (!isCallback) ...<Widget>[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 28),
                    child: Text(
                      isCallback
                          ? 'Choose call type and session mode, then start the callback.'
                          : 'You have a missed call. Dismiss this card when ready.',
                      style: const TextStyle(
                        color: Color(0xFFB5AFA7),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onDismiss,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF7A7267),
                      ),
                      child: const Text('Dismiss'),
                    ),
                  ),
                ] else ...<Widget>[
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.only(left: 28),
                    child: Text(
                      'Choose call type and session mode, then start the callback.',
                      style: TextStyle(
                        color: Color(0xFFB5AFA7),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<CallType>(
                    showSelectedIcon: false,
                    segments: const <ButtonSegment<CallType>>[
                      ButtonSegment<CallType>(
                        value: CallType.audio,
                        label: Text('Audio'),
                        icon: Icon(Icons.mic_rounded, size: 16),
                      ),
                      ButtonSegment<CallType>(
                        value: CallType.video,
                        label: Text('Video'),
                        icon: Icon(Icons.videocam_rounded, size: 16),
                      ),
                    ],
                    selected: <CallType>{callbackCallType},
                    onSelectionChanged: actionInFlight
                        ? null
                        : (selection) => onCallTypeChanged(selection.first),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<CallbackSessionMode>(
                    showSelectedIcon: false,
                    segments: CallbackSessionMode.values
                        .map(
                          (mode) => ButtonSegment<CallbackSessionMode>(
                            value: mode,
                            label: Text(mode.label),
                          ),
                        )
                        .toList(growable: false),
                    selected: <CallbackSessionMode>{callbackSessionMode},
                    onSelectionChanged: actionInFlight
                        ? null
                        : (selection) =>
                            onSessionModeChanged(selection.first),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      TextButton(
                        onPressed: actionInFlight ? null : onDismiss,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF7A7267),
                        ),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        key: const ValueKey<String>('start-callback-button'),
                        onPressed: actionInFlight
                            ? null
                            : () => unawaited(onStartCallback()),
                        icon: const Icon(Icons.call_rounded, size: 16),
                        label: const Text('Start Callback'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFC4441A),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helper Widgets ──────────────────────────────────────────────────────────

class _QuickStartBanner extends StatelessWidget {
  // ignore: unused_element
  const _QuickStartBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFFFDF0EB), Color(0xFFFBF5F1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8C8B8)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.rocket_launch_rounded,
                  size: 17, color: Color(0xFFC4441A)),
              SizedBox(width: 8),
              Text(
                'QUICK START',
                style: TextStyle(
                  color: Color(0xFFC4441A),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          _QuickStartStep(
            number: '1',
            text: 'Grant Permissions — tap both buttons in the Permissions section.',
          ),
          SizedBox(height: 8),
          _QuickStartStep(
            number: '2',
            text: 'Set a Call ID above (or keep the default "demo-call-001").',
          ),
          SizedBox(height: 8),
          _QuickStartStep(
            number: '3',
            text: 'Pick an Incoming Flow Mode, then tap "Incoming Audio" to see the native call UI.',
          ),
          SizedBox(height: 8),
          _QuickStartStep(
            number: '4',
            text: 'Accept or decline the call — watch events appear in the Event Log.',
          ),
        ],
      ),
    );
  }
}

class _QuickStartStep extends StatelessWidget {
  const _QuickStartStep({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(
            color: Color(0xFFC4441A),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF3D3731),
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.accentColor,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color accentColor;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8E3DC)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Left accent bar
            Container(width: 3.5, color: accentColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // Section header
                    Row(
                      children: <Widget>[
                        Icon(icon, color: accentColor, size: 17),
                        const SizedBox(width: 8),
                        Text(
                          title,
                          style: TextStyle(
                            color: accentColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        if (trailing != null) ...<Widget>[
                          const Spacer(),
                          trailing!,
                        ],
                      ],
                    ),
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: 5),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: Color(0xFFB5AFA7),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    child,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;
    final effectiveColor =
        isEnabled ? color : color.withValues(alpha: 0.3);
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: effectiveColor,
        side: BorderSide(color: effectiveColor.withValues(alpha: 0.4)),
        backgroundColor: isEnabled
            ? color.withValues(alpha: 0.06)
            : const Color(0xFFF5F2EE),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 22, color: effectiveColor),
          const SizedBox(height: 5),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: effectiveColor,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _SubSectionLabel extends StatelessWidget {
  const _SubSectionLabel({
    required this.text,
    required this.color,
    this.hint,
  });

  final String text;
  final Color color;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 2.5,
              height: 14,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            const SizedBox(width: 7),
            Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
        if (hint != null) ...<Widget>[
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Text(
              hint!,
              style: const TextStyle(
                color: Color(0xFFB5AFA7),
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.locked,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final bool locked;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: locked ? null : onSelected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFC4441A)
              : const Color(0xFFF0ECE7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? const Color(0xFFC4441A)
                : const Color(0xFFD9D3CB),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Colors.white
                : locked
                    ? const Color(0xFFD9D3CB)
                    : const Color(0xFF3D3731),
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _PermissionButton extends StatelessWidget {
  const _PermissionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.hint,
  });

  final IconData icon;
  final String label;
  final String? hint;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;
    const color = Color(0xFFC27803);
    final effectiveColor =
        isEnabled ? color : color.withValues(alpha: 0.35);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18, color: effectiveColor),
          label: Text(
            label,
            style: TextStyle(
              color: effectiveColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(
              color: effectiveColor.withValues(alpha: 0.5),
            ),
            backgroundColor: isEnabled
                ? const Color(0xFFFFF8EB)
                : const Color(0xFFF5F2EE),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
        if (hint != null) ...<Widget>[
          const SizedBox(height: 5),
          Text(
            hint!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFB5AFA7),
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ],
      ],
    );
  }
}
