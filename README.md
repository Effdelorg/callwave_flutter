# callwave_flutter

MIT-licensed federated Flutter plugin for WhatsApp-style VoIP call UX.

## Workspace Layout

- `packages/callwave_flutter`: Public API for app developers.
- `packages/callwave_flutter_platform_interface`: Shared contracts and DTOs.
- `packages/callwave_flutter_method_channel`: Internal MethodChannel + native Android/iOS implementations.
- `example`: Demo app for manual call flow testing.

## What This Plugin Does

- Shows system-level incoming call UI.
- Handles accept, decline, timeout, missed, callback, and end events.
- Exposes a session-first orchestration model via `CallwaveEngine` + `CallSession`.
- Buffers native events in memory + disk for cold start delivery.
- Supports Android permission flows for notifications and full-screen intents.
- Uses iOS CallKit.

## What This Plugin Does Not Do

- WebRTC media
- SIP signaling
- Audio routing/recording

## Quick Example

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final navKey = GlobalKey<NavigatorState>();
  CallwaveFlutter.instance.setEngine(MyCallwaveEngine());
  final startup = await CallwaveFlutter.instance.prepareStartupRouteDecision();

  runApp(
    MaterialApp(
      navigatorKey: navKey,
      initialRoute: startup.shouldOpenCall ? '/call' : '/home',
      routes: {
        '/home': (_) => const HomeScreen(),
        '/call': (_) => StartupCallRoute(callId: startup.callId),
      },
      builder: (_, child) => CallwaveScope(
        navigatorKey: navKey,
        preRoutedCallIds: startup.callId == null ? const <String>{} : {startup.callId!},
        child: child!,
      ),
    ),
  );
}
```

See `packages/callwave_flutter/README.md` for full setup and cold-start details.

Optional post-call behavior:

```dart
await CallwaveFlutter.instance.setPostCallBehavior(
  PostCallBehavior.backgroundOnEnded,
);
```

`backgroundOnEnded` is applied on Android (moves app task to background after `endCall`).
On iOS, the setting is accepted but intentionally no-op.

## WebRTC Integration

callwave_flutter is the call UI layer; you provide media and signaling via `CallwaveEngine`. When the user accepts or starts a call, your engine connects WebRTC (e.g. `flutter_webrtc`, `videosdk,realtimekit_core`) and calls `session.reportConnected()` when ready.

**Recommended `CallData.extra` keys** for WebRTC backends — use `CallDataExtraKeys` constants:

| Constant | Example | Used by |
|----------|---------|---------|
| `CallDataExtraKeys.roomId` | `"room-abc123"` | LiveKit, Agora, Twilio Rooms |
| `CallDataExtraKeys.meetingId` | `"meet-xyz"` | Zoom, Google Meet, etc. |
| `CallDataExtraKeys.peerId` / `remoteUserId` | `"user-xyz"` | Custom signaling, peer-to-peer |
| `CallDataExtraKeys.signalingUrl` | `"wss://..."` | WebSocket signaling server |
| `CallDataExtraKeys.token` | JWT or access token | LiveKit, Agora, etc. |
| `CallDataExtraKeys.sipUri` | `"sip:user@domain"` | SIP-based SDKs |

These are conventions, not required. Different SDKs use different names; `extra` stays flexible.

**Minimal example** wiring `flutter_webrtc` to `onAnswerCall`:

```dart
class WebRTCEngine extends CallwaveEngine {
  @override
  Future<void> onAnswerCall(CallSession session) async {
    final roomId = session.callData.extra?[CallDataExtraKeys.roomId] as String?;
    final token = session.callData.extra?[CallDataExtraKeys.token] as String?;
    if (roomId == null || token == null) return;
    // Connect to your WebRTC room, then:
    session.reportConnected();
  }

  @override
  Future<void> onStartCall(CallSession session) async {
    // Same pattern for outgoing
    session.reportConnected();
  }

  @override
  Future<void> onEndCall(CallSession session) async {}
  @override
  Future<void> onDeclineCall(CallSession session) async {}
  // ... other callbacks
}
```

**Cold start:** Include WebRTC data (roomId, peerId, token, etc.) in your push payload. When the app is woken by push, parse it and call `showIncomingCall(CallData(..., extra: {...}))` with full `extra` so the engine has connection data when the user accepts.

## Conference UI (Current Style)

The built-in UI now supports conference mode while preserving the current
Callwave look.

- Conference mode is enabled when `CallSession.participantCount > 1`.
- The conference control area is a plain bottom row in `SafeArea` (no rounded
  dock container).
- Default conference controls are `Mic`, `Speaker`, `Cam`, and `End`.
- Single-party calls still use the existing one-to-one `CallScreen` layout.

Update conference participants from your app/WebRTC integration:

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

Customize conference rendering through `CallwaveScope`:

```dart
CallwaveScope(
  navigatorKey: navKey,
  participantTileBuilder: (context, session, participant, isPrimary) {
    return ColoredBox(
      color: isPrimary ? const Color(0xFF0D4F4F) : const Color(0xFF1A6B6B),
      child: Center(child: Text(participant.displayName)),
    );
  },
  child: child!,
);
```

See `packages/callwave_flutter/README.md` for full API details.

## Local Development

1. Install melos (`dart pub global activate melos`).
2. Bootstrap workspace (`melos bootstrap`).
3. Analyze (`melos run analyze`).
4. Test (`melos run test`).
