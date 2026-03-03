import 'dart:async';

import 'package:callwave_flutter/callwave_flutter.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const CallwaveExampleApp());
}

class CallwaveExampleApp extends StatelessWidget {
  const CallwaveExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Callwave Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
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
  static const String _demoSource = 'example';
  static const String _incomingCallerName = 'Ava';
  static const String _incomingHandle = '+1 555 0101';
  static const String _outgoingCallerName = 'Milo';
  static const String _outgoingHandle = '+1 555 0202';

  final List<String> _eventLog = <String>[];
  final Map<String, CallData> _callsById = <String, CallData>{};
  final TextEditingController _callIdController =
      TextEditingController(text: 'demo-call-001');
  StreamSubscription<CallEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = CallwaveFlutter.instance.events.listen(_onCallEvent);
  }

  void _onCallEvent(CallEvent event) {
    if (!mounted) return;

    setState(() {
      _eventLog.insert(
        0,
        '${event.timestamp.toIso8601String()} ${event.callId} ${event.type.name}',
      );
    });

    switch (event.type) {
      case CallEventType.accepted:
        final callData = _callsById[event.callId] ?? _callDataFromEvent(event);
        _callsById[event.callId] = callData;
        _openCallScreen(callData: callData, isOutgoing: false);
        break;
      case CallEventType.ended:
      case CallEventType.declined:
      case CallEventType.timeout:
      case CallEventType.missed:
        _callsById.remove(event.callId);
        break;
      case CallEventType.started:
      case CallEventType.callback:
        break;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _callIdController.dispose();
    super.dispose();
  }

  void _openCallScreen({
    required CallData callData,
    required bool isOutgoing,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CallScreen(
          callData: callData,
          isOutgoing: isOutgoing,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final callId = _callIdController.text.trim();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Callwave Example'),
      ),
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
                  onPressed: callId.isEmpty ? null : _setPostCallStayOpen,
                  child: const Text('Stay Open'),
                ),
                ElevatedButton(
                  onPressed:
                      callId.isEmpty ? null : _setPostCallBackgroundOnEnd,
                  child: const Text('Bg On End'),
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
            const Text(
              'Cold-start test: send an incoming call, swipe app away, tap Accept on the full-screen call UI, then reopen app and check logs.',
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

  Future<void> _setPostCallStayOpen() async {
    await CallwaveFlutter.instance
        .setPostCallBehavior(PostCallBehavior.stayOpen);
    _pushLog('Post-call behavior set to stayOpen.');
  }

  Future<void> _setPostCallBackgroundOnEnd() async {
    await CallwaveFlutter.instance.setPostCallBehavior(
      PostCallBehavior.backgroundOnEnded,
    );
    _pushLog('Post-call behavior set to backgroundOnEnded.');
  }

  Future<void> _showIncoming(String callId) async {
    final callData = _buildIncomingCallData(callId);
    _callsById[callId] = callData;
    await CallwaveFlutter.instance.showIncomingCall(callData);
  }

  Future<void> _showOutgoing(String callId) async {
    final callData = _buildOutgoingCallData(callId);
    _callsById[callId] = callData;
    await CallwaveFlutter.instance.showOutgoingCall(callData);
    if (mounted) {
      _openCallScreen(callData: callData, isOutgoing: true);
    }
  }

  Future<void> _endCall(String callId) async {
    await CallwaveFlutter.instance.endCall(callId);
  }

  Future<void> _markMissed(String callId) async {
    await CallwaveFlutter.instance.markMissed(callId);
  }

  void _pushLog(String value) {
    if (!mounted) return;

    setState(() {
      _eventLog.insert(0, '${DateTime.now().toIso8601String()} $value');
    });
  }

  CallData _buildIncomingCallData(String callId) {
    return CallData(
      callId: callId,
      callerName: _incomingCallerName,
      handle: _incomingHandle,
      timeout: const Duration(seconds: 30),
      callType: CallType.audio,
      extra: _buildDemoExtra(
        callerName: _incomingCallerName,
        handle: _incomingHandle,
        callType: CallType.audio,
      ),
    );
  }

  CallData _buildOutgoingCallData(String callId) {
    return CallData(
      callId: callId,
      callerName: _outgoingCallerName,
      handle: _outgoingHandle,
      timeout: const Duration(seconds: 30),
      callType: CallType.video,
      extra: _buildDemoExtra(
        callerName: _outgoingCallerName,
        handle: _outgoingHandle,
        callType: CallType.video,
      ),
    );
  }

  Map<String, dynamic> _buildDemoExtra({
    required String callerName,
    required String handle,
    required CallType callType,
  }) {
    return <String, dynamic>{
      'source': _demoSource,
      'callerName': callerName,
      'handle': handle,
      'callType': callType.name,
    };
  }

  CallData _callDataFromEvent(CallEvent event) {
    final fallback = _buildIncomingCallData(event.callId);
    final callerName =
        _readNonEmptyString(event.extra, 'callerName') ?? fallback.callerName;
    final handle =
        _readNonEmptyString(event.extra, 'handle') ?? fallback.handle;
    final callType =
        _readCallType(event.extra?['callType']) ?? fallback.callType;

    return CallData(
      callId: event.callId,
      callerName: callerName,
      handle: handle,
      callType: callType,
      extra: event.extra ?? fallback.extra,
    );
  }

  String? _readNonEmptyString(Map<String, dynamic>? map, String key) {
    final value = map?[key];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  CallType? _readCallType(Object? raw) {
    if (raw is! String) return null;
    for (final callType in CallType.values) {
      if (callType.name == raw) {
        return callType;
      }
    }
    return null;
  }
}
