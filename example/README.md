# callwave_flutter Example

This example app demonstrates the public API of `callwave_flutter`.

## Run

```bash
flutter pub get
flutter run
```

## Manual Test Flows

1. Tap `Notif Permission` (Android 13+).
2. Tap `FullScreen Permission` (Android 14+).
3. Tap `Incoming` to show the incoming call UI.
4. Tap the incoming call details to open custom Flutter call UI.
5. Tap `Accept` or `Decline` from that custom UI.
6. Check the in-app event log.

Note: the custom incoming screen trigger on notification/details tap is Android behavior. iOS uses CallKit system incoming UI.

Cold-start example:
- Trigger `Incoming`.
- Kill the app (or swipe it away).
- Tap `Accept` on the incoming UI shown (native full-screen overlay when app was killed; custom Flutter UI if app was merely in background).
- Re-open app and confirm buffered `accepted` event is shown.

Timeout behavior:
- Foreground/background: if `CallScreen` is open and the call times out, the
  screen auto-returns to the previous route.
- Terminated/cold-start timeout: no in-app back navigation is forced; rely on
  system handling (for Android this is the missed-call notification).
