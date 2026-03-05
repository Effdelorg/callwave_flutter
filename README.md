# callwave_flutter

MIT-licensed federated Flutter plugin for WhatsApp-style VoIP call UX.

## Why callwave_flutter?

**Plug-and-play call UI for WebRTC video and audio calls.** Add WhatsApp-style incoming/outgoing call screens to your Flutter app in minutes—no reinventing the wheel.

- **Works with any WebRTC backend** — LiveKit, Agora, Twilio, Daily, VideoSDK, Cloudflare Calls (Real-time), or your own. Implement `CallwaveEngine`, wire your SDK in a few callbacks, and you're done.
- **Native UX out of the box** — Full-screen incoming call UI on Android, CallKit on iOS. Handles accept, decline, timeout, missed, and callback flows.
- **Cold-start ready** — Event buffering and startup route resolution so calls work even when the app launches from a push notification.
- **Conference support** — Built-in multi-participant UI with customizable tiles and controls.

If you're building video or voice calls with WebRTC, callwave_flutter gives you the call UX layer so you can focus on your media and signaling.

> **Platform status:** Android has custom native incoming call UI (`FullScreenCallActivity`) and full call UX (full-screen incoming, notifications, etc.). iOS uses CallKit system UI for incoming calls (Apple's native UI; no custom UI from the plugin). In-app call screen (`CallScreen`) is shared Flutter UI on both platforms.

## Workspace Layout

- `packages/callwave_flutter`: Public API for app developers.
- `packages/callwave_flutter_platform_interface`: Shared contracts and DTOs.
- `packages/callwave_flutter_method_channel`: Internal MethodChannel + native Android/iOS implementations.
- `packages/callwave_flutter/example`: Demo app for manual call flow testing.

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

### 1:1 Split-to-PiP Customization

For one-to-one connected video, inject your remote/local RTC surfaces through
`CallwaveScope`:

```dart
CallwaveScope(
  navigatorKey: navKey,
  oneToOneRemoteVideoBuilder: (context, session) {
    return rtcRemoteView(session.callId);
  },
  oneToOneLocalVideoBuilder: (context, session) {
    return rtcLocalView(session.callId);
  },
  child: child!,
);
```

Built-in behavior:

- Connected one-to-one starts in a centered `50/50` split using two square
  tiles (remote top, local bottom).
- Tap either tile to promote it into a large square primary surface with a
  bottom-right square PiP.
- Tap the large surface to return to split; tap PiP to swap primary/secondary.
- Built-in video framing uses cover-fit behavior (crop allowed, no stretch).
- If builders are not provided, Callwave renders safe fallback tiles.

For custom RTC widgets, wrap views in `VideoViewport` to preserve camera
geometry in square tiles:

```dart
oneToOneRemoteVideoBuilder: (context, session) {
  return VideoViewport(
    aspectRatio: 16 / 9,
    fit: BoxFit.cover,
    child: rtcRemoteView(session.callId),
  );
},
```

See `packages/callwave_flutter/README.md` for full API details.

## Local Development

1. Install melos (`dart pub global activate melos`).
2. Bootstrap workspace (`melos bootstrap`).
3. Analyze (`melos run analyze`).
4. Test (`melos run test`).
