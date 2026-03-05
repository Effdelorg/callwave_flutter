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

Accepted ongoing notification checks (Android):
- Accept an incoming call so the ongoing call notification appears.
- Try to swipe the ongoing notification away. It should stay visible.
- Tap the notification body/details area. The app should open to the ongoing call UI.
- Expand the ongoing notification. It should expose only `End call` (no snooze action in app-provided controls).
- Tap `End call` and confirm the call ends and the ongoing notification is removed.
- After the call has ended and the notification is removed, tapping stale UI should not reopen a call screen.

Note: the custom incoming screen trigger on notification/details tap is Android behavior. iOS uses CallKit system incoming UI.

Cold-start example:
- Trigger `Incoming`.
- Kill the app (or swipe it away).
- Tap `Accept` on the incoming UI shown (native full-screen overlay when app was killed; custom Flutter UI if app was merely in background).
- The app is brought to foreground, custom call UI opens in joined flow
  (`Connecting...` then timer), and
  an ongoing call notification is shown.
- The ongoing notification cannot be swiped away and includes `End call`.
- Confirm the event log contains one `accepted` event for that tap.

Timeout behavior:
- Foreground/background: if `CallScreen` is open and the call times out, the
  screen auto-returns to the previous route.
- Terminated/cold-start timeout: no in-app back navigation is forced; rely on
  system handling (for Android this is the missed-call notification).
