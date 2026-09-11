# callwave_flutter — Agent Guide

Federated Flutter plugin for WhatsApp-style VoIP call UX (incoming call UI, accept/decline/timeout, CallKit/Android full-screen intents). No WebRTC/SIP/audio routing.

Always check for race conditions in the code and fix them.

## Build & Development Commands

From the repo root:

```bash
dart pub get
dart run melos run analyze
dart run melos run test
```

For a single package:

```bash
cd packages/callwave_flutter
flutter test
flutter analyze
```

Example app: `cd packages/callwave_flutter/example && flutter run`

## Workspace Structure

| Package | Role |
|---------|------|
| `packages/callwave_flutter` | Public API for app developers |
| `packages/callwave_flutter_platform_interface` | Shared contracts, DTOs, codec |
| `packages/callwave_flutter_method_channel` | MethodChannel + Android (Kotlin) / iOS (Swift) |
| `packages/callwave_flutter/example` | Demo app for manual testing |

**iOS native sources** (for edits to CallKit / channels): `packages/callwave_flutter_method_channel/ios/callwave_flutter_method_channel/Sources/callwave_flutter_method_channel/`; SPM entrypoint `ios/callwave_flutter_method_channel/Package.swift`; CocoaPods `ios/callwave_flutter_method_channel.podspec`.

## Architecture

Public API is `CallwaveFlutter.instance` (`showIncomingCall()`, `showOutgoingCall()`, `endCall()`, `markMissed()`, `Stream<CallEvent> events`). It converts public models to DTOs, then the method channel talks to native code.

```
App → CallwaveFlutter (public models) → CallwaveFlutterPlatform (DTOs)
 → MethodChannelCallwaveFlutter → MethodChannel/EventChannel → Native code
```

Public `CallData` uses `Duration timeout`; DTO uses `int timeoutSeconds`. Public `CallEvent` uses `DateTime timestamp`; DTO uses `int timestampMs`.

**Android (Kotlin)** — `com.callwave.flutter.methodchannel`:
- `CallwaveRuntime` initializes via `ensureInitialized(context)`
- `AndroidCallManager` orchestrates notifications, timeout (`AlarmManager`), and events
- `FullScreenCallActivity` shows over the lock screen for cold-start incoming calls
- `CallActionReceiver` handles accept/decline/timeout/callback
- `CallNotificationManager` builds `CATEGORY_CALL` and `CATEGORY_MISSED_CALL` notifications

**iOS (Swift)**:
- `IOSCallManager` wraps `CXProvider` + `CXCallController` for CallKit
- `CallKitProviderDelegate` forwards accept/end/reset callbacks
- `NotificationDelegateProxy` forwards `UNUserNotificationCenter` callbacks so missed-call notifications still show in the foreground
- Timeout via `DispatchWorkItem` calling `provider.reportCall(endedAt:reason:.unanswered)`
- `requestNotificationPermission` always returns `true`; `requestFullScreenIntentPermission` is a no-op

### Event Buffering (Cold Start)

Both platforms persist events to disk when the Flutter engine is not attached:
- Android: `SharedPreferences` as `JSONArray`; iOS: `UserDefaults` as `[Data]`
- Max 50 events, 10-minute TTL, deduplication by `"callId|type|secondBucket"`
- On `onListen`, buffered events flush in order

### Call Exclusivity

`ActiveCallRegistry.tryStart()` on both platforms only allows one active `callId` at a time. A second distinct `callId` is rejected. The same `callId` is re-entrant.

## SDK Requirements

- Dart SDK: `^3.11.0`
- Flutter: `>=3.41.0` (required for iOS Swift Package Manager support alongside CocoaPods)
- iOS: 13.0+
- Android: uses `AlarmManager`, `POST_NOTIFICATIONS` (API 33+), `USE_FULL_SCREEN_INTENT` (API 34+)

## Conventions

- **Clean architecture**: Platform interface defines contracts; method channel implements them.
- **Workspace**: Use `dart pub get` at root; `dart run melos run analyze` / `dart run melos run test` for cross-package tasks.
- Keep changes minimal. Follow existing patterns in the codebase.
- iOS minimum is 13.0. Do not use `.banner` or `.list` notification presentation options without an `#available(iOS 14.0, *)` fallback to `.alert`.

## What Not to Add

- WebRTC, SIP signaling, audio routing/recording (out of scope).
