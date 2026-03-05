import 'dart:async';

import 'package:callwave_flutter/callwave_flutter.dart';
import 'package:callwave_flutter_example/mock_callwave_engine.dart';
import 'package:flutter/material.dart';

final MockCallwaveEngine _engine = MockCallwaveEngine();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  CallwaveFlutter.instance.setEngine(_engine);
  final startupDecision =
      await CallwaveFlutter.instance.prepareStartupRouteDecision();
  runApp(CallwaveExampleApp(startupDecision: startupDecision));
}

abstract final class _Routes {
  static const String home = '/home';
  static const String call = '/call';
}

class CallwaveExampleApp extends StatefulWidget {
  const CallwaveExampleApp({
    CallStartupRouteDecision? startupDecision,
    super.key,
  }) : startupDecision =
            startupDecision ?? const CallStartupRouteDecision.home();

  final CallStartupRouteDecision startupDecision;

  @override
  State<CallwaveExampleApp> createState() => _CallwaveExampleAppState();
}

class _CallwaveExampleAppState extends State<CallwaveExampleApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final Set<String> _preRoutedCallIds =
      widget.startupDecision.callId == null
          ? const <String>{}
          : <String>{widget.startupDecision.callId!};

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
          child: child ?? const SizedBox.shrink(),
        );
      },
      initialRoute:
          widget.startupDecision.shouldOpenCall ? _Routes.call : _Routes.home,
      routes: <String, WidgetBuilder>{
        _Routes.home: (_) => const CallDemoScreen(),
        _Routes.call: (_) => _StartupCallRoute(
              startupDecision: widget.startupDecision,
            ),
      },
    );
  }
}

class _StartupCallRoute extends StatelessWidget {
  const _StartupCallRoute({
    required this.startupDecision,
  });

  final CallStartupRouteDecision startupDecision;

  @override
  Widget build(BuildContext context) {
    final callId = startupDecision.callId;
    if (callId == null) {
      return const CallDemoScreen();
    }

    final session = CallwaveFlutter.instance.getSession(callId);
    if (session == null || session.isEnded) {
      return const CallDemoScreen();
    }

    return InheritedCallSession(
      session: session,
      child: CallScreen(
        session: session,
        onCallEnded: () {
          Navigator.of(context).pushReplacementNamed(_Routes.home);
        },
      ),
    );
  }
}

class CallDemoScreen extends StatefulWidget {
  const CallDemoScreen({super.key});

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
  StreamSubscription<CallEvent>? _subscription;
  bool _isCallActionInFlight = false;
  String? _previewCallId;
  int _speakerCursor = 0;

  @override
  void initState() {
    super.initState();
    _subscription = CallwaveFlutter.instance.events.listen(_onCallEvent);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _callIdController.dispose();
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
    return Scaffold(
      appBar: AppBar(title: const Text('Callwave Example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _callIdController,
              decoration: const InputDecoration(labelText: 'Call ID'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ElevatedButton(
                  onPressed:
                      callId.isEmpty ? null : _requestNotificationPermission,
                  child: const Text('Notif Permission'),
                ),
                ElevatedButton(
                  onPressed:
                      callId.isEmpty ? null : _requestFullScreenPermission,
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
                  onPressed: callId.isEmpty ? null : () => _endCall(callId),
                  child: const Text('End call'),
                ),
                ElevatedButton(
                  onPressed: callId.isEmpty ? null : () => _markMissed(callId),
                  child: const Text('Missed'),
                ),
                ElevatedButton(
                  onPressed: callId.isEmpty
                      ? null
                      : () => _openConferencePreview(callId),
                  child: const Text('Conference Preview'),
                ),
                ElevatedButton(
                  onPressed:
                      _previewCallId == null ? null : _cycleConferenceSpeaker,
                  child: const Text('Cycle Speaker'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Events'),
            const SizedBox(height: 8),
            Expanded(
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
  }) {
    return CallData(
      callId: callId,
      callerName: callerName,
      handle: handle,
      timeout: const Duration(seconds: 30),
      callType: callType,
      extra: <String, dynamic>{
        'callerName': callerName,
        'handle': handle,
        'callType': callType.name,
      },
    );
  }

  Future<void> _endCall(String callId) async {
    await CallwaveFlutter.instance.endCall(callId);
  }

  Future<void> _markMissed(String callId) async {
    await CallwaveFlutter.instance.markMissed(callId);
  }

  void _openConferencePreview(String callIdSeed) {
    final callId =
        '$callIdSeed-conference-${DateTime.now().millisecondsSinceEpoch}';
    final session = CallwaveFlutter.instance.createSession(
      callData: CallData(
        callId: callId,
        callerName: 'Conference',
        handle: 'group room',
        timeout: const Duration(seconds: 45),
        callType: CallType.video,
        extra: const <String, dynamic>{
          'callerName': 'Conference',
          'handle': 'group room',
          'callType': 'video',
        },
      ),
      isOutgoing: true,
      initialState: CallSessionState.connected,
    );

    _previewCallId = callId;
    _speakerCursor = 0;
    session.updateConferenceState(_buildPreviewConferenceState(updatedAtMs: 1));
    _pushLog('Conference preview started for $callId');
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
    session.updateConferenceState(
      _buildPreviewConferenceState(updatedAtMs: updatedAtMs),
    );
    _pushLog('Conference speaker changed.');
  }

  ConferenceState _buildPreviewConferenceState({required int updatedAtMs}) {
    const participants = <CallParticipant>[
      CallParticipant(
        participantId: 'speaker-1',
        displayName: 'Ava',
        isVideoOn: true,
        sortOrder: 1,
      ),
      CallParticipant(
        participantId: 'speaker-2',
        displayName: 'Milo',
        isVideoOn: true,
        sortOrder: 2,
      ),
      CallParticipant(
        participantId: 'speaker-3',
        displayName: 'Nora',
        isVideoOn: true,
        sortOrder: 3,
      ),
      CallParticipant(
        participantId: 'local-you',
        displayName: 'You',
        isLocal: true,
        isVideoOn: true,
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
