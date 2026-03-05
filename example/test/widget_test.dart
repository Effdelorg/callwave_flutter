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

  testWidgets('demo renders explicit incoming/outgoing audio-video buttons',
      (tester) async {
    await tester.pumpWidget(const CallwaveExampleApp());
    await tester.pump();

    expect(find.text('Incoming Audio'), findsOneWidget);
    expect(find.text('Incoming Video'), findsOneWidget);
    expect(find.text('Outgoing Audio'), findsOneWidget);
    expect(find.text('Outgoing Video'), findsOneWidget);
    expect(find.text('Conference Audio'), findsOneWidget);
    expect(find.text('Conference Video'), findsOneWidget);
    expect(find.text('Cycle Speaker'), findsOneWidget);

    await _disposeRenderedApp(tester, wait: const Duration(milliseconds: 50));
  });

  testWidgets('conference audio preview opens conference call UI',
      (tester) async {
    await tester.pumpWidget(const CallwaveExampleApp());
    await tester.pump();

    await tester.tap(find.text('Conference Audio'));
    await _pumpUntilCallScreen(tester);

    expect(find.byType(CallScreen), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('conference-view')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('conference-controls-row')),
        findsOneWidget);
    expect(find.text('Mic'), findsOneWidget);
    expect(find.text('Speaker'), findsOneWidget);
    expect(find.text('Cam'), findsNothing);
    expect(find.text('End'), findsOneWidget);

    for (final session in CallwaveFlutter.instance.activeSessions) {
      session.reportEnded();
    }
    await tester.pump(const Duration(seconds: 4));
    await _disposeRenderedApp(tester, wait: const Duration(milliseconds: 50));
  });

  testWidgets('conference video preview opens conference call UI',
      (tester) async {
    await tester.pumpWidget(const CallwaveExampleApp());
    await tester.pump();

    await tester.tap(find.text('Conference Video'));
    await _pumpUntilCallScreen(tester);

    expect(find.byType(CallScreen), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('conference-view')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('conference-controls-row')),
        findsOneWidget);
    expect(find.text('Mic'), findsOneWidget);
    expect(find.text('Speaker'), findsOneWidget);
    expect(find.text('Cam'), findsOneWidget);
    expect(find.text('End'), findsOneWidget);

    for (final session in CallwaveFlutter.instance.activeSessions) {
      session.reportEnded();
    }
    await tester.pump(const Duration(seconds: 4));
    await _disposeRenderedApp(tester, wait: const Duration(milliseconds: 50));
  });

  testWidgets('demo sends selected call types to platform', (tester) async {
    await tester.pumpWidget(const CallwaveExampleApp());
    await tester.pump();

    await tester.tap(find.text('Incoming Video'));
    await tester.pump();
    expect(fakePlatform.lastIncomingCallData, isNotNull);
    expect(
        fakePlatform.lastIncomingCallData!.callType, platform.CallType.video);
    expect(fakePlatform.lastIncomingCallData!.callId, _FakePlatform.callId);

    await tester.tap(find.text('Outgoing Audio'));
    await tester.pump();
    expect(fakePlatform.lastOutgoingCallData, isNotNull);
    expect(
        fakePlatform.lastOutgoingCallData!.callType, platform.CallType.audio);
    expect(fakePlatform.lastOutgoingCallData!.callId, _FakePlatform.callId);

    await _disposeRenderedApp(tester, wait: const Duration(milliseconds: 50));
  });

  testWidgets('in-flight guard prevents duplicate call launch taps',
      (tester) async {
    fakePlatform.pendingIncomingCallCompleter = Completer<void>();

    await tester.pumpWidget(const CallwaveExampleApp());
    await tester.pump();

    await tester.tap(find.text('Incoming Video'));
    await tester.tap(find.text('Incoming Video'));
    await tester.pump();

    expect(fakePlatform.incomingCallCount, 1);

    fakePlatform.pendingIncomingCallCompleter?.complete();
    await tester.pump();
    await tester.pump();

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

  testWidgets('accepted launchAction event opens session-driven call screen',
      (tester) async {
    fakePlatform.initialEvents = <platform.CallEventDto>[
      platform.CallEventDto(
        callId: _FakePlatform.callId,
        type: platform.CallEventType.accepted,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        extra: const <String, dynamic>{
          'launchAction':
              'com.callwave.flutter.methodchannel.ACTION_OPEN_ONGOING',
        },
      ),
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
  List<platform.CallEventDto> _initialEvents = <platform.CallEventDto>[];
  List<String> activeCallIds = const <String>[];
  List<platform.CallEventDto> activeCallSnapshots =
      const <platform.CallEventDto>[];
  platform.CallDataDto? lastIncomingCallData;
  platform.CallDataDto? lastOutgoingCallData;
  int incomingCallCount = 0;
  int outgoingCallCount = 0;
  Completer<void>? pendingIncomingCallCompleter;
  Completer<void>? pendingOutgoingCallCompleter;
  bool _didEmitInitialEvents = false;

  set initialEventTypes(List<platform.CallEventType> value) {
    _initialEventTypes = List<platform.CallEventType>.of(value);
    _initialEvents = <platform.CallEventDto>[];
    _didEmitInitialEvents = false;
    if (_controller.hasListener) {
      _emitInitialEvents();
    }
  }

  set initialEvents(List<platform.CallEventDto> value) {
    _initialEvents = List<platform.CallEventDto>.of(value);
    _initialEventTypes = <platform.CallEventType>[];
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
    if (_initialEvents.isNotEmpty) {
      for (final event in _initialEvents) {
        _controller.add(event);
      }
      return;
    }
    for (final type in _initialEventTypes) {
      emit(type: type);
    }
  }

  void emit({
    required platform.CallEventType type,
    Map<String, dynamic>? extra,
  }) {
    _controller.add(
      platform.CallEventDto(
        callId: callId,
        type: type,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        extra: extra,
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
  Future<void> showIncomingCall(platform.CallDataDto data) async {
    lastIncomingCallData = data;
    incomingCallCount += 1;
    final completer = pendingIncomingCallCompleter;
    if (completer != null) {
      await completer.future;
    }
  }

  @override
  Future<void> showOutgoingCall(platform.CallDataDto data) async {
    lastOutgoingCallData = data;
    outgoingCallCount += 1;
    final completer = pendingOutgoingCallCompleter;
    if (completer != null) {
      await completer.future;
    }
  }
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
