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

  test(
      'validated incoming call uses defer-open strategy and registers background validator',
      () async {
    CallwaveFlutter.instance.configure(
      CallwaveConfiguration(
        engine: _FakeEngine(),
        incomingCallHandling: IncomingCallHandling.validated(
          validator: (_) async => const CallAcceptDecision.allow(),
        ),
        backgroundIncomingCallValidator: _backgroundIncomingCallValidator,
      ),
    );

    await CallwaveFlutter.instance.showIncomingCall(
      const CallData(callId: 'c-validated', callerName: 'Ava', handle: '+1'),
    );

    expect(
      fakePlatform.lastIncomingCallData?.incomingAcceptStrategy,
      platform.IncomingAcceptStrategy.deferOpenUntilConfirmed,
    );
    expect(fakePlatform.lastBackgroundDispatcherHandle, isNotNull);
    expect(fakePlatform.lastBackgroundCallbackHandle, isNotNull);
  });

  test('configure reports invalid background validator registration errors',
      () async {
    final capturedErrors = <Object>[];

    await runZonedGuarded(() async {
      CallwaveFlutter.instance.configure(
        CallwaveConfiguration(
          engine: _FakeEngine(),
          backgroundIncomingCallValidator: (request) async {
            return const CallAcceptDecision.allow();
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }, (error, _) {
      capturedErrors.add(error);
    });

    expect(capturedErrors.single, isA<ArgumentError>());
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

  test('CallData.copyWith can clear nullable fields', () {
    const original = CallData(
      callId: 'c-clear',
      callerName: 'Ava',
      handle: '+1',
      avatarUrl: 'https://x.test/avatar.png',
      extra: <String, dynamic>{'room': 'blue'},
    );

    final updated = original.copyWith(
      avatarUrl: null,
      extra: null,
    );

    expect(updated.avatarUrl, isNull);
    expect(updated.extra, isNull);
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

  test('validated handling keeps accepted session hidden until allowed',
      () async {
    final engine = _FakeEngine();
    final validationGate = Completer<CallAcceptDecision>();
    final sessionFuture = CallwaveFlutter.instance.sessions.first;

    CallwaveFlutter.instance.configure(
      CallwaveConfiguration(
        engine: engine,
        incomingCallHandling: IncomingCallHandling.validated(
          validator: (_) => validationGate.future,
        ),
      ),
    );
    fakePlatform.emit(
      platform.CallEventDto(
        callId: 'c-validated-allow',
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

    expect(session.state, CallSessionState.validating);
    expect(engine.answerCount, 0);
    expect(fakePlatform.confirmAcceptedCallCount, 0);

    validationGate.complete(const CallAcceptDecision.allow());
    await Future<void>.delayed(Duration.zero);

    expect(session.state, CallSessionState.connecting);
    expect(engine.answerCount, 1);
    expect(fakePlatform.confirmAcceptedCallCount, 1);
    expect(fakePlatform.lastConfirmedCallId, 'c-validated-allow');
  });

  test('validated rejection marks missed with an outcome reason', () async {
    final engine = _FakeEngine();
    final sessionFuture = CallwaveFlutter.instance.sessions.first;

    CallwaveFlutter.instance.configure(
      CallwaveConfiguration(
        engine: engine,
        incomingCallHandling: IncomingCallHandling.validated(
          validator: (_) async => const CallAcceptDecision.reject(
            reason: CallAcceptRejectReason.cancelled,
          ),
        ),
      ),
    );
    fakePlatform.emit(
      platform.CallEventDto(
        callId: 'c-validated-reject',
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
    await Future<void>.delayed(Duration.zero);

    expect(session.state, CallSessionState.ended);
    expect(engine.answerCount, 0);
    expect(fakePlatform.lastMarkedMissedCallId, 'c-validated-reject');
    expect(
      fakePlatform.lastMarkedMissedExtra?[CallEventExtraKeys.outcomeReason],
      CallAcceptRejectReason.cancelled.name,
    );
  });

  test('validated rejection still ends locally when markMissed throws',
      () async {
    final engine = _FakeEngine();
    final capturedErrors = <Object>[];
    fakePlatform.markMissedError = StateError('mark missed failed');

    await runZonedGuarded(() async {
      final sessionFuture = CallwaveFlutter.instance.sessions.first;

      CallwaveFlutter.instance.configure(
        CallwaveConfiguration(
          engine: engine,
          incomingCallHandling: IncomingCallHandling.validated(
            validator: (_) async => const CallAcceptDecision.reject(
              reason: CallAcceptRejectReason.cancelled,
            ),
          ),
        ),
      );
      fakePlatform.emit(
        platform.CallEventDto(
          callId: 'c-validated-mark-missed-failure',
          type: platform.CallEventType.accepted,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      final session = await sessionFuture;
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(session.state, CallSessionState.ended);
      expect(
        fakePlatform.lastMarkedMissedCallId,
        'c-validated-mark-missed-failure',
      );
    }, (error, _) {
      capturedErrors.add(error);
    });

    expect(capturedErrors, hasLength(1));
    expect(capturedErrors.single, isA<StateError>());
  });

  test('confirmAcceptedCall failures are reported and call is marked missed',
      () async {
    final capturedErrors = <Object>[];
    fakePlatform.confirmAcceptedCallError = StateError('confirm failed');

    await runZonedGuarded(() async {
      final sessionFuture = CallwaveFlutter.instance.sessions.first;

      CallwaveFlutter.instance.configure(
        CallwaveConfiguration(
          engine: _FakeEngine(),
          incomingCallHandling: IncomingCallHandling.validated(
            validator: (_) async => const CallAcceptDecision.allow(),
          ),
        ),
      );
      fakePlatform.emit(
        platform.CallEventDto(
          callId: 'c-confirm-failure',
          type: platform.CallEventType.accepted,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      final session = await sessionFuture;
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(session.state, CallSessionState.ended);
      expect(fakePlatform.lastMarkedMissedCallId, 'c-confirm-failure');
      expect(
        fakePlatform.lastMarkedMissedExtra?[CallEventExtraKeys.outcomeReason],
        CallAcceptRejectReason.unavailable.name,
      );
    }, (error, _) {
      capturedErrors.add(error);
    });

    expect(capturedErrors, hasLength(1));
    expect(capturedErrors.single, isA<StateError>());
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

  test('open incoming launch action re-emits existing ringing session',
      () async {
    const callId = 'c-open-incoming';
    final existing = CallwaveFlutter.instance.createSession(
      callData: const CallData(
        callId: callId,
        callerName: 'Ava',
        handle: '+1 555 0101',
      ),
      isOutgoing: false,
      initialState: CallSessionState.ringing,
    );

    final routedSessionFuture = CallwaveFlutter.instance.sessions.first;
    fakePlatform.emit(
      platform.CallEventDto(
        callId: callId,
        type: platform.CallEventType.incoming,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        extra: const <String, dynamic>{
          CallEventExtraKeys.launchAction:
              CallEventExtraKeys.launchActionOpenIncoming,
        },
      ),
    );

    final routedSession = await routedSessionFuture;
    expect(identical(routedSession, existing), isTrue);
    expect(routedSession.state, CallSessionState.ringing);
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
    expect(existing.state, CallSessionState.connecting);
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
    expect(decision.pendingAction, isNull);
  });

  test(
      'prepareStartupRouteDecision opens for explicit incoming startup without auto-answer',
      () async {
    final engine = _FakeEngine();
    fakePlatform.activeCallIds = <String>['c-startup-open-incoming'];
    fakePlatform.activeCallSnapshots = <platform.CallEventDto>[
      platform.CallEventDto(
        callId: 'c-startup-open-incoming',
        type: platform.CallEventType.incoming,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        extra: const <String, dynamic>{
          CallEventExtraKeys.launchAction:
              CallEventExtraKeys.launchActionOpenIncoming,
        },
      ),
    ];

    CallwaveFlutter.instance.setEngine(engine);
    final decision =
        await CallwaveFlutter.instance.prepareStartupRouteDecision();

    expect(decision.shouldOpenCall, isTrue);
    expect(decision.callId, 'c-startup-open-incoming');
    expect(decision.sessionState, CallSessionState.ringing);
    expect(engine.answerCount, 0);
  });

  test('prepareStartupRouteDecision stays home for validated rejected startup',
      () async {
    fakePlatform.activeCallIds = <String>['c-startup-validated-reject'];
    fakePlatform.activeCallSnapshots = <platform.CallEventDto>[
      platform.CallEventDto(
        callId: 'c-startup-validated-reject',
        type: platform.CallEventType.accepted,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        extra: const <String, dynamic>{
          'callerName': 'Ava',
          'handle': '+1 555 0101',
        },
      ),
    ];

    CallwaveFlutter.instance.configure(
      CallwaveConfiguration(
        engine: _FakeEngine(),
        incomingCallHandling: IncomingCallHandling.validated(
          validator: (_) async => const CallAcceptDecision.reject(
            reason: CallAcceptRejectReason.cancelled,
          ),
        ),
      ),
    );
    final decision =
        await CallwaveFlutter.instance.prepareStartupRouteDecision();

    expect(decision.shouldOpenCall, isFalse);
    expect(fakePlatform.lastMarkedMissedCallId, 'c-startup-validated-reject');
  });

  test('prepareStartupRouteDecision opens for validated approved startup',
      () async {
    fakePlatform.activeCallIds = <String>['c-startup-validated-allow'];
    fakePlatform.activeCallSnapshots = <platform.CallEventDto>[
      platform.CallEventDto(
        callId: 'c-startup-validated-allow',
        type: platform.CallEventType.accepted,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        extra: const <String, dynamic>{
          'callerName': 'Ava',
          'handle': '+1 555 0101',
        },
      ),
    ];

    CallwaveFlutter.instance.configure(
      CallwaveConfiguration(
        engine: _FakeEngine(),
        incomingCallHandling: IncomingCallHandling.validated(
          validator: (_) async => const CallAcceptDecision.allow(),
        ),
      ),
    );
    final decision =
        await CallwaveFlutter.instance.prepareStartupRouteDecision();

    expect(decision.shouldOpenCall, isTrue);
    expect(decision.callId, 'c-startup-validated-allow');
    expect(decision.sessionState, CallSessionState.connecting);
    expect(fakePlatform.lastConfirmedCallId, 'c-startup-validated-allow');
  });

  test('prepareStartupRouteDecision returns pending missed-call open action',
      () async {
    fakePlatform.pendingStartupAction = const platform.CallStartupActionDto(
      type: platform.CallStartupActionType.openMissedCall,
      callId: 'c-missed-open',
      callerName: 'Ava',
      handle: '+1 555 0101',
      extra: <String, dynamic>{'roomType': 'one-to-one'},
    );

    final decision =
        await CallwaveFlutter.instance.prepareStartupRouteDecision();

    expect(decision.shouldOpenCall, isFalse);
    expect(decision.callId, isNull);
    expect(decision.pendingAction, isNotNull);
    expect(
      decision.pendingAction!.type,
      CallStartupActionType.openMissedCall,
    );
    expect(decision.pendingAction!.callId, 'c-missed-open');
    expect(fakePlatform.takePendingStartupActionCount, 1);
  });

  test('prepareStartupRouteDecision returns pending callback action', () async {
    fakePlatform.pendingStartupAction = const platform.CallStartupActionDto(
      type: platform.CallStartupActionType.callback,
      callId: 'c-missed-callback',
      callerName: 'Ava',
      handle: '+1 555 0101',
      callType: platform.CallType.video,
      extra: <String, dynamic>{'roomType': 'conference'},
    );

    final decision =
        await CallwaveFlutter.instance.prepareStartupRouteDecision();

    expect(decision.shouldOpenCall, isFalse);
    expect(decision.pendingAction, isNotNull);
    expect(decision.pendingAction!.type, CallStartupActionType.callback);
    expect(decision.pendingAction!.callType, CallType.video);
    expect(
      decision.pendingAction!.extra,
      <String, dynamic>{'roomType': 'conference'},
    );
  });

  test('active startup session wins over pending missed-call action', () async {
    fakePlatform.activeCallIds = <String>['c-startup-accepted'];
    fakePlatform.activeCallSnapshots = <platform.CallEventDto>[
      platform.CallEventDto(
        callId: 'c-startup-accepted',
        type: platform.CallEventType.accepted,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ),
    ];
    fakePlatform.pendingStartupAction = const platform.CallStartupActionDto(
      type: platform.CallStartupActionType.callback,
      callId: 'c-missed-callback',
      callerName: 'Ava',
      handle: '+1 555 0101',
    );

    final decision =
        await CallwaveFlutter.instance.prepareStartupRouteDecision();

    expect(decision.shouldOpenCall, isTrue);
    expect(decision.callId, 'c-startup-accepted');
    expect(decision.pendingAction, isNull);
    expect(fakePlatform.pendingStartupAction, isNull);
  });

  test('validated accept does not reopen after terminal event wins the race',
      () async {
    final engine = _FakeEngine();
    final validationGate = Completer<CallAcceptDecision>();
    final sessionFuture = CallwaveFlutter.instance.sessions.first;

    CallwaveFlutter.instance.configure(
      CallwaveConfiguration(
        engine: engine,
        incomingCallHandling: IncomingCallHandling.validated(
          validator: (_) => validationGate.future,
        ),
      ),
    );
    fakePlatform.emit(
      platform.CallEventDto(
        callId: 'c-validation-race',
        type: platform.CallEventType.accepted,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    final session = await sessionFuture;
    await Future<void>.delayed(Duration.zero);
    expect(session.state, CallSessionState.validating);

    fakePlatform.emit(
      platform.CallEventDto(
        callId: 'c-validation-race',
        type: platform.CallEventType.ended,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    validationGate.complete(const CallAcceptDecision.allow());
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(session.state, CallSessionState.ended);
    expect(engine.answerCount, 0);
    expect(fakePlatform.confirmAcceptedCallCount, 0);
  });

  test('started event replaces lingering ended session with a fresh one',
      () async {
    const callId = 'c-reuse-after-ended';
    final endedSession = CallwaveFlutter.instance.createSession(
      callData: const CallData(
        callId: callId,
        callerName: 'Ava',
        handle: '+1 555 0101',
      ),
      isOutgoing: false,
      initialState: CallSessionState.connecting,
    );
    endedSession.reportEnded();
    await Future<void>.delayed(Duration.zero);

    final sessionFuture = CallwaveFlutter.instance.sessions.first;
    fakePlatform.emit(
      platform.CallEventDto(
        callId: callId,
        type: platform.CallEventType.started,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        extra: const <String, dynamic>{
          'callerName': 'Milo',
          'handle': '+1 555 0202',
        },
      ),
    );

    final routedSession = await sessionFuture;
    await Future<void>.delayed(Duration.zero);

    expect(identical(routedSession, endedSession), isFalse);
    expect(routedSession.isOutgoing, isTrue);
    expect(routedSession.state, CallSessionState.connecting);
    expect(routedSession.callData.callerName, 'Milo');
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
  platform.CallDataDto? lastIncomingCallData;
  String? lastConfirmedCallId;
  String? lastMarkedMissedCallId;
  Map<String, dynamic>? lastMarkedMissedExtra;
  int? lastBackgroundDispatcherHandle;
  int? lastBackgroundCallbackHandle;
  Object? markMissedError;
  Object? confirmAcceptedCallError;
  int confirmAcceptedCallCount = 0;
  int takePendingStartupActionCount = 0;
  platform.PostCallBehavior postCallBehavior =
      platform.PostCallBehavior.stayOpen;
  platform.CallStartupActionDto? pendingStartupAction;

  @override
  Stream<platform.CallEventDto> get events => _controller.stream;

  void emit(platform.CallEventDto event) {
    _controller.add(event);
  }

  Future<void> dispose() async {
    await _controller.close();
  }

  void _removeActiveCall(String callId) {
    activeCallIds = activeCallIds.where((id) => id != callId).toList();
    activeCallSnapshots = activeCallSnapshots
        .where((event) => event.callId != callId)
        .toList(growable: false);
  }

  @override
  Future<void> endCall(String callId) async {
    _removeActiveCall(callId);
  }

  @override
  Future<void> registerBackgroundIncomingCallValidator({
    required int backgroundDispatcherHandle,
    required int backgroundCallbackHandle,
  }) async {
    lastBackgroundDispatcherHandle = backgroundDispatcherHandle;
    lastBackgroundCallbackHandle = backgroundCallbackHandle;
  }

  @override
  Future<void> clearBackgroundIncomingCallValidator() async {
    lastBackgroundDispatcherHandle = null;
    lastBackgroundCallbackHandle = null;
  }

  @override
  Future<void> acceptCall(String callId) async {}

  @override
  Future<void> confirmAcceptedCall(String callId) async {
    confirmAcceptedCallCount += 1;
    lastConfirmedCallId = callId;
    final error = confirmAcceptedCallError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> declineCall(String callId) async {
    _removeActiveCall(callId);
  }

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
  Future<platform.CallStartupActionDto?> takePendingStartupAction() async {
    takePendingStartupActionCount += 1;
    final action = pendingStartupAction;
    pendingStartupAction = null;
    return action;
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> markMissed(
    String callId, {
    Map<String, dynamic>? extra,
  }) async {
    _removeActiveCall(callId);
    lastMarkedMissedCallId = callId;
    lastMarkedMissedExtra = extra;
    final error = markMissedError;
    if (error != null) {
      throw error;
    }
    emit(
      platform.CallEventDto(
        callId: callId,
        type: platform.CallEventType.missed,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        extra: extra,
      ),
    );
  }

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
    lastIncomingCallData = data;
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

Future<CallAcceptDecision> _backgroundIncomingCallValidator(
  BackgroundIncomingCallValidationRequest request,
) async {
  return CallAcceptDecision.allow(
    extra: <String, dynamic>{
      'validatedCallId': request.callId,
    },
  );
}
