import 'dart:async';

import 'package:callwave_flutter/callwave_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepted event invokes answer hook once', () async {
    final engine = _FakeEngine();
    final session = CallSession(
      callData: const CallData(
        callId: 'c-1',
        callerName: 'Ava',
        handle: '+1',
      ),
      isOutgoing: false,
      engineProvider: () => engine,
    );
    addTearDown(session.dispose);

    await session.applyNativeEvent(
      CallEvent(
        callId: 'c-1',
        type: CallEventType.accepted,
        timestamp: DateTime.now(),
      ),
    );
    await session.applyNativeEvent(
      CallEvent(
        callId: 'c-1',
        type: CallEventType.accepted,
        timestamp: DateTime.now(),
      ),
    );

    expect(session.state, CallSessionState.connecting);
    expect(engine.answerCount, 1);
  });

  test('mute failure reverts optimistic toggle without failing call', () async {
    final engine = _FakeEngine(throwOnMute: true);
    final session = CallSession(
      callData: const CallData(
        callId: 'c-2',
        callerName: 'Ava',
        handle: '+1',
      ),
      isOutgoing: false,
      engineProvider: () => engine,
    );
    addTearDown(session.dispose);

    expect(session.isMuted, isFalse);
    await session.toggleMute();

    expect(session.isMuted, isFalse);
    expect(session.state, isNot(CallSessionState.failed));
  });

  test('terminal states are absorbing', () async {
    final session = CallSession(
      callData: const CallData(
        callId: 'c-3',
        callerName: 'Ava',
        handle: '+1',
      ),
      isOutgoing: false,
    );
    addTearDown(session.dispose);

    session.reportEnded();
    await session.applyNativeEvent(
      CallEvent(
        callId: 'c-3',
        type: CallEventType.accepted,
        timestamp: DateTime.now(),
      ),
    );

    expect(session.state, CallSessionState.ended);
  });

  test('accepted event does not regress connected session to connecting',
      () async {
    final session = CallSession(
      callData: const CallData(
        callId: 'c-3b',
        callerName: 'Ava',
        handle: '+1',
      ),
      isOutgoing: false,
      initialState: CallSessionState.connected,
    );
    addTearDown(session.dispose);

    await session.applyNativeEvent(
      CallEvent(
        callId: 'c-3b',
        type: CallEventType.accepted,
        timestamp: DateTime.now(),
      ),
    );

    expect(session.state, CallSessionState.connected);
  });

  test('accept native failure transitions to failed', () async {
    final session = CallSession(
      callData: const CallData(
        callId: 'c-4',
        callerName: 'Ava',
        handle: '+1',
      ),
      isOutgoing: false,
      acceptNative: (_) async {
        throw StateError('No active incoming call');
      },
    );
    addTearDown(session.dispose);

    await session.accept();

    expect(session.state, CallSessionState.failed);
    expect(session.error, isNotNull);
  });

  test('conference updates ignore stale timestamps and dedupe by participantId',
      () {
    final session = CallSession(
      callData: const CallData(
        callId: 'c-5',
        callerName: 'Ava',
        handle: '+1',
      ),
      isOutgoing: false,
    );
    addTearDown(session.dispose);

    session.updateConferenceState(
      const ConferenceState(
        updatedAtMs: 10,
        activeSpeakerId: 'p-1',
        participants: [
          CallParticipant(
            participantId: 'p-1',
            displayName: 'Ava',
          ),
          CallParticipant(
            participantId: 'p-2',
            displayName: 'Milo',
          ),
          CallParticipant(
            participantId: 'p-1',
            displayName: 'Ava (latest)',
            isMuted: true,
          ),
        ],
      ),
    );

    expect(session.participantCount, 2);
    expect(
        session.conferenceState.participants.first.displayName, 'Ava (latest)');
    expect(session.conferenceState.participants.first.isMuted, isTrue);

    session.updateConferenceState(
      const ConferenceState(
        updatedAtMs: 9,
        participants: [
          CallParticipant(participantId: 'p-3', displayName: 'Nora'),
        ],
      ),
    );

    expect(session.participantCount, 2);
    expect(session.conferenceState.updatedAtMs, 10);
  });

  test('conference updates are ignored after terminal state', () {
    final session = CallSession(
      callData: const CallData(
        callId: 'c-6',
        callerName: 'Ava',
        handle: '+1',
      ),
      isOutgoing: false,
    );
    addTearDown(session.dispose);

    session.reportEnded();
    session.updateConferenceState(
      const ConferenceState(
        updatedAtMs: 11,
        participants: [
          CallParticipant(participantId: 'p-9', displayName: 'Late User'),
        ],
      ),
    );

    expect(session.participantCount, 0);
  });

  test('stale mute failure does not revert latest successful toggle', () async {
    final firstGate = Completer<void>();
    final secondGate = Completer<void>();
    var requestCount = 0;

    final engine = _FakeEngine(
      onMuteChangedHandler: (_, __) {
        requestCount += 1;
        return requestCount == 1
            ? _completeAfterGate(
                firstGate,
                shouldFail: true,
                errorMessage: 'late mute failure',
              )
            : _completeAfterGate(secondGate);
      },
    );
    final session = CallSession(
      callData: const CallData(
        callId: 'c-7',
        callerName: 'Ava',
        handle: '+1',
      ),
      isOutgoing: false,
      engineProvider: () => engine,
    );
    addTearDown(session.dispose);

    final firstToggle = session.toggleMute();
    expect(session.isMuted, isTrue);
    final secondToggle = session.toggleMute();
    expect(session.isMuted, isFalse);

    secondGate.complete();
    await secondToggle;
    firstGate.complete();
    await firstToggle;

    expect(session.isMuted, isFalse);
    expect(session.state, isNot(CallSessionState.failed));
  });

  test('stale speaker failure does not revert latest successful toggle',
      () async {
    final firstGate = Completer<void>();
    final secondGate = Completer<void>();
    var requestCount = 0;

    final engine = _FakeEngine(
      onSpeakerChangedHandler: (_, __) {
        requestCount += 1;
        return requestCount == 1
            ? _completeAfterGate(
                firstGate,
                shouldFail: true,
                errorMessage: 'late speaker failure',
              )
            : _completeAfterGate(secondGate);
      },
    );
    final session = CallSession(
      callData: const CallData(
        callId: 'c-8',
        callerName: 'Ava',
        handle: '+1',
      ),
      isOutgoing: false,
      engineProvider: () => engine,
    );
    addTearDown(session.dispose);

    final firstToggle = session.toggleSpeaker();
    expect(session.isSpeakerOn, isTrue);
    final secondToggle = session.toggleSpeaker();
    expect(session.isSpeakerOn, isFalse);

    secondGate.complete();
    await secondToggle;
    firstGate.complete();
    await firstToggle;

    expect(session.isSpeakerOn, isFalse);
    expect(session.state, isNot(CallSessionState.failed));
  });

  test('stale camera failure does not revert latest successful toggle',
      () async {
    final firstGate = Completer<void>();
    final secondGate = Completer<void>();
    var requestCount = 0;

    final engine = _FakeEngine(
      onCameraChangedHandler: (_, __) {
        requestCount += 1;
        return requestCount == 1
            ? _completeAfterGate(
                firstGate,
                shouldFail: true,
                errorMessage: 'late camera failure',
              )
            : _completeAfterGate(secondGate);
      },
    );
    final session = CallSession(
      callData: const CallData(
        callId: 'c-9',
        callerName: 'Ava',
        handle: '+1',
      ),
      isOutgoing: false,
      engineProvider: () => engine,
    );
    addTearDown(session.dispose);

    expect(session.isCameraOn, isTrue);
    final firstToggle = session.toggleCamera();
    expect(session.isCameraOn, isFalse);
    final secondToggle = session.toggleCamera();
    expect(session.isCameraOn, isTrue);

    secondGate.complete();
    await secondToggle;
    firstGate.complete();
    await firstToggle;

    expect(session.isCameraOn, isTrue);
    expect(session.state, isNot(CallSessionState.failed));
  });
}

Future<void> _completeAfterGate(
  Completer<void> gate, {
  bool shouldFail = false,
  String errorMessage = 'request failed',
}) async {
  await gate.future;
  if (shouldFail) {
    throw StateError(errorMessage);
  }
}

class _FakeEngine extends CallwaveEngine {
  _FakeEngine({
    this.throwOnMute = false,
    this.onMuteChangedHandler,
    this.onSpeakerChangedHandler,
    this.onCameraChangedHandler,
  });

  final bool throwOnMute;
  final Future<void> Function(CallSession session, bool muted)?
      onMuteChangedHandler;
  final Future<void> Function(CallSession session, bool speakerOn)?
      onSpeakerChangedHandler;
  final Future<void> Function(CallSession session, bool enabled)?
      onCameraChangedHandler;
  int answerCount = 0;

  @override
  Future<void> onAnswerCall(CallSession session) async {
    answerCount += 1;
  }

  @override
  Future<void> onMuteChanged(CallSession session, bool muted) async {
    final handler = onMuteChangedHandler;
    if (handler != null) {
      return handler(session, muted);
    }
    if (throwOnMute) {
      throw StateError('mute failed');
    }
  }

  @override
  Future<void> onStartCall(CallSession session) async {}

  @override
  Future<void> onEndCall(CallSession session) async {}

  @override
  Future<void> onDeclineCall(CallSession session) async {}

  @override
  Future<void> onSpeakerChanged(CallSession session, bool speakerOn) async {
    final handler = onSpeakerChangedHandler;
    if (handler != null) {
      return handler(session, speakerOn);
    }
  }

  @override
  Future<void> onCameraChanged(CallSession session, bool enabled) async {
    final handler = onCameraChangedHandler;
    if (handler != null) {
      return handler(session, enabled);
    }
  }

  @override
  Future<void> onCameraSwitch(CallSession session) async {}

  @override
  Future<void> onDispose(CallSession session) async {}
}
