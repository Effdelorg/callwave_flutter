import 'package:callwave_flutter_platform_interface/callwave_flutter_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PostCallBehavior', () {
    test('fromWireValue returns stayOpen for null or unknown values', () {
      expect(PostCallBehavior.fromWireValue(null), PostCallBehavior.stayOpen);
      expect(
        PostCallBehavior.fromWireValue('not-a-valid-mode'),
        PostCallBehavior.stayOpen,
      );
    });
  });

  group('PayloadCodec', () {
    test('serializes and deserializes CallDataDto', () {
      const data = CallDataDto(
        callId: 'abc',
        callerName: 'Ava',
        handle: '+1',
        avatarUrl: 'https://x.test/a.png',
        timeoutSeconds: 45,
        callType: CallType.video,
        extra: <String, dynamic>{'room': 'blue'},
      );

      final map = PayloadCodec.callDataToMap(data);
      final decoded = PayloadCodec.callDataFromMap(map);

      expect(decoded.callId, data.callId);
      expect(decoded.callerName, data.callerName);
      expect(decoded.handle, data.handle);
      expect(decoded.avatarUrl, data.avatarUrl);
      expect(decoded.timeoutSeconds, data.timeoutSeconds);
      expect(decoded.callType, data.callType);
      expect(decoded.extra, data.extra);
    });

    test('safeCallEventFromMap returns null for invalid payload', () {
      final event = PayloadCodec.safeCallEventFromMap(<String, dynamic>{
        'callId': 'abc',
        'type': 'unknown',
        'timestampMs': 123,
      });

      expect(event, isNull);
    });

    test('safeCallEventFromMap decodes valid payload', () {
      final event = PayloadCodec.safeCallEventFromMap(<String, dynamic>{
        'callId': 'abc',
        'type': 'accepted',
        'timestampMs': 123,
        'extra': <String, dynamic>{'source': 'push'},
      });

      expect(event, isNotNull);
      expect(event!.callId, 'abc');
      expect(event.type, CallEventType.accepted);
      expect(event.timestampMs, 123);
      expect(event.extra?['source'], 'push');
    });
  });
}
