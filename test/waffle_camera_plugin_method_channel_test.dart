import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waffle_camera_plugin/waffle_camera_plugin_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelWaffleCameraPlugin platform = MethodChannelWaffleCameraPlugin();
  const MethodChannel channel = MethodChannel('waffle_camera_plugin');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          return '42';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });
}
