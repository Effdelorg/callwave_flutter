import 'package:callwave_flutter/callwave_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CallSession _session(List<String> sent) => CallSession(
  callData: const CallData(callId: 'call', callerName: 'Ava', handle: '+1'),
  isOutgoing: true,
  reportOutgoingScreenVisible: (id) async {
    sent.add(id);
  },
);

Future<void> _prepare(CallSession session) => session.applyNativeEvent(
  CallEvent(
    callId: session.callId,
    type: CallEventType.started,
    timestamp: DateTime.now(),
    extra: {CallEventExtraKeys.outgoingRingbackRequestId: 'attempt-1'},
  ),
);

Widget _screen(CallSession session) => CallwaveCallScreenReady(
  session: session,
  child: const Scaffold(body: Text('Call')),
);

void main() {
  testWidgets('waits for route entrance completion and its rendered frame', (
    tester,
  ) async {
    final sent = <String>[];
    final session = _session(sent);
    addTearDown(session.dispose);
    await _prepare(session);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigator, home: const SizedBox()),
    );
    navigator.currentState!.push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(seconds: 1),
        pageBuilder: (_, __, ___) => _screen(session),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(sent, isEmpty);
    await tester.pumpAndSettle();
    expect(sent, ['attempt-1']);
  });

  for (final outcome in ['connected', 'failed', 'ended', 'popped']) {
    testWidgets('$outcome during entrance prevents readiness', (tester) async {
      final sent = <String>[];
      final session = _session(sent);
      addTearDown(session.dispose);
      await _prepare(session);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const SizedBox()),
      );
      navigator.currentState!.push(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(seconds: 1),
          pageBuilder: (_, __, ___) => _screen(session),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      switch (outcome) {
        case 'connected':
          session.reportConnected();
        case 'failed':
          session.reportFailed();
        case 'ended':
          session.reportEnded();
        case 'popped':
          navigator.currentState!.pop();
      }
      await tester.pumpAndSettle();
      expect(sent, isEmpty);
      session.dispose();
    });
  }

  testWidgets('initial route and nested wrappers signal once', (tester) async {
    final sent = <String>[];
    final session = _session(sent);
    addTearDown(session.dispose);
    await _prepare(session);
    await tester.pumpWidget(
      MaterialApp(
        home: CallwaveCallScreenReady(
          session: session,
          child: _screen(session),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(sent, ['attempt-1']);
  });

  testWidgets('standalone built-in screen reports readiness', (tester) async {
    final sent = <String>[];
    final session = _session(sent);
    addTearDown(session.dispose);
    await _prepare(session);
    await tester.pumpWidget(MaterialApp(home: CallScreen(session: session)));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(sent, ['attempt-1']);
  });

  testWidgets('zero-duration route records visibility before native setup', (
    tester,
  ) async {
    final sent = <String>[];
    final session = _session(sent);
    addTearDown(session.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigator, home: const SizedBox()),
    );
    navigator.currentState!.push(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => _screen(session),
      ),
    );
    await tester.pumpAndSettle();
    expect(sent, isEmpty);
    await _prepare(session);
    expect(sent, ['attempt-1']);
  });

  testWidgets('covered route waits until it is current again', (tester) async {
    final sent = <String>[];
    final session = _session(sent);
    addTearDown(session.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigator, home: _screen(session)),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Text('Other')),
    );
    await tester.pumpAndSettle();
    await _prepare(session);
    expect(sent, isEmpty);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(sent, ['attempt-1']);
  });

  testWidgets('background app waits for resume', (tester) async {
    final sent = <String>[];
    final session = _session(sent);
    addTearDown(session.dispose);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(MaterialApp(home: _screen(session)));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await _prepare(session);
    expect(sent, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(sent, ['attempt-1']);
  });

  testWidgets('disposed screen cannot signal when setup arrives later', (
    tester,
  ) async {
    final sent = <String>[];
    final session = _session(sent);
    addTearDown(session.dispose);
    await tester.pumpWidget(MaterialApp(home: _screen(session)));
    await tester.pumpWidget(const SizedBox());
    await _prepare(session);
    expect(sent, isEmpty);
  });

  testWidgets(
    'completed offstage route cannot start audio until painted again',
    (tester) async {
      final sent = <String>[];
      final session = _session(sent);
      addTearDown(session.dispose);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const SizedBox()),
      );
      final route = MaterialPageRoute<void>(builder: (_) => _screen(session));
      navigator.currentState!.push(route);
      await tester.pumpAndSettle();
      route.offstage = true;
      await tester.pump();
      await _prepare(session);
      await tester.pump();
      expect(sent, isEmpty);
      route.offstage = false;
      await tester.pumpAndSettle();
      expect(sent, ['attempt-1']);
    },
  );

  testWidgets('session replacement clears visibility for the old attempt', (
    tester,
  ) async {
    final oldSent = <String>[];
    final newSent = <String>[];
    final old = _session(oldSent);
    final current = _session(newSent);
    addTearDown(old.dispose);
    addTearDown(current.dispose);
    await tester.pumpWidget(MaterialApp(home: _screen(old)));
    await tester.pumpWidget(MaterialApp(home: _screen(current)));
    await _prepare(old);
    await _prepare(current);
    expect(oldSent, isEmpty);
    expect(newSent, ['attempt-1']);
  });

  for (final nested in [false, true]) {
    testWidgets('built-in fade must finish before readiness (nested=$nested)', (
      tester,
    ) async {
      final sent = <String>[];
      final session = _session(sent);
      addTearDown(session.dispose);
      await _prepare(session);
      Widget screen = CallScreen(session: session);
      if (nested) {
        screen = CallwaveCallScreenReady(
          session: session,
          child: CallwaveCallScreenReady(session: session, child: screen),
        );
      }
      await tester.pumpWidget(MaterialApp(home: screen));
      expect(sent, isEmpty);
      await tester.pump(const Duration(milliseconds: 200));
      expect(sent, isEmpty);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(sent, ['attempt-1']);
      final fade = tester.widget<FadeTransition>(
        find
            .descendant(
              of: find.byType(CallScreen),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade.opacity.value, 1);
    });
  }

  testWidgets('Offstage content cannot report readiness without painting', (
    tester,
  ) async {
    final sent = <String>[];
    final session = _session(sent);
    addTearDown(session.dispose);
    final hidden = ValueNotifier(true);
    addTearDown(hidden.dispose);
    final painter = _PaintCounter();
    await _prepare(session);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: hidden,
          builder: (_, hidden, child) =>
              Offstage(offstage: hidden, child: child),
          child: CallwaveCallScreenReady(
            session: session,
            child: CustomPaint(painter: painter, size: const Size(50, 50)),
          ),
        ),
      ),
    );
    expect(painter.count, 0);
    expect(sent, isEmpty);
    hidden.value = false;
    await tester.pump();
    expect(painter.count, greaterThan(0));
    expect(sent, ['attempt-1']);
  });

  testWidgets('transparent ancestor blocks a previously painted screen', (
    tester,
  ) async {
    final sent = <String>[];
    final session = _session(sent);
    addTearDown(session.dispose);
    final opacity = ValueNotifier(1.0);
    addTearDown(opacity.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<double>(
          valueListenable: opacity,
          builder: (_, value, child) => Opacity(opacity: value, child: child),
          child: _screen(session),
        ),
      ),
    );
    opacity.value = 0;
    await tester.pump();
    await _prepare(session);
    await tester.pump();
    expect(sent, isEmpty);
    opacity.value = 1;
    await tester.pump();
    expect(sent, ['attempt-1']);
  });

  testWidgets('incoming connected ticks do not repaint static call content', (
    tester,
  ) async {
    final painter = _PaintCounter();
    final session = CallSession(
      callData: const CallData(
        callId: 'incoming',
        callerName: 'Ava',
        handle: '+1',
      ),
      isOutgoing: false,
    );
    session.reportConnected();
    await tester.pumpWidget(
      MaterialApp(
        home: CallwaveCallScreenReady(
          session: session,
          child: CustomPaint(painter: painter, size: const Size(50, 50)),
        ),
      ),
    );
    final before = painter.count;
    await tester.pump(const Duration(seconds: 1));
    expect(painter.count, before);
    session.dispose();
  });

  testWidgets(
    'nested wrappers release all session observation after readiness',
    (tester) async {
      final sent = <String>[];
      final session = _TrackedSession(sent);
      addTearDown(session.dispose);
      final painter = _PaintCounter();
      await tester.pumpWidget(
        MaterialApp(
          home: CallwaveCallScreenReady(
            session: session,
            child: CallwaveCallScreenReady(
              session: session,
              child: CallwaveCallScreenReady(
                session: session,
                child: CustomPaint(painter: painter, size: const Size(50, 50)),
              ),
            ),
          ),
        ),
      );
      expect(session.listeners.length, 1);
      await _prepare(session);
      await tester.pump();
      expect(sent, ['attempt-1']);
      expect(session.listeners, isEmpty);
      final before = painter.count;
      session.updateCallData(session.callData.copyWith(callerName: 'Changed'));
      await tester.pump();
      expect(painter.count, before);
    },
  );

  testWidgets('native start without a ringback token stops observing', (
    tester,
  ) async {
    final sent = <String>[];
    final session = _TrackedSession(sent);
    addTearDown(session.dispose);
    final painter = _PaintCounter();
    await tester.pumpWidget(
      MaterialApp(
        home: CallwaveCallScreenReady(
          session: session,
          child: CustomPaint(painter: painter, size: const Size(50, 50)),
        ),
      ),
    );
    expect(session.listeners.length, 1);
    await session.applyNativeEvent(
      CallEvent(
        callId: session.callId,
        type: CallEventType.started,
        timestamp: DateTime.now(),
      ),
    );
    expect(session.listeners, isEmpty);
    final before = painter.count;
    session.updateCallData(session.callData.copyWith(callerName: 'Changed'));
    await tester.pump();
    expect(painter.count, before);
    expect(sent, isEmpty);
  });

  testWidgets('nested content also waits for an ancestor entrance animation', (
    tester,
  ) async {
    final sent = <String>[];
    final session = _session(sent);
    addTearDown(session.dispose);
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(seconds: 1),
    );
    addTearDown(controller.dispose);
    await _prepare(session);
    await tester.pumpWidget(
      MaterialApp(
        home: CallwaveCallScreenReady(
          session: session,
          entranceAnimation: controller,
          child: _screen(session),
        ),
      ),
    );
    expect(sent, isEmpty);
    controller.forward();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(sent, isEmpty);
    await tester.pumpAndSettle();
    expect(sent, ['attempt-1']);
  });

  testWidgets('preparing session remains observed until it can connect', (
    tester,
  ) async {
    final sent = <String>[];
    final session = _session(sent);
    addTearDown(session.dispose);
    session.reportValidating();
    await tester.pumpWidget(MaterialApp(home: _screen(session)));
    expect(sent, isEmpty);
    await _prepare(session);
    await tester.pump();
    expect(sent, ['attempt-1']);
  });

  testWidgets('without a route requires explicit reporting', (tester) async {
    final sent = <String>[];
    final session = _session(sent);
    addTearDown(session.dispose);
    await _prepare(session);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CallwaveCallScreenReady(
          session: session,
          child: const Text('Call'),
        ),
      ),
    );
    await tester.pump();
    expect(sent, isEmpty);
    session.setCallScreenVisible(true);
    expect(sent, ['attempt-1']);
  });
}

class _PaintCounter extends CustomPainter {
  int count = 0;
  @override
  void paint(Canvas canvas, Size size) {
    count++;
  }

  @override
  bool shouldRepaint(covariant _PaintCounter oldDelegate) => false;
}

class _TrackedSession extends CallSession {
  _TrackedSession(List<String> sent)
    : super(
        callData: const CallData(
          callId: 'call',
          callerName: 'Ava',
          handle: '+1',
        ),
        isOutgoing: true,
        reportOutgoingScreenVisible: (id) async {
          sent.add(id);
        },
      );
  final listeners = <VoidCallback>{};
  @override
  void addListener(VoidCallback listener) {
    listeners.add(listener);
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners.remove(listener);
    super.removeListener(listener);
  }
}
