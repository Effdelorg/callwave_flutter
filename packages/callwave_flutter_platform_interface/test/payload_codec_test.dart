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
        backgroundDispatcherHandle: 101,
        backgroundCallbackHandle: 202,
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
      expect(
        decoded.incomingAcceptStrategy,
        IncomingAcceptStrategy.openImmediately,
      );
      expect(decoded.backgroundDispatcherHandle, 101);
      expect(decoded.backgroundCallbackHandle, 202);
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

    test('startup action roundtrips through payload codec', () {
      const action = CallStartupActionDto(
        type: CallStartupActionType.callback,
        callId: 'missed-1',
        callerName: 'Ava',
        handle: '+1 555 0101',
        avatarUrl: 'https://x.test/a.png',
        callType: CallType.video,
        extra: <String, dynamic>{'roomType': 'conference'},
      );

      final map = PayloadCodec.startupActionToMap(action);
      final decoded = PayloadCodec.safeStartupActionFromMap(map);

      expect(decoded, isNotNull);
      expect(decoded!.type, CallStartupActionType.callback);
      expect(decoded.callId, action.callId);
      expect(decoded.callType, action.callType);
      expect(decoded.extra, action.extra);
    });
  });
}
