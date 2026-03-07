import 'package:callwave_flutter_method_channel/callwave_flutter_method_channel.dart';
import 'package:callwave_flutter_platform_interface/callwave_flutter_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registerWith sets platform instance', () {
    MethodChannelCallwaveFlutter.registerWith();
    expect(
        CallwaveFlutterPlatform.instance, isA<MethodChannelCallwaveFlutter>());
  });

  test('setPostCallBehavior sends method channel payload', () async {
    const channel = MethodChannel('callwave_flutter/methods');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final plugin = MethodChannelCallwaveFlutter();
    await plugin.setPostCallBehavior(PostCallBehavior.backgroundOnEnded);

    expect(calls.map((call) => call.method), <String>[
      'initialize',
      'setPostCallBehavior',
    ]);

    final args = calls.last.arguments as Map<dynamic, dynamic>;
    expect(args[PayloadCodec.keyPostCallBehavior], 'backgroundOnEnded');
  });

  test('confirmAcceptedCall sends method channel payload', () async {
    const channel = MethodChannel('callwave_flutter/methods');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final plugin = MethodChannelCallwaveFlutter();
    await plugin.confirmAcceptedCall('c-123');

    expect(calls.map((call) => call.method), <String>[
      'initialize',
      'confirmAcceptedCall',
    ]);

    final args = calls.last.arguments as Map<dynamic, dynamic>;
    expect(args[PayloadCodec.keyCallId], 'c-123');
  });

  test('registerBackgroundIncomingCallValidator sends callback handles',
      () async {
    const channel = MethodChannel('callwave_flutter/methods');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final plugin = MethodChannelCallwaveFlutter();
    await plugin.registerBackgroundIncomingCallValidator(
      backgroundDispatcherHandle: 101,
      backgroundCallbackHandle: 202,
    );

    expect(calls.map((call) => call.method), <String>[
      'initialize',
      'registerBackgroundIncomingCallValidator',
    ]);

    final args = calls.last.arguments as Map<dynamic, dynamic>;
    expect(args[PayloadCodec.keyBackgroundDispatcherHandle], 101);
    expect(args[PayloadCodec.keyBackgroundCallbackHandle], 202);
  });

  test('markMissed sends optional extra metadata', () async {
    const channel = MethodChannel('callwave_flutter/methods');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final plugin = MethodChannelCallwaveFlutter();
    await plugin.markMissed(
      'c-456',
      extra: const <String, dynamic>{'outcomeReason': 'cancelled'},
    );

    expect(calls.map((call) => call.method), <String>[
      'initialize',
      'markMissed',
    ]);

    final args = calls.last.arguments as Map<dynamic, dynamic>;
    expect(args[PayloadCodec.keyCallId], 'c-456');
    expect(
      args[PayloadCodec.keyExtra],
      const <String, dynamic>{'outcomeReason': 'cancelled'},
    );
  });

  test('takePendingStartupAction decodes startup action payload', () async {
    const channel = MethodChannel('callwave_flutter/methods');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'takePendingStartupAction') {
        return <String, dynamic>{
          PayloadCodec.keyStartupActionType: 'callback',
          PayloadCodec.keyCallId: 'missed-1',
          PayloadCodec.keyCallerName: 'Ava',
          PayloadCodec.keyHandle: '+1 555 0101',
          PayloadCodec.keyCallType: 'video',
          PayloadCodec.keyExtra: <String, dynamic>{'roomType': 'conference'},
        };
      }
      return null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final plugin = MethodChannelCallwaveFlutter();
    final action = await plugin.takePendingStartupAction();

    expect(action, isNotNull);
    expect(action!.type, CallStartupActionType.callback);
    expect(action.callId, 'missed-1');
    expect(action.callType, CallType.video);
    expect(action.extra, <String, dynamic>{'roomType': 'conference'});
  });
}
