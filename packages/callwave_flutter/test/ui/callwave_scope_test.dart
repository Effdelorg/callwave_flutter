import 'package:callwave_flutter/callwave_flutter.dart';
import 'package:callwave_flutter_platform_interface/callwave_flutter_platform_interface.dart'
    as platform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    platform.CallwaveFlutterPlatform.instance = _NoopPlatform();
    CallwaveFlutter.instance.setEngine(_FakeEngine());
  });

  tearDown(() {
    // Reset singleton state between tests.
    CallwaveFlutter.instance.setEngine(_FakeEngine());
  });

  testWidgets('hydrates sessions created before scope listener attaches',
      (tester) async {
    CallwaveFlutter.instance.createSession(
      callData: const CallData(
        callId: 'restore-1',
        callerName: 'Ava',
        handle: '+1 555 0101',
      ),
      isOutgoing: false,
      initialState: CallSessionState.connecting,
    );

    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, child) {
          return CallwaveScope(
            navigatorKey: navigatorKey,
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );

    await _pumpUntilCallScreen(tester);

    expect(find.byType(CallScreen), findsOneWidget);
    expect(find.text('Connecting...'), findsOneWidget);
  });

  testWidgets('preRoutedCallIds skips auto-push for startup-routed call',
      (tester) async {
    CallwaveFlutter.instance.createSession(
      callData: const CallData(
        callId: 'startup-routed',
        callerName: 'Ava',
        handle: '+1 555 0101',
      ),
      isOutgoing: false,
      initialState: CallSessionState.connecting,
    );

    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, child) {
          return CallwaveScope(
            navigatorKey: navigatorKey,
            preRoutedCallIds: const <String>{'startup-routed'},
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const Scaffold(body: Text('Home')),
      ),
    );

    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Home'), findsOneWidget);
    expect(find.byType(CallScreen), findsNothing);
  });

  testWidgets('onRouteSession handled session skips auto-push', (tester) async {
    CallwaveFlutter.instance.createSession(
      callData: const CallData(
        callId: 'handled-by-app',
        callerName: 'Ava',
        handle: '+1 555 0101',
      ),
      isOutgoing: false,
      initialState: CallSessionState.connecting,
    );

    var handledCount = 0;
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, child) {
          return CallwaveScope(
            navigatorKey: navigatorKey,
            onRouteSession: (_, session) {
              if (session.callId == 'handled-by-app') {
                handledCount += 1;
                return true;
              }
              return false;
            },
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const Scaffold(body: Text('Home')),
      ),
    );

    await tester.pump(const Duration(milliseconds: 300));

    expect(handledCount, 1);
    expect(find.byType(CallScreen), findsNothing);
  });

  testWidgets('onRouteSession fallback false keeps auto-push behavior',
      (tester) async {
    CallwaveFlutter.instance.createSession(
      callData: const CallData(
        callId: 'fallback-auto-push',
        callerName: 'Ava',
        handle: '+1 555 0101',
      ),
      isOutgoing: false,
      initialState: CallSessionState.connecting,
    );

    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, child) {
          return CallwaveScope(
            navigatorKey: navigatorKey,
            onRouteSession: (_, __) => false,
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );

    await _pumpUntilCallScreen(tester);

    expect(find.byType(CallScreen), findsOneWidget);
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

class _NoopPlatform extends platform.CallwaveFlutterPlatform {
  @override
  Stream<platform.CallEventDto> get events =>
      const Stream<platform.CallEventDto>.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> showIncomingCall(platform.CallDataDto data) async {}

  @override
  Future<void> showOutgoingCall(platform.CallDataDto data) async {}

  @override
  Future<void> acceptCall(String callId) async {}

  @override
  Future<void> declineCall(String callId) async {}

  @override
  Future<void> endCall(String callId) async {}

  @override
  Future<void> markMissed(String callId) async {}

  @override
  Future<List<String>> getActiveCallIds() async => const <String>[];

  @override
  Future<void> syncActiveCallsToEvents() async {}

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<void> requestFullScreenIntentPermission() async {}

  @override
  Future<void> setPostCallBehavior(platform.PostCallBehavior behavior) async {}
}

class _FakeEngine extends CallwaveEngine {
  @override
  Future<void> onAnswerCall(CallSession session) async {}

  @override
  Future<void> onStartCall(CallSession session) async {}

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
