# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Development Commands

This is a Melos monorepo. Install melos first: `dart pub global activate melos`.

```bash
melos bootstrap          # Link all packages and resolve dependencies
melos run analyze        # Run flutter analyze across all packages
melos run test           # Run tests across all packages
```

To work on a single package:
```bash
cd packages/callwave_flutter           # or any sub-package
flutter test                           # run tests for that package only
flutter test test/callwave_flutter_test.dart  # run a single test file
flutter analyze                        # analyze a single package
```

To run the example app: `cd example && flutter run`

## Architecture

This is a **federated Flutter plugin** for WhatsApp-style VoIP call UX (incoming/outgoing call notifications, accept/decline/timeout/missed/callback events). It does NOT handle media, signaling, or audio.

### Three-Package Structure

1. **`callwave_flutter`** — Public-facing package. Singleton `CallwaveFlutter.instance` exposes `showIncomingCall()`, `showOutgoingCall()`, `endCall()`, `markMissed()`, and a `Stream<CallEvent> events`. Converts between public models (`CallData`, `CallEvent`) and internal DTOs (`CallDataDto`, `CallEventDto`).

2. **`callwave_flutter_platform_interface`** — Abstract `CallwaveFlutterPlatform` (extends `PlatformInterface`) defining the contract. Contains DTOs, enums with wire serialization (`wireValue`/`tryFromWireValue`), and `PayloadCodec` for Dart map ↔ DTO conversion.

3. **`callwave_flutter_method_channel`** — Concrete implementation using `MethodChannel('callwave_flutter/methods')` and `EventChannel('callwave_flutter/events')`. Contains all native Android (Kotlin) and iOS (Swift) code.

### Data Flow

```
App → CallwaveFlutter (public models) → CallwaveFlutterPlatform (DTOs)
    → MethodChannelCallwaveFlutter → MethodChannel/EventChannel → Native code
```

Public `CallData` uses `Duration timeout`; DTO uses `int timeoutSeconds`. Public `CallEvent` uses `DateTime timestamp`; DTO uses `int timestampMs`.

### Native Platforms

**Android (Kotlin)** — `com.callwave.flutter.methodchannel`:
- `CallwaveRuntime` (singleton) initializes all components via `ensureInitialized(context)`
- `AndroidCallManager` orchestrates notifications, timeout scheduling (`AlarmManager`), and event emission
- `FullScreenCallActivity` shows over the lock screen for cold-start incoming calls
- `CallActionReceiver` (BroadcastReceiver) handles accept/decline/timeout/callback actions
- `CallNotificationManager` builds `CATEGORY_CALL` and `CATEGORY_MISSED_CALL` notifications

**iOS (Swift)** — CallKit integration:
- `IOSCallManager` wraps `CXProvider` + `CXCallController` for system call UI
- `CallKitProviderDelegate` forwards accept/end/reset callbacks via closures
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

- Dart SDK: `>=3.3.0 <4.0.0`
- Flutter: `>=3.22.0`
- iOS: 13.0+
- Android: uses `AlarmManager`, `POST_NOTIFICATIONS` (API 33+), `USE_FULL_SCREEN_INTENT` (API 34+)
