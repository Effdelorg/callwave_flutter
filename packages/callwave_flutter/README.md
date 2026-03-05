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

For standalone usage outside `CallwaveScope`, you can pass `theme` directly:

```dart
CallScreen(
  session: session,
  theme: const CallwaveThemeData(),
)
```

Sessions come from `CallwaveFlutter.sessions` or `CallwaveFlutter.getSession`.
`CallwaveScope` pushes `CallScreen` automatically when sessions are created.

## Conference UI (Current Style)

`CallScreen` automatically switches to conference mode when
`session.participantCount > 1`.

- Keeps the current Callwave visual style (same gradient/action-button language).
- Uses a plain bottom control row in `SafeArea` (no rounded dock container).
- Default video conference controls: `Mic`, `Speaker`, `Cam`, `End`.
- Default audio conference controls: `Mic`, `Speaker`, `End`.
- One-to-one UI remains unchanged for `participantCount <= 1`.

### Conference State API

Use `CallSession.updateConferenceState` to provide participants and speaker data.

```dart
session.updateConferenceState(
  ConferenceState(
    participants: const [
      CallParticipant(participantId: 'p-1', displayName: 'Ava'),
      CallParticipant(participantId: 'p-2', displayName: 'Milo'),
      CallParticipant(participantId: 'local', displayName: 'You', isLocal: true),
    ],
    activeSpeakerId: 'p-1',
    updatedAtMs: DateTime.now().millisecondsSinceEpoch,
  ),
);
```

Race-safety rules:

- Older `updatedAtMs` snapshots are ignored.
- Updates are ignored once the session is ended/failed.
- Duplicate `participantId` entries are deduped (latest entry wins).

### Optional Builders

`CallwaveScope` provides conference customization hooks:

```dart
CallwaveScope(
  navigatorKey: navKey,
  participantTileBuilder: (context, session, participant, isPrimary) {
    // Inject your RTC view for this participant.
    return ColoredBox(
      color: isPrimary ? const Color(0xFF0D4F4F) : const Color(0xFF1A6B6B),
      child: Center(child: Text(participant.displayName)),
    );
  },
  conferenceControlsBuilder: (context, session) {
    // Optional: override the default Mic/Speaker/Cam/End row.
    return const SizedBox.shrink();
  },
  child: child!,
)
```

You can also replace the entire conference surface with
`conferenceScreenBuilder`.

## Notes

- Native accept/decline/end remains authoritative.
- `CallSession` is the single source of truth for UI state.
- `CallwaveScope` auto-pushes one call screen per `callId` and does not auto-pop.
- `CallwaveScope.navigatorKey` must be the same key used by your app's `MaterialApp`.
- `CallwaveEngine` must be set before session operations (including `restoreActiveSessions`).
