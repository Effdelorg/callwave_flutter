import 'dart:async';

import 'package:callwave_flutter_platform_interface/callwave_flutter_platform_interface.dart'
    as platform;
import 'package:callwave_flutter_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakePlatform fakePlatform;

  setUp(() {
    fakePlatform = _FakePlatform();
    platform.CallwaveFlutterPlatform.instance = fakePlatform;
  });

  tearDown(() async {
    await fakePlatform.dispose();
  });

  testWidgets('cold-start accepted opens joined call UI safely', (
    tester,
  ) async {
    fakePlatform.initialEventTypes = <platform.CallEventType>[
      platform.CallEventType.accepted,
    ];

    await tester.pumpWidget(const CallwaveExampleApp());
    await _pumpToJoinedFlowFrame(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Mute'), findsOneWidget);
    await _disposeRenderedApp(tester);
  });

  testWidgets('queued incoming then accepted opens one joined-flow screen', (
    tester,
  ) async {
    fakePlatform.initialEventTypes = <platform.CallEventType>[
      platform.CallEventType.incoming,
      platform.CallEventType.accepted,
    ];

    await tester.pumpWidget(const CallwaveExampleApp());
    await _pumpToJoinedFlowFrame(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Mute'), findsOneWidget);
    expect(find.text('Ringing...'), findsNothing);
    await _disposeRenderedApp(tester);
  });

  testWidgets('accepted after first frame still opens joined call UI', (
    tester,
  ) async {
    await tester.pumpWidget(const CallwaveExampleApp());
    await tester.pump();

    fakePlatform.emit(type: platform.CallEventType.accepted);
    await _pumpToJoinedFlowFrame(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Mute'), findsOneWidget);
    await _disposeRenderedApp(tester);
  });

  testWidgets('restores active call on startup when accepted event is missing',
      (
    tester,
  ) async {
    fakePlatform.activeCallIds = <String>[_FakePlatform.callId];

    await tester.pumpWidget(const CallwaveExampleApp());
    await _pumpToJoinedFlowFrame(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Mute'), findsOneWidget);
    await _disposeRenderedApp(tester);
  });
}

Future<void> _pumpToJoinedFlowFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 650));
}

Future<void> _disposeRenderedApp(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

class _FakePlatform extends platform.CallwaveFlutterPlatform {
  static const String callId = 'demo-call-001';

  _FakePlatform();

  late final StreamController<platform.CallEventDto> _controller =
      StreamController<platform.CallEventDto>.broadcast(
    onListen: _emitInitialEvents,
  );
  List<platform.CallEventType> _initialEventTypes = <platform.CallEventType>[];
  List<String> activeCallIds = const <String>[];
  bool _didEmitInitialEvents = false;

  set initialEventTypes(List<platform.CallEventType> value) {
    _initialEventTypes = List<platform.CallEventType>.of(value);
    _didEmitInitialEvents = false;
  }

  Future<void> dispose() async {
    await _controller.close();
  }

  @override
  Stream<platform.CallEventDto> get events => _controller.stream;

  void _emitInitialEvents() {
    if (_didEmitInitialEvents) {
      return;
    }
    _didEmitInitialEvents = true;
    for (final type in _initialEventTypes) {
      emit(type: type);
    }
  }

  void emit({required platform.CallEventType type}) {
    _controller.add(
      platform.CallEventDto(
        callId: callId,
        type: type,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  @override
  Future<void> acceptCall(String callId) async {}

  @override
  Future<void> declineCall(String callId) async {}

  @override
  Future<void> endCall(String callId) async {}

  @override
  Future<List<String>> getActiveCallIds() async =>
      List<String>.of(activeCallIds);

  @override
  Future<void> initialize() async {}

  @override
  Future<void> markMissed(String callId) async {}

  @override
  Future<void> requestFullScreenIntentPermission() async {}

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<void> setPostCallBehavior(platform.PostCallBehavior behavior) async {}

  @override
  Future<void> showIncomingCall(platform.CallDataDto data) async {}

  @override
  Future<void> showOutgoingCall(platform.CallDataDto data) async {}
}
