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

Incoming flow selector:
- `Realtime` keeps the old behavior: native accept goes straight into
  `Connecting...` and opens the call screen.
- `Validated Allow` waits for a short async validation, then opens the call.
- `Validated Reject` waits for validation and then converts the accept into
  missed-call handling without opening the call screen or forcing the app back
  to foreground.

Accepted ongoing notification checks (Android):
- Accept an incoming call so the ongoing call notification appears.
- Try to swipe the ongoing notification away. It should stay visible.
- Tap the notification body/details area. The app should open to the ongoing call UI.
- Expand the ongoing notification. It should expose only `End call` (no snooze action in app-provided controls).
- Tap `End call` and confirm the call ends and the ongoing notification is removed.
- After the call has ended and the notification is removed, tapping stale UI should not reopen a call screen.

Outgoing ongoing notification checks (Android):
- Tap `Outgoing Audio` or `Outgoing Video`.
- Confirm the native notification title is `Call Ongoing`.
- Try to swipe the ongoing notification away. It should stay visible.
- Tap the notification body/details area. The app should open to the ongoing call UI.
- Expand the ongoing notification. It should expose only `End call`.
- Tap `End call` and confirm the call ends and the ongoing notification is removed.
- After the call has ended and the notification is removed, tapping stale UI should not reopen a call screen.

Missed notification custom text example (Android):
- In `Missed Notification Text`, enter `You missed a notification from {name}.`
- Tap `Incoming Audio` to create the call payload with that text.
- Tap `Missed` for the same call ID.
- Confirm the missed-call notification body uses your custom text, for example `You missed a notification from Ava.`

Note: the custom missed text is read from the call payload created by `Incoming` or `Outgoing`. If you tap `Missed` before starting a call, or edit the text after starting the call, Android will use the older/default payload instead.

Note: the custom incoming screen trigger on notification/details tap is Android behavior. iOS uses CallKit system incoming UI.

Cold-start example:
- Trigger `Incoming`.
- Kill the app (or swipe it away).
- In `Realtime`, tap `Accept` on the incoming UI shown. The app opens the call
  flow immediately and shows the ongoing call notification.
- In `Validated Reject`, tap `Accept` on the incoming UI shown. The example
  runs validation in a transient native Android bridge and resolves directly
  into missed-call handling without showing the Flutter call UI.
- In `Validated Allow`, tap `Accept` on the incoming UI shown. The example
  waits for validation and then opens the call only after approval.
- If the app was only in background, `Validated Reject` should stay off the
  foreground and end in missed-call handling.

Timeout behavior:
- Foreground/background: if `CallScreen` is open and the call times out, the
  screen auto-returns to the previous route.
- Terminated/cold-start timeout: no in-app back navigation is forced; rely on
  system handling (for Android this is the missed-call notification).
