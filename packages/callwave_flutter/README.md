# callwave_flutter

Public Flutter API for Callwave VoIP call UX.

This package is session-first. You provide a `CallwaveEngine` and the package handles
call-session orchestration, call-screen state, and navigation hooks.

## Core Flow

1. Register your engine.
2. Restore active sessions on startup.
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

final navKey = GlobalKey<NavigatorState>();
CallwaveFlutter.instance.setEngine(MyCallwaveEngine());
await CallwaveFlutter.instance.restoreActiveSessions();

MaterialApp(
  navigatorKey: navKey,
  builder: (_, child) => CallwaveScope(
    navigatorKey: navKey,
    child: child!,
  ),
);
```

## Cold Start

When the app launches from a cold start (e.g. user tapped Accept on the native
full-screen UI while the app was killed), call `restoreActiveSessions()` early in
startup. It fetches active call IDs from the platform and creates sessions in
`connecting` state. Call metadata may be minimal (e.g. `callerName: 'Unknown'`)
until events arrive; store richer data in `CallData.extra` if you need it on
restore.

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
