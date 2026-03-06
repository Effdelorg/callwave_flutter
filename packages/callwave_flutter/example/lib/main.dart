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
  validatedReject('Validated Reject');

  const IncomingDemoMode(this.label);

  final String label;
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
    IncomingDemoMode.realtime => const IncomingCallHandling.realtime(),
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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
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
      );
    }

    final session = CallwaveFlutter.instance.getSession(callId);
    if (session == null || session.isEnded) {
      return CallDemoScreen(
        engine: engine,
        initialIncomingDemoMode: initialIncomingDemoMode,
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
    super.key,
  });

  final CallwaveEngine engine;
  final IncomingDemoMode initialIncomingDemoMode;

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

  @override
  void initState() {
    super.initState();
    _missedNotificationTextController.text = 'You missed a call from {name}.';
    _subscription = CallwaveFlutter.instance.events.listen(_onCallEvent);
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
      appBar: AppBar(title: const Text('Callwave Example')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextField(
                      controller: _callIdController,
                      decoration: const InputDecoration(labelText: 'Call ID'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _missedNotificationTextController,
                      decoration: const InputDecoration(
                        labelText: 'Missed Notification Text',
                        hintText: 'You missed a call from {name}.',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Incoming Flow: ${_incomingDemoMode.label}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<IncomingDemoMode>(
                      showSelectedIcon: false,
                      segments: IncomingDemoMode.values
                          .map(
                            (mode) => ButtonSegment<IncomingDemoMode>(
                              value: mode,
                              label: Text(mode.label),
                            ),
                          )
                          .toList(growable: false),
                      selected: <IncomingDemoMode>{_incomingDemoMode},
                      onSelectionChanged: incomingModeLocked
                          ? null
                          : (selection) {
                              final nextMode = selection.first;
                              if (nextMode == _incomingDemoMode) {
                                return;
                              }
                              setState(() {
                                _incomingDemoMode = nextMode;
                              });
                              unawaited(
                                persistIncomingDemoMode(nextMode),
                              );
                              _applyIncomingMode();
                            },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _incomingModeDescription,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        ElevatedButton(
                          onPressed: callId.isEmpty
                              ? null
                              : _requestNotificationPermission,
                          child: const Text('Notif Permission'),
                        ),
                        ElevatedButton(
                          onPressed: callId.isEmpty
                              ? null
                              : _requestFullScreenPermission,
                          child: const Text('FullScreen Permission'),
                        ),
                        ElevatedButton(
                          onPressed: callId.isEmpty || _isCallActionInFlight
                              ? null
                              : () => _showCall(
                                    callId: callId,
                                    isIncoming: true,
                                    callType: CallType.audio,
                                  ),
                          child: const Text('Incoming Audio'),
                        ),
                        ElevatedButton(
                          onPressed: callId.isEmpty || _isCallActionInFlight
                              ? null
                              : () => _showCall(
                                    callId: callId,
                                    isIncoming: true,
                                    callType: CallType.video,
                                  ),
                          child: const Text('Incoming Video'),
                        ),
                        ElevatedButton(
                          onPressed: callId.isEmpty || _isCallActionInFlight
                              ? null
                              : () => _showCall(
                                    callId: callId,
                                    isIncoming: false,
                                    callType: CallType.audio,
                                  ),
                          child: const Text('Outgoing Audio'),
                        ),
                        ElevatedButton(
                          onPressed: callId.isEmpty || _isCallActionInFlight
                              ? null
                              : () => _showCall(
                                    callId: callId,
                                    isIncoming: false,
                                    callType: CallType.video,
                                  ),
                          child: const Text('Outgoing Video'),
                        ),
                        ElevatedButton(
                          onPressed:
                              callId.isEmpty ? null : () => _endCall(callId),
                          child: const Text('End call'),
                        ),
                        ElevatedButton(
                          onPressed:
                              callId.isEmpty ? null : () => _markMissed(callId),
                          child: const Text('Missed'),
                        ),
                        ElevatedButton(
                          onPressed: callId.isEmpty
                              ? null
                              : () => _openConferencePreview(
                                  callId, CallType.audio),
                          child: const Text('Conference Audio'),
                        ),
                        ElevatedButton(
                          onPressed: callId.isEmpty
                              ? null
                              : () => _openConferencePreview(
                                  callId, CallType.video),
                          child: const Text('Conference Video'),
                        ),
                        ElevatedButton(
                          onPressed: _previewCallId == null
                              ? null
                              : _cycleConferenceSpeaker,
                          child: const Text('Cycle Speaker'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Events'),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 220,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.black26),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView.builder(
                          itemCount: _eventLog.length,
                          itemBuilder: (context, index) {
                            return ListTile(
                              dense: true,
                              title: Text(
                                _eventLog[index],
                                style: const TextStyle(fontSize: 13),
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
  }) {
    final customMissedNotificationText =
        _resolvedMissedNotificationText(callerName);
    return CallData(
      callId: callId,
      callerName: callerName,
      handle: handle,
      timeout: timeout,
      callType: callType,
      extra: <String, dynamic>{
        'callerName': callerName,
        'handle': handle,
        'callType': callType.name,
        CallDataExtraKeys.androidMissedCallNotificationText:
            customMissedNotificationText,
      },
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
}
