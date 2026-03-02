import 'package:callwave_flutter_method_channel/callwave_flutter_method_channel.dart';
import 'package:callwave_flutter_platform_interface/callwave_flutter_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registerWith sets platform instance', () {
    MethodChannelCallwaveFlutter.registerWith();
    expect(CallwaveFlutterPlatform.instance, isA<MethodChannelCallwaveFlutter>());
  });
}
