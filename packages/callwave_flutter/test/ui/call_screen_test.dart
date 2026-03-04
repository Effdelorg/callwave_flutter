import 'package:callwave_flutter/callwave_flutter.dart';
import 'package:callwave_flutter/src/ui/call_screen_controller.dart';
import 'package:callwave_flutter/src/ui/theme/call_screen_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('auto returns on ended when previous route exists',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final session = _buildSession();
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const SizedBox.shrink(),
      ),
    );

    _pushCallScreen(navigatorKey, session);
    await tester.pump(const Duration(milliseconds: 350));
    expect(navigatorKey.currentState!.canPop(), isTrue);

    session.reportEnded();
    await tester.pump();
    await _pumpThroughAutoDismiss(tester);

    expect(navigatorKey.currentState!.canPop(), isFalse);
  });

  testWidgets('does not pop when call screen is root route', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final session = _buildSession();
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: CallScreen(session: session),
      ),
    );

    expect(navigatorKey.currentState!.canPop(), isFalse);

    session.reportEnded();
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
    final session = _buildSession();
    addTearDown(session.dispose);
    var callbackCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const SizedBox.shrink(),
      ),
    );

    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => CallScreen(
          session: session,
          onCallEnded: () {
            callbackCount += 1;
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));

    session.reportEnded();
    session.reportEnded();
    await tester.pump();
    await _pumpThroughAutoDismiss(tester);

    expect(callbackCount, 1);
  });

  test('session mode maps state and delegates actions', () async {
    var acceptCalls = 0;
    var endCalls = 0;
    final session = _buildSession(
      acceptNative: (_) async {
        acceptCalls += 1;
      },
      endNative: (_) async {
        endCalls += 1;
      },
    );
    addTearDown(session.dispose);

    final controller = CallScreenController(session: session);
    addTearDown(controller.dispose);

    expect(controller.status, CallStatus.ringing);

    controller.acceptCall();
    await Future<void>.delayed(Duration.zero);
    expect(acceptCalls, 1);

    session.reportConnected();
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, CallStatus.connected);

    controller.endCall();
    await Future<void>.delayed(Duration.zero);
    expect(endCalls, 1);
  });
}

CallSession _buildSession({
  Future<void> Function(String callId)? acceptNative,
  Future<void> Function(String callId)? endNative,
}) {
  return CallSession(
    callData: const CallData(
      callId: 'test-call-id',
      callerName: 'Ava',
      handle: '+1 555 0101',
    ),
    isOutgoing: false,
    acceptNative: acceptNative,
    endNative: endNative,
  );
}

void _pushCallScreen(
    GlobalKey<NavigatorState> navigatorKey, CallSession session) {
  navigatorKey.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => CallScreen(session: session),
    ),
  );
}

Future<void> _pumpThroughAutoDismiss(WidgetTester tester) async {
  await tester.pump(CallScreenTheme.autoDismissDelay);
  await tester.pump(const Duration(milliseconds: 50));
}
