# callwave_flutter_platform_interface

Shared contracts, DTOs, enums, and payload codecs for
[callwave_flutter](https://pub.dev/packages/callwave_flutter) platform implementations.
App developers should depend on the public package.

## Version and requirements

Version `0.4.0` is used by `callwave_flutter: ^0.7.0` and
`callwave_flutter_method_channel: ^0.4.0`.
Requires Dart `^3.11.0` and Flutter `>=3.41.0`.

## Outgoing ringback contract

`CallDataDto` includes these settings:

| Field | Default | Meaning |
| --- | --- | --- |
| `playRingback` | `true` | Enables the plugin's outgoing tone |
| `ringbackStartMode` | `RingbackStartMode.automatic` | Selects automatic or host-controlled startup |
| `maxRingbackSeconds` | `120` | Caps playback without ending the call |

`copyWith` and `PayloadCodec` preserve the mode. Wire values are `automatic` and
`appControlled`; missing or unknown values use `automatic`.

The bundled implementation applies these startup rules:

| Mode | Android | iOS |
| --- | --- | --- |
| `automatic` | Screen readiness | CallKit audio activation |
| `appControlled` | Screen readiness and host permission | Screen readiness, host permission, and CallKit audio activation |

`playRingback: false` disables either mode. Audio routing belongs to the host.

## Readiness methods

Each method takes a call ID and the request ID captured from that attempt's
`started` event:

- `reportOutgoingCallScreenVisible(callId, requestId: ...)` reports screen readiness.
- `allowOutgoingRingback(callId, requestId: ...)` grants host permission without
  waiting for playback.
- `reportOutgoingCallScreenHidden(callId, requestId: ...)` clears pending visibility;
  it does not pause sound that has already started.

These methods have default no-op implementations, so existing custom platforms
remain source-compatible. Custom implementations must override them to support
the readiness flow. Keep request IDs specific to each attempt and invalidate
pending playback on connection, cleanup, or engine teardown. Do not recreate
playback permission during process restoration.
