import 'package:callwave_flutter/callwave_flutter.dart';
import 'package:callwave_flutter_example/startup/startup_call_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recovers accepted event for active call id', () {
    final recovered = recoverAcceptedEventsFromActiveIds(
      activeCallIds: const <String>['c-1'],
      acceptedCallIds: <String>{},
      incomingCallIds: <String>{},
      knownCallsById: <String, CallData>{},
      timestamp: DateTime.fromMillisecondsSinceEpoch(10),
    );

    expect(recovered.length, 1);
    expect(recovered.first.callId, 'c-1');
    expect(recovered.first.type, CallEventType.accepted);
  });

  test('does not recover when call is already accepted', () {
    final recovered = recoverAcceptedEventsFromActiveIds(
      activeCallIds: const <String>['c-1'],
      acceptedCallIds: <String>{'c-1'},
      incomingCallIds: <String>{},
      knownCallsById: <String, CallData>{},
      timestamp: DateTime.fromMillisecondsSinceEpoch(10),
    );

    expect(recovered, isEmpty);
  });

  test('does not recover when incoming state already exists', () {
    final recovered = recoverAcceptedEventsFromActiveIds(
      activeCallIds: const <String>['c-1'],
      acceptedCallIds: <String>{},
      incomingCallIds: <String>{'c-1'},
      knownCallsById: <String, CallData>{},
      timestamp: DateTime.fromMillisecondsSinceEpoch(10),
    );

    expect(recovered, isEmpty);
  });
}
