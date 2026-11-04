import 'dart:async';

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
  final controlled = _data.copyWith(
    ringbackStartMode: RingbackStartMode.appControlled,
  );
  Future<void> flush() => Future<void>.delayed(Duration.zero);

  for (final order in ['permission-first', 'screen-first', 'before-native']) {
    test('app-controlled startup: $order, duplicates cannot restart', () async {
      final signals = <String>[];
      final session = CallSession(
        callData: controlled,
        isOutgoing: true,
        allowOutgoingRingbackNative: (id) async {
          signals.add('allow:$id');
        },
        reportOutgoingScreenVisible: (id) async {
          signals.add('visible:$id');
        },
      );
      addTearDown(session.dispose);
      if (order == 'before-native') {
        await session.allowOutgoingRingback();
        session.setCallScreenVisible(true);
        expect(signals, isEmpty);
      }
      await session.applyNativeEvent(_started());
      if (order == 'screen-first') {
        session.setCallScreenVisible(true);
        expect(signals, isEmpty);
        await session.allowOutgoingRingback();
      } else if (order == 'permission-first') {
        await session.allowOutgoingRingback();
        await flush();
        expect(signals, ['allow:attempt-1']);
        session.setCallScreenVisible(true);
      }
      await flush();
      expect(signals, ['allow:attempt-1', 'visible:attempt-1']);
      await session.allowOutgoingRingback();
      session.setCallScreenVisible(true);
      await session.applyNativeEvent(_started('stale-token'));
      await flush();
      expect(signals, ['allow:attempt-1', 'visible:attempt-1']);
    });
  }

  test('incoming sessions ignore explicit ringback permission', () async {
    final signals = <String>[];
    final session = CallSession(callData: controlled, isOutgoing: false,
      allowOutgoingRingbackNative: (id) async { signals.add(id); },
      reportOutgoingScreenVisible: (id) async { signals.add(id); });
    addTearDown(session.dispose);
    await session.applyNativeEvent(_started());
    session.setCallScreenVisible(true);
    await session.allowOutgoingRingback();
    await flush();
    expect(signals, isEmpty);
  });

  test('no permission is silent and does not block the lifecycle', () async {
    final signals = <String>[];
    final session = CallSession(
      callData: controlled,
      isOutgoing: true,
      reportOutgoingScreenVisible: (id) async {
        signals.add(id);
      },
    );
    addTearDown(session.dispose);
    session.setCallScreenVisible(true);
    await session.applyNativeEvent(_started());
    expect(session.state, CallSessionState.connecting);
    session.reportConnected();
    expect(session.state, CallSessionState.connected);
    session.reportEnded();
    await session.allowOutgoingRingback();
    expect(session.state, CallSessionState.ended);
    expect(signals, isEmpty);
  });

  for (final mode in RingbackStartMode.values) {
    test('playRingback false suppresses all startup in $mode', () async {
      final signals = <String>[];
      final session = CallSession(
        callData: controlled.copyWith(
          playRingback: false,
          ringbackStartMode: mode,
        ),
        isOutgoing: true,
        allowOutgoingRingbackNative: (id) async {
          signals.add(id);
        },
        reportOutgoingScreenVisible: (id) async {
          signals.add(id);
        },
      );
      addTearDown(session.dispose);
      session.setCallScreenVisible(true);
      await session.applyNativeEvent(_started());
      await session.allowOutgoingRingback();
      await flush();
      expect(signals, isEmpty);
      expect(session.state, CallSessionState.connecting);
    });
  }

  for (final outcome in [
    'hidden',
    'connected',
    'ended',
    'failed',
    'disposed',
  ]) {
    test(
      '$outcome while permission acknowledgment is pending rejects startup',
      () async {
        final gate = Completer<void>();
        final signals = <String>[];
        final session = CallSession(
          callData: controlled,
          isOutgoing: true,
          allowOutgoingRingbackNative: (_) => gate.future,
          reportOutgoingScreenVisible: (id) async {
            signals.add(id);
          },
        );
        addTearDown(session.dispose);
        await session.applyNativeEvent(_started());
        session.setCallScreenVisible(true);
        // This must finish even though the native acknowledgment is still pending.
        await session.allowOutgoingRingback();
        switch (outcome) {
          case 'hidden':
            session.setCallScreenVisible(false);
          case 'connected':
            session.reportConnected();
          case 'ended':
            session.reportEnded();
          case 'failed':
            session.reportFailed();
          case 'disposed':
            session.dispose();
        }
        gate.complete();
        await flush();
        expect(signals, isEmpty);
        if (outcome == 'hidden') {
          session.setCallScreenVisible(true);
          expect(signals, ['attempt-1']);
        }
      },
    );
  }

  test(
    'hidden signal revokes pending visibility without revoking permission',
    () async {
      final signals = <String>[];
      final session = CallSession(
        callData: controlled,
        isOutgoing: true,
        allowOutgoingRingbackNative: (id) async {
          signals.add('allow');
        },
        reportOutgoingScreenVisible: (id) async {
          signals.add('visible');
        },
        reportOutgoingScreenHidden: (id) async {
          signals.add('hidden');
        },
      );
      addTearDown(session.dispose);
      await session.applyNativeEvent(_started());
      await session.allowOutgoingRingback();
      await flush();
      session.setCallScreenVisible(true);
      session.setCallScreenVisible(false);
      session.setCallScreenVisible(false);
      session.setCallScreenVisible(true);
      expect(signals, ['allow', 'visible', 'hidden', 'visible']);
    },
  );

  test('restored tokenless call stays silent even after permission', () async {
    final signals = <String>[];
    final session = CallSession(
      callData: controlled,
      isOutgoing: true,
      initialState: CallSessionState.reconnecting,
      allowOutgoingRingbackNative: (id) async {
        signals.add(id);
      },
      reportOutgoingScreenVisible: (id) async {
        signals.add(id);
      },
    );
    addTearDown(session.dispose);
    session.setCallScreenVisible(true);
    await session.allowOutgoingRingback();
    await session.applyNativeEvent(
      CallEvent(
        callId: 'call',
        type: CallEventType.started,
        timestamp: DateTime.now(),
      ),
    );
    await flush();
    expect(signals, isEmpty);
  });

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
