# callwave_flutter

Public Flutter API for Callwave VoIP call UX.

This package is session-first. You provide a `CallwaveEngine` and the package handles
call-session orchestration, call-screen state, and navigation hooks.

## Core Flow

1. Register your engine.
2. Resolve startup route (`home` vs `call`) before `runApp`.
3. Wrap your app with `CallwaveScope`.

```dart
class MyCallwaveEngine extends CallwaveEngine {
  @override
  Future<void> onAnswerCall(CallSession session) async {
    final roomToken = session.callData.extra?['roomToken'];
    await mySdk.join(roomToken);
    session.reportConnected();
  }

  @override
  Future<void> onStartCall(CallSession session) async {
    await mySdk.start(session.callId);
    session.reportConnected();
  }

  @override
  Future<void> onEndCall(CallSession session) async {
    await mySdk.leave();
  }

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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final navKey = GlobalKey<NavigatorState>();
  CallwaveFlutter.instance.setEngine(MyCallwaveEngine());
  final startup = await CallwaveFlutter.instance.prepareStartupRouteDecision();

  runApp(
    MaterialApp(
      navigatorKey: navKey,
      initialRoute: startup.shouldOpenCall ? '/call' : '/home',
      routes: <String, WidgetBuilder>{
        '/home': (_) => const HomeScreen(),
        '/call': (_) => StartupCallRoute(callId: startup.callId),
      },
      builder: (_, child) => CallwaveScope(
        navigatorKey: navKey,
        preRoutedCallIds: startup.callId == null
            ? const <String>{}
            : <String>{startup.callId!},
        child: child!,
      ),
    ),
  );
}
```

## Cold Start

`prepareStartupRouteDecision()` restores active sessions and returns a route
decision:

- Open call route when a session is `connecting`, `connected`, or `reconnecting`.
- Stay on home route when sessions are only `ringing`/`idle`, or none exist.

If your app does not use startup routing in `main`, `CallwaveScope` still
auto-pushes `CallScreen` as fallback.

## CallScreen

`CallScreen` is session-driven: pass a `CallSession`, not raw `CallData`.

```dart
CallScreen(session: session, onCallEnded: () => navigator.pop());
```

Sessions come from `CallwaveFlutter.sessions` or `CallwaveFlutter.getSession`.
`CallwaveScope` pushes `CallScreen` automatically when sessions are created.

## Notes

- Native accept/decline/end remains authoritative.
- `CallSession` is the single source of truth for UI state.
- `CallwaveScope` auto-pushes one call screen per `callId` and does not auto-pop.
- `CallwaveScope.navigatorKey` must be the same key used by your app's `MaterialApp`.
- `CallwaveEngine` must be set before session operations (including `restoreActiveSessions`).
