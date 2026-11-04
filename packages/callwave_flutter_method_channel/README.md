# callwave_flutter_method_channel

Native Android and iOS implementation for
[callwave_flutter](https://pub.dev/packages/callwave_flutter).
App developers should depend on the public package.

## Version and requirements

Version `0.4.0` uses `callwave_flutter_platform_interface: ^0.4.0` and ships with
`callwave_flutter: ^0.7.0`.

- Dart `^3.11.0` and Flutter `>=3.41.0`.
- Android API 26+: incoming and ongoing notifications, full-screen incoming call
  UI, actions, timeouts, and buffered events.
- iOS 13+: CallKit, missed-call notifications, and buffered events. Both CocoaPods
  and Swift Package Manager are supported. The package includes a privacy
  manifest for its `UserDefaults` use.

## Outgoing ringback

`CallDataDto.ringbackStartMode` defaults to `RingbackStartMode.automatic`.
The wire values are `automatic` and `appControlled`; missing or unknown values
use `automatic`.

| Mode | Android startup | iOS startup |
| --- | --- | --- |
| `automatic` | Screen readiness | CallKit audio activation |
| `appControlled` | Screen readiness and host permission | Screen readiness, host permission, and CallKit audio activation |

`playRingback: false` disables sound in either mode. The host owns audio routing.
`maxRingbackSeconds` limits playback, not call duration. The iOS cap starts at
successful playback and is not extended by audio reactivation.

These channel methods require `callId` and the captured outgoing `requestId`:

- `reportOutgoingCallScreenVisible`: reports completed screen navigation.
- `allowOutgoingRingback`: grants host permission without waiting for playback.
- `reportOutgoingCallScreenHidden`: clears pending visibility without pausing
  sound that has already started.

Readiness is kept in memory. Connection, cleanup, and engine teardown invalidate
pending playback. Process restoration does not restart sound. Native event
metadata carries `playRingback`, `ringbackStartMode`, and `maxRingbackSeconds`
so automatically created outgoing sessions receive the correct settings.

## Background decline handling

Native code waits for the headless Flutter decline callback before completing
the incoming-call flow:

- `reported` closes the call without missed-call UI.
- `failed`, an exception, or timeout falls back to missed-call handling.

On iOS, register plugins needed by headless callbacks with
`CallwaveFlutterPlugin.setBackgroundFlutterPluginRegistrant(...)`.
Foreground missed-call notifications use an alert on iOS 13 and banner plus
Notification Center on iOS 14+.

## Native readiness tests

From this package's `ios` directory on macOS with Xcode tools:

```sh
src=callwave_flutter_method_channel/Sources/callwave_flutter_method_channel
xcrun swiftc -module-cache-path /tmp/callwave-swift-module-cache \
  "$src/manager/OutgoingRingbackReadiness.swift" \
  "$src/model/CallPayload.swift" "$src/JSONValueSanitizer.swift" \
  tests/OutgoingRingbackReadinessTests.swift -o /tmp/callwave-ringback-tests
/tmp/callwave-ringback-tests
```
