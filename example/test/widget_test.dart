import 'dart:async';

import 'package:callwave_flutter/callwave_flutter.dart';
import 'package:callwave_flutter_platform_interface/callwave_flutter_platform_interface.dart'
    as platform;
import 'package:callwave_flutter_example/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakePlatform fakePlatform;

  setUp(() {
    fakePlatform = _FakePlatform();
    platform.CallwaveFlutterPlatform.instance = fakePlatform;
    CallwaveFlutter.instance.setEngine(_TestEngine());
  });

  tearDown(() async {
    CallwaveFlutter.instance.setEngine(_TestEngine());
    await fakePlatform.dispose();
  });

  testWidgets('app boots to home screen', (tester) async {
    await tester.pumpWidget(const CallwaveExampleApp());
    await tester.pump();

    expect(find.text('Callwave Example'), findsOneWidget);
    expect(find.text('Call ID'), findsOneWidget);
    await _disposeRenderedApp(tester, wait: const Duration(milliseconds: 50));
  });

  testWidgets('accepted event opens session-driven call screen',
      (tester) async {
    fakePlatform.initialEventTypes = <platform.CallEventType>[
      platform.CallEventType.accepted,
    ];

    await tester.pumpWidget(const CallwaveExampleApp());
    await _pumpUntilCallScreen(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(CallScreen), findsOneWidget);
    fakePlatform.emit(type: platform.CallEventType.ended);
    await tester.pump();
    await _disposeRenderedApp(tester, wait: const Duration(seconds: 4));
  });

  testWidgets('ended event transitions startup-routed session to ended state',
      (tester) async {
    fakePlatform.activeCallIds = <String>[_FakePlatform.callId];
    fakePlatform.activeCallSnapshots = <platform.CallEventDto>[
      platform.CallEventDto(
        callId: _FakePlatform.callId,
        type: platform.CallEventType.accepted,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ),
    ];

    final startupDecision =
        await CallwaveFlutter.instance.prepareStartupRouteDecision();
    await tester.pumpWidget(
      CallwaveExampleApp(startupDecision: startupDecision),
    );
    await _pumpUntilCallScreen(tester);
    expect(find.byType(CallScreen), findsOneWidget);

    fakePlatform.emit(type: platform.CallEventType.ended);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final session = CallwaveFlutter.instance.getSession(_FakePlatform.callId);
    expect(session, isNotNull);
    expect(session!.state, CallSessionState.ended);
    await _disposeRenderedApp(tester, wait: const Duration(seconds: 4));
  });

  testWidgets('startup decision routes accepted cold start directly to call',
      (tester) async {
    fakePlatform.activeCallIds = <String>[_FakePlatform.callId];
    fakePlatform.activeCallSnapshots = <platform.CallEventDto>[
      platform.CallEventDto(
        callId: _FakePlatform.callId,
        type: platform.CallEventType.accepted,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ),
    ];

    final startupDecision =
        await CallwaveFlutter.instance.prepareStartupRouteDecision();
    await tester.pumpWidget(
      CallwaveExampleApp(startupDecision: startupDecision),
    );
    await _pumpUntilCallScreen(tester);

    expect(startupDecision.shouldOpenCall, isTrue);
    expect(find.byType(CallScreen), findsOneWidget);
    expect(find.text('Call ID'), findsNothing);
    fakePlatform.emit(type: platform.CallEventType.ended);
    await tester.pump();
    await _disposeRenderedApp(tester, wait: const Duration(seconds: 4));
  });
}

Future<void> _pumpUntilCallScreen(WidgetTester tester) async {
  for (var i = 0; i < 20; i += 1) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(CallScreen).evaluate().isNotEmpty) {
      return;
    }
  }
}

Future<void> _disposeRenderedApp(
  WidgetTester tester, {
  required Duration wait,
}) async {
  await tester.pump(wait);
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
  List<platform.CallEventDto> activeCallSnapshots =
      const <platform.CallEventDto>[];
  bool _didEmitInitialEvents = false;

  set initialEventTypes(List<platform.CallEventType> value) {
    _initialEventTypes = List<platform.CallEventType>.of(value);
    _didEmitInitialEvents = false;
    if (_controller.hasListener) {
      _emitInitialEvents();
    }
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
  Future<List<platform.CallEventDto>> getActiveCallEventSnapshots() async {
    return List<platform.CallEventDto>.of(activeCallSnapshots);
  }

  @override
  Future<void> syncActiveCallsToEvents() async {
    for (final event in activeCallSnapshots) {
      _controller.add(event);
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
  Future<void> setPostCallBehavior(platform.PostCallBehavior behavior) async {}

  @override
  Future<void> showIncomingCall(platform.CallDataDto data) async {}

  @override
  Future<void> showOutgoingCall(platform.CallDataDto data) async {}
}

class _TestEngine extends CallwaveEngine {
  @override
  Future<void> onAnswerCall(CallSession session) async {
    session.reportConnected();
  }

  @override
  Future<void> onStartCall(CallSession session) async {
    session.reportConnected();
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
