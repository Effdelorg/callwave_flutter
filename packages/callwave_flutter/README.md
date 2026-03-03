# callwave_flutter

Public Flutter API for Callwave VoIP call UX.

This package exposes clean Dart models and methods.
It does not expose MethodChannel objects directly.

## Usage

```dart
await CallwaveFlutter.instance.showIncomingCall(
  const CallData(
    callId: 'c-42',
    callerName: 'Alex',
    handle: '+1 555 0100',
  ),
);
```

Listen to events:

```dart
CallwaveFlutter.instance.events.listen((event) {
  if (event.type == CallEventType.incoming) {
    // open incoming custom call screen with Accept / Decline
  }
  if (event.type == CallEventType.accepted) {
    // open call screen
  }
});
```

`CallEventType.incoming` from notification/full-screen tap is Android behavior.
On iOS, incoming UI remains CallKit-managed system UI.

When users tap `Answer` from Android system incoming UI (foreground, background,
or terminated app), the plugin emits `accepted`, brings the app to the
foreground, and switches the notification to an ongoing call notification.
On iOS, CallKit remains system-managed; the plugin emits `accepted` with merged
caller metadata so apps can restore/open custom UI when active.

Answer or decline from custom UI:

```dart
try {
  await CallwaveFlutter.instance.acceptCall('c-42');
  // or: await CallwaveFlutter.instance.declineCall('c-42');
} catch (error) {
  // invalid/expired callId, or call no longer active
}
```

`CallScreen` auto-return behavior:

- When a call ends (`ended`, `declined`, `missed`, or `timeout`), `CallScreen`
  auto-returns to the previous screen if one exists.
- If `CallScreen` is the root route (no previous route), it stays on the
  current screen and does not force navigation.

Optional post-call behavior:

```dart
await CallwaveFlutter.instance.setPostCallBehavior(
  PostCallBehavior.backgroundOnEnded,
);
```
