import 'dart:async';

import 'package:callwave_flutter/callwave_flutter.dart';
import 'package:callwave_flutter_platform_interface/callwave_flutter_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakePlatform fakePlatform;

  setUp(() {
    fakePlatform = _FakePlatform();
    platform.CallwaveFlutterPlatform.instance = fakePlatform;
    CallwaveFlutter.instance.setEngine(_FakeEngine());
  });

  tearDown(() async {
    CallwaveFlutter.instance.setEngine(_FakeEngine());
    await fakePlatform.dispose();
  });

  test('showIncomingCall delegates to platform interface', () async {
    await CallwaveFlutter.instance.showIncomingCall(
      const CallData(callId: 'c1', callerName: 'Ava', handle: '+1'),
    );

    expect(fakePlatform.lastIncomingCallId, 'c1');
  });

  test('events are mapped to public model', () async {
    final completer = Completer<CallEvent>();
    final sub = CallwaveFlutter.instance.events.listen(completer.complete);

    fakePlatform.emit(
      const platform.CallEventDto(
        callId: 'c1',
        type: platform.CallEventType.accepted,
        timestampMs: 5000,
      ),
    );

    final event = await completer.future;
    await sub.cancel();

    expect(event.callId, 'c1');
    expect(event.type, CallEventType.accepted);
    expect(event.timestamp, DateTime.fromMillisecondsSinceEpoch(5000));
  });

  test('setPostCallBehavior delegates to platform interface', () async {
    await CallwaveFlutter.instance.setPostCallBehavior(
      PostCallBehavior.backgroundOnEnded,
    );

    expect(
      fakePlatform.postCallBehavior,
      platform.PostCallBehavior.backgroundOnEnded,
    );
  });

  test('engine mode creates session and invokes answer callback once',
      () async {
    final engine = _FakeEngine();
    final sessionFuture = CallwaveFlutter.instance.sessions.first;

    CallwaveFlutter.instance.setEngine(engine);
    fakePlatform.emit(
      platform.CallEventDto(
        callId: 'c-engine',
        type: platform.CallEventType.accepted,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        extra: const <String, dynamic>{
          'callerName': 'Ava',
          'handle': '+1 555 0101',
        },
      ),
    );

    final session = await sessionFuture;
    await Future<void>.delayed(Duration.zero);

    expect(session.callId, 'c-engine');
    expect(session.state, CallSessionState.connecting);
    expect(engine.answerCount, 1);

    fakePlatform.emit(
      platform.CallEventDto(
        callId: 'c-engine',
        type: platform.CallEventType.accepted,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(engine.answerCount, 1);
  });

  test('open ongoing launch action re-emits existing session for routing',
      () async {
    const callId = 'c-open-ongoing';
    final existing = CallwaveFlutter.instance.createSession(
      callData: const CallData(
        callId: callId,
        callerName: 'Ava',
        handle: '+1 555 0101',
      ),
      isOutgoing: false,
      initialState: CallSessionState.connecting,
    );

    final routedSessionFuture = CallwaveFlutter.instance.sessions.first;
    fakePlatform.emit(
      platform.CallEventDto(
        callId: callId,
        type: platform.CallEventType.accepted,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        extra: const <String, dynamic>{
          'launchAction':
              'com.callwave.flutter.methodchannel.ACTION_OPEN_ONGOING',
        },
      ),
    );

    final routedSession = await routedSessionFuture;
    expect(identical(routedSession, existing), isTrue);
  });

  test('started launchAction re-emits existing outgoing session for routing',
      () async {
    const callId = 'c-open-ongoing-started';
    final engine = _FakeEngine();
    CallwaveFlutter.instance.setEngine(engine);

    final existing = CallwaveFlutter.instance.createSession(
      callData: const CallData(
        callId: callId,
        callerName: 'Milo',
        handle: '+1 555 0202',
      ),
      isOutgoing: true,
      initialState: CallSessionState.connecting,
    );

    final routedSessionFuture = CallwaveFlutter.instance.sessions.first;
    fakePlatform.emit(
      platform.CallEventDto(
        callId: callId,
        type: platform.CallEventType.started,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        extra: const <String, dynamic>{
          'launchAction':
              'com.callwave.flutter.methodchannel.ACTION_OPEN_ONGOING',
        },
      ),
    );

    final routedSession = await routedSessionFuture;
    await Future<void>.delayed(Duration.zero);

    expect(identical(routedSession, existing), isTrue);
    expect(engine.startCount, 1);
    expect(engine.answerCount, 0);
  });

  test('restoreActiveSessions creates connecting session without engine hooks',
      () async {
    final engine = _FakeEngine();
    fakePlatform.activeCallIds = <String>['c-restore'];

    CallwaveFlutter.instance.setEngine(engine);
    await CallwaveFlutter.instance.restoreActiveSessions();

    final session = CallwaveFlutter.instance.getSession('c-restore');
    expect(session, isNotNull);
    expect(session!.state, CallSessionState.connecting);
    expect(engine.answerCount, 0);
    expect(engine.startCount, 0);
    expect(fakePlatform.getActiveCallEventSnapshotsCalled, isTrue);
  });

  test('restoreActiveSessions replays native snapshots for accepted calls',
      () async {
    final engine = _FakeEngine();
    fakePlatform.activeCallIds = <String>['c-restore-accepted'];
    fakePlatform.activeCallSnapshots = <platform.CallEventDto>[
      platform.CallEventDto(
        callId: 'c-restore-accepted',
        type: platform.CallEventType.accepted,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        extra: const <String, dynamic>{
          'callerName': 'Ava',
          'handle': '+1 555 0101',
        },
      ),
    ];

    CallwaveFlutter.instance.setEngine(engine);
    await CallwaveFlutter.instance.restoreActiveSessions();
    await Future<void>.delayed(Duration.zero);

    final session = CallwaveFlutter.instance.getSession('c-restore-accepted');
    expect(session, isNotNull);
    expect(session!.callData.callerName, 'Ava');
    expect(engine.answerCount, 1);
  });

  test('restoreActiveSessions keeps incoming session in ringing state',
      () async {
    final engine = _FakeEngine();
    fakePlatform.activeCallIds = <String>['c-restore-incoming'];
    fakePlatform.activeCallSnapshots = <platform.CallEventDto>[
      platform.CallEventDto(
        callId: 'c-restore-incoming',
        type: platform.CallEventType.incoming,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        extra: const <String, dynamic>{
          'callerName': 'Ava',
          'handle': '+1 555 0101',
        },
      ),
    ];

    CallwaveFlutter.instance.setEngine(engine);
    await CallwaveFlutter.instance.restoreActiveSessions();
    await Future<void>.delayed(Duration.zero);

    final session = CallwaveFlutter.instance.getSession('c-restore-incoming');
    expect(session, isNotNull);
    expect(session!.state, CallSessionState.ringing);
    expect(engine.answerCount, 0);
  });

  test('restoreActiveSessions replays native snapshots for started calls',
      () async {
    final engine = _FakeEngine();
    fakePlatform.activeCallIds = <String>['c-restore-started'];
    fakePlatform.activeCallSnapshots = <platform.CallEventDto>[
      platform.CallEventDto(
        callId: 'c-restore-started',
        type: platform.CallEventType.started,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        extra: const <String, dynamic>{
          'callerName': 'Milo',
          'handle': '+1 555 0202',
        },
      ),
    ];

    CallwaveFlutter.instance.setEngine(engine);
    await CallwaveFlutter.instance.restoreActiveSessions();
    await Future<void>.delayed(Duration.zero);

    final session = CallwaveFlutter.instance.getSession('c-restore-started');
    expect(session, isNotNull);
    expect(session!.callData.callerName, 'Milo');
    expect(session.isOutgoing, isTrue);
    expect(engine.startCount, 1);
    expect(engine.answerCount, 0);
  });

  test('prepareStartupRouteDecision opens call route for accepted startup',
      () async {
    final engine = _FakeEngine();
    fakePlatform.activeCallIds = <String>['c-startup-accepted'];
    fakePlatform.activeCallSnapshots = <platform.CallEventDto>[
      platform.CallEventDto(
        callId: 'c-startup-accepted',
        type: platform.CallEventType.accepted,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ),
    ];

    CallwaveFlutter.instance.setEngine(engine);
    final decision =
        await CallwaveFlutter.instance.prepareStartupRouteDecision();

    expect(decision.shouldOpenCall, isTrue);
    expect(decision.callId, 'c-startup-accepted');
    expect(decision.sessionState, CallSessionState.connecting);
  });

  test('prepareStartupRouteDecision opens call route for started startup',
      () async {
    final engine = _FakeEngine();
    fakePlatform.activeCallIds = <String>['c-startup-started'];
    fakePlatform.activeCallSnapshots = <platform.CallEventDto>[
      platform.CallEventDto(
        callId: 'c-startup-started',
        type: platform.CallEventType.started,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ),
    ];

    CallwaveFlutter.instance.setEngine(engine);
    final decision =
        await CallwaveFlutter.instance.prepareStartupRouteDecision();

    expect(decision.shouldOpenCall, isTrue);
    expect(decision.callId, 'c-startup-started');
    expect(decision.sessionState, CallSessionState.connecting);
  });

  test('prepareStartupRouteDecision stays on home for ringing-only startup',
      () async {
    final engine = _FakeEngine();
    fakePlatform.activeCallIds = <String>['c-startup-ringing'];
    fakePlatform.activeCallSnapshots = <platform.CallEventDto>[
      platform.CallEventDto(
        callId: 'c-startup-ringing',
        type: platform.CallEventType.incoming,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ),
    ];

    CallwaveFlutter.instance.setEngine(engine);
    final decision =
        await CallwaveFlutter.instance.prepareStartupRouteDecision();

    expect(decision.shouldOpenCall, isFalse);
    expect(decision.callId, isNull);
    expect(decision.sessionState, isNull);
  });
}

class _FakePlatform extends platform.CallwaveFlutterPlatform {
  final StreamController<platform.CallEventDto> _controller =
      StreamController<platform.CallEventDto>.broadcast();

  List<String> activeCallIds = const <String>[];
  List<platform.CallEventDto> activeCallSnapshots =
      const <platform.CallEventDto>[];
  bool getActiveCallEventSnapshotsCalled = false;
  bool syncActiveCallsToEventsCalled = false;
  String? lastIncomingCallId;
  platform.PostCallBehavior postCallBehavior =
      platform.PostCallBehavior.stayOpen;

  @override
  Stream<platform.CallEventDto> get events => _controller.stream;

  void emit(platform.CallEventDto event) {
    _controller.add(event);
  }

  Future<void> dispose() async {
    await _controller.close();
  }

  @override
  Future<void> endCall(String callId) async {}

  @override
  Future<void> acceptCall(String callId) async {}

  @override
  Future<void> declineCall(String callId) async {}

  @override
  Future<List<String>> getActiveCallIds() async => activeCallIds;

  @override
  Future<List<platform.CallEventDto>> getActiveCallEventSnapshots() async {
    getActiveCallEventSnapshotsCalled = true;
    return List<platform.CallEventDto>.of(activeCallSnapshots);
  }

  @override
  Future<void> syncActiveCallsToEvents() async {
    syncActiveCallsToEventsCalled = true;
    for (final event in activeCallSnapshots) {
      emit(event);
    }
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> markMissed(String callId) async {}

  @override
  Future<void> requestFullScreenIntentPermission() async {}

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<void> setPostCallBehavior(platform.PostCallBehavior behavior) async {
    postCallBehavior = behavior;
  }

  @override
  Future<void> showIncomingCall(platform.CallDataDto data) async {
    lastIncomingCallId = data.callId;
  }

  @override
  Future<void> showOutgoingCall(platform.CallDataDto data) async {}
}

class _FakeEngine extends CallwaveEngine {
  int answerCount = 0;
  int startCount = 0;

  @override
  Future<void> onAnswerCall(CallSession session) async {
    answerCount += 1;
  }

  @override
  Future<void> onStartCall(CallSession session) async {
    startCount += 1;
  }

  @override
  Future<void> onEndCall(CallSession session) async {}

  @override
  Future<void> onDeclineCall(CallSession session) async {}

  @override
  Future<void> onMuteChanged(CallSession session, bool muted) async {}

  @override
  Future<void> onSpeakerChanged(CallSession session, bool speakerOn) async {}

  @override
  Future<void> onCameraChanged(CallSession session, bool enabled) async {}

  @override
  Future<void> onCameraSwitch(CallSession session) async {}

  @override
  Future<void> onDispose(CallSession session) async {}
}
