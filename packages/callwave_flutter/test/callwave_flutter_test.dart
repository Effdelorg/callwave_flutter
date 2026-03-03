import 'dart:async';

import 'package:callwave_flutter/callwave_flutter.dart';
import 'package:callwave_flutter_platform_interface/callwave_flutter_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakePlatform fakePlatform;

  setUp(() {
    fakePlatform = _FakePlatform();
    platform.CallwaveFlutterPlatform.instance = fakePlatform;
  });

  test('showIncomingCall delegates to platform interface', () async {
    await CallwaveFlutter.instance.showIncomingCall(
      const CallData(callId: 'c1', callerName: 'Ava', handle: '+1'),
    );

    expect(fakePlatform.lastIncomingCallId, 'c1');
  });

  test('events are mapped to public model', () async {
    final completer = Completer<CallEvent>();
    final sub = CallwaveFlutter.instance.events.listen(completer.complete);

    fakePlatform.emit(
      const platform.CallEventDto(
        callId: 'c1',
        type: platform.CallEventType.accepted,
        timestampMs: 5000,
      ),
    );

    final event = await completer.future;
    await sub.cancel();

    expect(event.callId, 'c1');
    expect(event.type, CallEventType.accepted);
    expect(event.timestamp, DateTime.fromMillisecondsSinceEpoch(5000));
  });

  test('setPostCallBehavior delegates to platform interface', () async {
    await CallwaveFlutter.instance.setPostCallBehavior(
      PostCallBehavior.backgroundOnEnded,
    );

    expect(
      fakePlatform.postCallBehavior,
      platform.PostCallBehavior.backgroundOnEnded,
    );
  });
}

class _FakePlatform extends platform.CallwaveFlutterPlatform {
  final StreamController<platform.CallEventDto> _controller =
      StreamController<platform.CallEventDto>.broadcast();

  String? lastIncomingCallId;
  platform.PostCallBehavior postCallBehavior =
      platform.PostCallBehavior.stayOpen;

  @override
  Stream<platform.CallEventDto> get events => _controller.stream;

  void emit(platform.CallEventDto event) {
    _controller.add(event);
  }

  @override
  Future<void> endCall(String callId) async {}

  @override
  Future<List<String>> getActiveCallIds() async => const <String>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> markMissed(String callId) async {}

  @override
  Future<void> requestFullScreenIntentPermission() async {}

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<void> setPostCallBehavior(platform.PostCallBehavior behavior) async {
    postCallBehavior = behavior;
  }

  @override
  Future<void> showIncomingCall(platform.CallDataDto data) async {
    lastIncomingCallId = data.callId;
  }

  @override
  Future<void> showOutgoingCall(platform.CallDataDto data) async {}
}
