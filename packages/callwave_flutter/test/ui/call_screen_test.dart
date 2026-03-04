import 'dart:async';

import 'package:callwave_flutter/callwave_flutter.dart';
import 'package:callwave_flutter_platform_interface/callwave_flutter_platform_interface.dart'
    as platform;
import 'package:callwave_flutter/src/ui/call_screen_controller.dart';
import 'package:callwave_flutter/src/ui/theme/call_screen_theme.dart';
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

  testWidgets('auto returns on timeout when previous route exists', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const SizedBox.shrink(),
      ),
    );

    _pushCallScreen(navigatorKey, _testCallData());
    await tester.pump(const Duration(milliseconds: 350));
    expect(navigatorKey.currentState!.canPop(), isTrue);

    fakePlatform.emit(type: platform.CallEventType.timeout);
    await tester.pump();
    await _pumpThroughAutoDismiss(tester);

    expect(navigatorKey.currentState!.canPop(), isFalse);
  });

  testWidgets('auto returns on ended, declined, and missed', (tester) async {
    final endTypes = <platform.CallEventType>[
      platform.CallEventType.ended,
      platform.CallEventType.declined,
      platform.CallEventType.missed,
    ];

    for (final type in endTypes) {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const SizedBox.shrink(),
        ),
      );

      _pushCallScreen(navigatorKey, _testCallData());
      await tester.pump(const Duration(milliseconds: 350));
      expect(navigatorKey.currentState!.canPop(), isTrue);

      fakePlatform.emit(type: type);
      await tester.pump();
      await _pumpThroughAutoDismiss(tester);

      expect(
        navigatorKey.currentState!.canPop(),
        isFalse,
        reason: 'CallScreen should auto-return for ${type.name}.',
      );
    }
  });

  testWidgets('does not pop when call screen is root route', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: CallScreen(callData: _testCallData()),
      ),
    );

    expect(navigatorKey.currentState!.canPop(), isFalse);

    fakePlatform.emit(type: platform.CallEventType.timeout);
    await tester.pump();
    await _pumpThroughAutoDismiss(tester);

    expect(find.byType(CallScreen), findsOneWidget);
    expect(navigatorKey.currentState!.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('onCallEnded callback runs exactly once when provided', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    var callbackCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const SizedBox.shrink(),
      ),
    );

    _pushCallScreen(
      navigatorKey,
      _testCallData(),
      onCallEnded: () {
        callbackCount += 1;
      },
    );
    await tester.pump(const Duration(milliseconds: 350));

    fakePlatform.emit(type: platform.CallEventType.timeout);
    fakePlatform.emit(type: platform.CallEventType.missed);
    await tester.pump();
    await _pumpThroughAutoDismiss(tester);

    expect(callbackCount, 1);
  });

  test('startInConnecting auto-advances to connected', () async {
    final controller = CallScreenController(
      callId: _FakePlatform.callId,
      callType: CallType.audio,
      startInConnecting: true,
    );
    addTearDown(controller.dispose);

    expect(controller.status, CallStatus.connecting);

    await Future<void>.delayed(const Duration(milliseconds: 850));
    expect(controller.status, CallStatus.connected);
  });

  test('incoming after accepted does not regress to ringing', () async {
    final controller = CallScreenController(
      callId: _FakePlatform.callId,
      callType: CallType.audio,
    );
    addTearDown(controller.dispose);

    expect(controller.status, CallStatus.ringing);
    fakePlatform.emit(type: platform.CallEventType.accepted);
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, isNot(CallStatus.ringing));

    fakePlatform.emit(type: platform.CallEventType.incoming);
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, isNot(CallStatus.ringing));
  });

  test('timeout and missed after accepted are ignored as stale', () async {
    final controller = CallScreenController(
      callId: _FakePlatform.callId,
      callType: CallType.audio,
    );
    addTearDown(controller.dispose);

    expect(controller.status, CallStatus.ringing);

    fakePlatform.emit(type: platform.CallEventType.accepted);
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, CallStatus.connecting);

    fakePlatform.emit(type: platform.CallEventType.timeout);
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, isNot(CallStatus.ended));

    fakePlatform.emit(type: platform.CallEventType.missed);
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, isNot(CallStatus.ended));
  });
}

void _pushCallScreen(
  GlobalKey<NavigatorState> navigatorKey,
  CallData callData, {
  VoidCallback? onCallEnded,
  bool startInConnecting = false,
}) {
  navigatorKey.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => CallScreen(
        callData: callData,
        startInConnecting: startInConnecting,
        onCallEnded: onCallEnded,
      ),
    ),
  );
}

CallData _testCallData() {
  return const CallData(
    callId: _FakePlatform.callId,
    callerName: 'Ava',
    handle: '+1 555 0101',
  );
}

Future<void> _pumpThroughAutoDismiss(WidgetTester tester) async {
  await tester.pump(CallScreenTheme.autoDismissDelay);
  await tester.pump(const Duration(milliseconds: 50));
}

class _FakePlatform extends platform.CallwaveFlutterPlatform {
  static const String callId = 'test-call-id';

  final StreamController<platform.CallEventDto> _controller =
      StreamController<platform.CallEventDto>.broadcast();

  @override
  Stream<platform.CallEventDto> get events => _controller.stream;

  Future<void> dispose() async {
    await _controller.close();
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
  Future<List<String>> getActiveCallIds() async => const <String>[];

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
