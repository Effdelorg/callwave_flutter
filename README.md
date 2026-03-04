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
CallwaveFlutter.instance.setEngine(MyCallwaveEngine());
await CallwaveFlutter.instance.restoreActiveSessions();
```

Optional post-call behavior:

```dart
await CallwaveFlutter.instance.setPostCallBehavior(
  PostCallBehavior.backgroundOnEnded,
);
```

`backgroundOnEnded` is applied on Android (moves app task to background after `endCall`).
On iOS, the setting is accepted but intentionally no-op.

## Local Development

1. Install melos (`dart pub global activate melos`).
2. Bootstrap workspace (`melos bootstrap`).
3. Analyze (`melos run analyze`).
4. Test (`melos run test`).
