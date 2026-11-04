import 'package:callwave_flutter/callwave_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

const _data = CallData(callId: 'call', callerName: 'Ava', handle: '+1');

CallEvent _started([String token = 'attempt-1']) => CallEvent(
  callId: 'call',
  type: CallEventType.started,
  timestamp: DateTime.now(),
  extra: {CallEventExtraKeys.outgoingRingbackRequestId: token},
);

void main() {
  for (final screenFirst in [true, false]) {
    test(
      'readiness waits for both inputs (screenFirst=$screenFirst)',
      () async {
        final sent = <String>[];
        final session = CallSession(
          callData: _data,
          isOutgoing: true,
          reportOutgoingScreenVisible: (id) async {
            sent.add(id);
          },
        );
        addTearDown(session.dispose);
        if (screenFirst) {
          session.setCallScreenVisible(true);
        } else {
          await session.applyNativeEvent(_started());
        }
        expect(sent, isEmpty);
        if (screenFirst) {
          await session.applyNativeEvent(_started());
        } else {
          session.setCallScreenVisible(true);
        }
        expect(sent, ['attempt-1']);
        session.setCallScreenVisible(false);
        session.setCallScreenVisible(true);
        await session.applyNativeEvent(_started());
        await session.applyNativeEvent(_started('different-attempt'));
        expect(sent, ['attempt-1']);
      },
    );
  }

  test(
    'screen hidden before native preparation does not start sound',
    () async {
      final sent = <String>[];
      final session = CallSession(
        callData: _data,
        isOutgoing: true,
        reportOutgoingScreenVisible: (id) async {
          sent.add(id);
        },
      );
      addTearDown(session.dispose);
      session.setCallScreenVisible(true);
      session.setCallScreenVisible(false);
      await session.applyNativeEvent(_started());
      expect(sent, isEmpty);
      session.setCallScreenVisible(true);
      expect(sent, ['attempt-1']);
    },
  );

  for (final outcome in [
    'connected',
    'reconnecting',
    'failed',
    'ended',
    'cancelled',
    'disposed',
  ]) {
    test('$outcome before visibility prevents sound', () async {
      final sent = <String>[];
      final session = CallSession(
        callData: _data,
        isOutgoing: true,
        reportOutgoingScreenVisible: (id) async {
          sent.add(id);
        },
      );
      addTearDown(session.dispose);
      await session.applyNativeEvent(_started());
      switch (outcome) {
        case 'connected':
          session.reportConnected();
        case 'reconnecting':
          session.reportReconnecting();
        case 'failed':
          session.reportFailed();
        case 'ended':
          session.reportEnded();
        case 'cancelled':
          await session.end();
        case 'disposed':
          session.dispose();
      }
      session.setCallScreenVisible(true);
      await session.applyNativeEvent(_started());
      expect(sent, isEmpty);
    });
  }

  test('incoming sessions never signal outgoing sound', () async {
    final sent = <String>[];
    final session = CallSession(
      callData: _data,
      isOutgoing: false,
      reportOutgoingScreenVisible: (id) async {
        sent.add(id);
      },
    );
    addTearDown(session.dispose);
    session.setCallScreenVisible(true);
    await session.applyNativeEvent(_started());
    expect(sent, isEmpty);
  });
}
