# callwave_flutter

Public Flutter API for Callwave VoIP call UX.

This package exposes clean Dart models and methods.
It does not expose MethodChannel objects directly.

## Usage

```dart
await CallwaveFlutter.instance.showIncomingCall(
  const CallData(
    callId: 'c-42',
    callerName: 'Alex',
    handle: '+1 555 0100',
  ),
);
```

Listen to events:

```dart
CallwaveFlutter.instance.events.listen((event) {
  if (event.type == CallEventType.accepted) {
    // open call screen
  }
});
```
