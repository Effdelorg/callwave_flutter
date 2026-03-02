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
4. Tap `Accept` or `Decline` from system UI.
5. Check the in-app event log.

Cold-start example:
- Trigger `Incoming`.
- Kill the app.
- Tap `Accept` on incoming UI.
- Re-open app and confirm buffered `accepted` event is shown.
