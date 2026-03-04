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
}

class _FakeEngine extends CallwaveEngine {
  _FakeEngine({this.throwOnMute = false});

  final bool throwOnMute;
  int answerCount = 0;

  @override
  Future<void> onAnswerCall(CallSession session) async {
    answerCount += 1;
  }

  @override
  Future<void> onMuteChanged(CallSession session, bool muted) async {
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
  Future<void> onSpeakerChanged(CallSession session, bool speakerOn) async {}

  @override
  Future<void> onCameraChanged(CallSession session, bool enabled) async {}

  @override
  Future<void> onCameraSwitch(CallSession session) async {}

  @override
  Future<void> onDispose(CallSession session) async {}
}
