import 'dart:async';

import 'package:callwave_flutter/callwave_flutter.dart';
import 'package:callwave_flutter_example/mock_callwave_engine.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const CallwaveExampleApp());
}

class CallwaveExampleApp extends StatefulWidget {
  const CallwaveExampleApp({super.key});

  @override
  State<CallwaveExampleApp> createState() => _CallwaveExampleAppState();
}

class _CallwaveExampleAppState extends State<CallwaveExampleApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

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
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const CallDemoScreen(),
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

  final MockCallwaveEngine _engine = MockCallwaveEngine();
  final List<String> _eventLog = <String>[];
  final TextEditingController _callIdController =
      TextEditingController(text: 'demo-call-001');
  StreamSubscription<CallEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    CallwaveFlutter.instance.setEngine(_engine);
    unawaited(CallwaveFlutter.instance.restoreActiveSessions());
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
                  onPressed:
                      callId.isEmpty ? null : () => _showIncoming(callId),
                  child: const Text('Incoming'),
                ),
                ElevatedButton(
                  onPressed:
                      callId.isEmpty ? null : () => _showOutgoing(callId),
                  child: const Text('Outgoing'),
                ),
                ElevatedButton(
                  onPressed: callId.isEmpty ? null : () => _endCall(callId),
                  child: const Text('End'),
                ),
                ElevatedButton(
                  onPressed: callId.isEmpty ? null : () => _markMissed(callId),
                  child: const Text('Missed'),
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

  Future<void> _showIncoming(String callId) async {
    await CallwaveFlutter.instance.showIncomingCall(
      CallData(
        callId: callId,
        callerName: _incomingCallerName,
        handle: _incomingHandle,
        timeout: const Duration(seconds: 30),
        callType: CallType.audio,
        extra: const <String, dynamic>{
          'callerName': _incomingCallerName,
          'handle': _incomingHandle,
          'callType': 'audio',
        },
      ),
    );
  }

  Future<void> _showOutgoing(String callId) async {
    await CallwaveFlutter.instance.showOutgoingCall(
      CallData(
        callId: callId,
        callerName: _outgoingCallerName,
        handle: _outgoingHandle,
        timeout: const Duration(seconds: 30),
        callType: CallType.video,
        extra: const <String, dynamic>{
          'callerName': _outgoingCallerName,
          'handle': _outgoingHandle,
          'callType': 'video',
        },
      ),
    );
  }

  Future<void> _endCall(String callId) async {
    await CallwaveFlutter.instance.endCall(callId);
  }

  Future<void> _markMissed(String callId) async {
    await CallwaveFlutter.instance.markMissed(callId);
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
