# callwave_flutter

A Flutter plugin that gives your app a beautiful, native call UI — like WhatsApp or FaceTime — without building it from scratch.

---

## What does this package do?

When someone calls a user of your app, this plugin handles everything the user **sees and hears**:

- A full-screen incoming call screen that appears even when the app is closed
- The ringtone that plays while the phone rings
- Buttons to **accept**, **decline**, or let it time out
- A missed call notification if they don't answer
- A ready-made in-call screen with mute, speaker, camera, and end buttons
- Group/conference call UI when multiple people join

It works on both **Android** and **iOS** using the same Flutter code.

> This plugin handles call **UI and events only**. You still connect your own audio/video SDK (LiveKit, Agora, Twilio, etc.) — this plugin just shows the screens and tells you what the user did.

---

## Use the built-in UI, or bring your own

callwave_flutter ships a complete, production-ready call UI for every scenario. You can use it as-is, or swap in your own screens — your choice.

| Scenario | Built-in UI | Bring your own UI |
|----------|:-----------:|:-----------------:|
| Incoming call (lock screen) | ✅ | — (native OS handles this) |
| 1-to-1 audio call | ✅ | ✅ |
| 1-to-1 video call | ✅ | ✅ |
| Group / conference call | ✅ | ✅ |
| Video feeds (remote + local) | ✅ fallback tiles | ✅ inject your RTC widget |

**Use the default UI** — drop `CallwaveScope` into your app and you get a polished call screen immediately with no extra work.

**Customize pieces** — keep the layout but inject your own video widgets, conference tiles, or control buttons.

**Replace it entirely** — use only the event system and call your own screens from `CallwaveEngine` callbacks.

---

## What can you build with it?

- A WhatsApp-style voice or video calling feature in your app
- A team communication app with group calls
- A telehealth or customer support app with inbound calls
- Any app where users need to receive and make calls

---

## How it looks

| Incoming call | Native incoming (Android) |
|:---:|:---:|
| ![Incoming call](https://raw.githubusercontent.com/Effdelorg/callwave_flutter/main/packages/callwave_flutter/screenshots/Incoming_call_ui.png) | ![Native plugin](https://raw.githubusercontent.com/Effdelorg/callwave_flutter/main/packages/callwave_flutter/screenshots/Incoming_call_native_plugin_UI.png) |

| Missed call | Group video call |
|:---:|:---:|
| ![Missed call](https://raw.githubusercontent.com/Effdelorg/callwave_flutter/main/packages/callwave_flutter/screenshots/Missed_call_ui.png) | ![Video conference](https://raw.githubusercontent.com/Effdelorg/callwave_flutter/main/packages/callwave_flutter/screenshots/Video_conference_call_ui.png) |

| 1-to-1 audio | 1-to-1 video |
|:---:|:---:|
| ![1-to-1 audio](https://raw.githubusercontent.com/Effdelorg/callwave_flutter/main/packages/callwave_flutter/screenshots/1to1_ui.png) | ![1-to-1 video](https://raw.githubusercontent.com/Effdelorg/callwave_flutter/main/packages/callwave_flutter/screenshots/1to1_video.png) |

---

## Platform support

| Feature | Android | iOS |
|---------|---------|-----|
| Incoming call screen (lock screen) | Full-screen native activity | CallKit (Apple system UI) |
| In-app call screen | Flutter (shared) | Flutter (shared) |
| Ongoing call notification | Yes | Yes (CallKit) |
| Missed call notification | Yes | Yes |
| Ringtone | Yes | Yes (CallKit) |

---

## Getting started in 3 steps

### Step 1 — Tell the plugin what to do when a call is accepted or ended

You implement a simple `CallwaveEngine` class with callbacks for each action:

```dart
class MyCallEngine extends CallwaveEngine {
  @override
  Future<void> onAnswerCall(CallSession session) async {
    // User accepted — connect your audio/video SDK here
    final roomToken = session.callData.extra?['roomToken'];
    await mySdk.join(roomToken);
    session.reportConnected(); // tell the plugin the call is live
  }

  @override
  Future<void> onStartCall(CallSession session) async {
    // User started an outgoing call
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
```

### Step 2 — Configure and wrap your app

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final navKey = GlobalKey<NavigatorState>();

  // Register your engine
  CallwaveFlutter.instance.configure(
    CallwaveConfiguration(
      engine: MyCallEngine(),
      incomingCallHandling: const IncomingCallHandling.realtime(),
    ),
  );

  // Check if the app was opened from a call notification
  final startup = await CallwaveFlutter.instance.prepareStartupRouteDecision();

  runApp(
    MaterialApp(
      navigatorKey: navKey,
      // Go straight to the call screen if opened from a notification
      initialRoute: startup.shouldOpenCall ? '/call' : '/home',
      routes: {
        '/home': (_) => const HomeScreen(),
        '/call': (_) => StartupCallRoute(callId: startup.callId),
      },
      builder: (_, child) => CallwaveScope(
        navigatorKey: navKey,
        preRoutedCallIds: startup.callId == null ? {} : {startup.callId!},
        child: child!,
      ),
    ),
  );
}
```

### Step 3 — Trigger an incoming call from your push notification handler

When your server sends a push notification for an incoming call, call this:

```dart
await CallwaveFlutter.instance.showIncomingCall(
  CallData(
    callId: 'call-123',
    callerName: 'Alice',
    handle: '+1 555 0101',
    callType: CallType.video,
    timeout: const Duration(seconds: 30),
    extra: {'roomToken': 'your-sdk-token-here'},
  ),
);
```

The plugin takes care of the rest — showing the incoming call screen, playing the ringtone, and routing the accept/decline back to your engine.

---

## Call UI in detail

### 1-to-1 audio call

Out of the box you get a clean audio call screen with the caller's avatar, name, call timer, and controls for mute, speaker, and end. No configuration needed.

### 1-to-1 video call

The video call screen starts in a 50/50 split (remote video on top, your camera on the bottom). Tap either tile to promote it to full screen with the other in a picture-in-picture corner. Tap again to swap or go back to split.

To show live video from your SDK, inject your video widgets:

```dart
CallwaveScope(
  navigatorKey: navKey,
  oneToOneRemoteVideoBuilder: (context, session) => yourRemoteVideoWidget(),
  oneToOneLocalVideoBuilder: (context, session) => yourLocalVideoWidget(),
  child: child!,
)
```

If you don't provide widgets, the plugin shows a safe placeholder so the UI still works while you set up your SDK.

### Group / conference call

When there is more than one participant, the call screen automatically switches to a conference layout — no extra setup needed. Push participant updates from your SDK:

```dart
session.updateConferenceState(
  ConferenceState(
    participants: [
      CallParticipant(participantId: 'p-1', displayName: 'Ava'),
      CallParticipant(participantId: 'p-2', displayName: 'Milo'),
      CallParticipant(participantId: 'local', displayName: 'You', isLocal: true),
    ],
    activeSpeakerId: 'p-1',
    updatedAtMs: DateTime.now().millisecondsSinceEpoch,
  ),
);
```

Customize how each participant tile looks by providing your own builder:

```dart
CallwaveScope(
  navigatorKey: navKey,
  participantTileBuilder: (context, session, participant, isPrimary) {
    return YourVideoTileWidget(participantId: participant.participantId);
  },
  child: child!,
)
```

### Replacing the UI entirely

If you want full control, skip `CallScreen` and `CallwaveScope` entirely. Listen to call events from your `CallwaveEngine` callbacks and navigate to your own screens. The plugin still handles the native incoming call UI, ringtone, notifications, and events — you just provide the in-call experience.

---

## More features

### Works with any audio/video SDK

Pass your room token, meeting ID, or any data you need in the `extra` field of `CallData`. Common keys are available as constants in `CallDataExtraKeys`:

```dart
extra: {
  CallDataExtraKeys.roomId: 'room-abc',
  CallDataExtraKeys.token: 'jwt-token',
}
```

Works with LiveKit, Agora, Twilio, Daily, VideoSDK, Cloudflare Calls, and any custom backend.

### Outgoing calls

```dart
await CallwaveFlutter.instance.showOutgoingCall(
  CallData(callId: 'call-456', callerName: 'Bob', handle: 'bob@example.com'),
);
```

### End a call

```dart
await CallwaveFlutter.instance.endCall('call-123');
```

### Mark a call as missed

```dart
await CallwaveFlutter.instance.markMissed('call-123');
```

### Ringtone behavior

- Ringtone plays until the user accepts, declines, or the timeout is reached
- `accept at 10s` → ringtone stops, call moves to active state
- `decline at 10s` → ringtone stops, incoming UI is dismissed
- `timeout at 30s` → ringtone stops, missed call notification is shown

### Android exact alarm permission (Android 12+)

For reliable timeout scheduling, check and request exact alarm permission:

```dart
final canSchedule = await CallwaveFlutter.instance.canScheduleExactAlarms();
if (!canSchedule) {
  await CallwaveFlutter.instance.requestExactAlarmPermission();
}
```

---

## What this plugin does NOT handle

- Transmitting audio or video (WebRTC media)
- Signaling protocols (SIP, WebSocket signaling)
- Call recording

These belong to your audio/video SDK. callwave_flutter handles the UI layer only.

---

## Full API docs

See [`packages/callwave_flutter/README.md`](packages/callwave_flutter/README.md) for the complete API reference including validated accept flows, cold-start details, Android manifest setup, and iOS AppDelegate configuration.

---

## Local development

```bash
dart pub global activate melos
dart pub get          # install workspace dependencies
dart run melos run analyze  # lint all packages
dart run melos run test     # test all packages
```
