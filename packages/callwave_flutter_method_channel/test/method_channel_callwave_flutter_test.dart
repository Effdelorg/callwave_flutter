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
}
