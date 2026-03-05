# callwave_flutter_method_channel

Internal MethodChannel implementation for `callwave_flutter`.

## Why callwave_flutter?

**Plug-and-play call UI for WebRTC video and audio calls.** Add WhatsApp-style incoming/outgoing call screens to your Flutter app in minutes—no reinventing the wheel.

- **Works with any WebRTC backend** — LiveKit, Agora, Twilio, Daily, VideoSDK, Cloudflare Calls (Real-time), or your own. Implement `CallwaveEngine`, wire your SDK in a few callbacks, and you're done.
- **Native UX out of the box** — Full-screen incoming call UI on Android, CallKit on iOS. Handles accept, decline, timeout, missed, and callback flows.
- **Cold-start ready** — Event buffering and startup route resolution so calls work even when the app launches from a push notification.
- **Conference support** — Built-in multi-participant UI with customizable tiles and controls.

If you're building video or voice calls with WebRTC, callwave_flutter gives you the call UX layer so you can focus on your media and signaling. **App developers should use [callwave_flutter](https://pub.dev/packages/callwave_flutter), not this package directly.**

> **Platform status:** Android has custom native incoming call UI (`FullScreenCallActivity`) and full call UX. iOS uses CallKit system UI for incoming calls (Apple's native UI; no custom UI from the plugin). In-app call screen is shared Flutter UI on both platforms.

## Contains
- Dart MethodChannel/EventChannel bridge
- Android native implementation (notifications, actions, buffering)
- iOS native implementation (CallKit, buffering)

App developers should use `callwave_flutter`, not this package directly.
