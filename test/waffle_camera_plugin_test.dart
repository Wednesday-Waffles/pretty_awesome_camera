import 'package:flutter_test/flutter_test.dart';
import 'package:waffle_camera_plugin/waffle_camera_plugin.dart';
import 'package:waffle_camera_plugin/waffle_camera_plugin_platform_interface.dart';
import 'package:waffle_camera_plugin/waffle_camera_plugin_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockWaffleCameraPluginPlatform
    with MockPlatformInterfaceMixin
    implements WaffleCameraPluginPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final WaffleCameraPluginPlatform initialPlatform = WaffleCameraPluginPlatform.instance;

  test('$MethodChannelWaffleCameraPlugin is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelWaffleCameraPlugin>());
  });

  test('getPlatformVersion', () async {
    WaffleCameraPlugin waffleCameraPlugin = WaffleCameraPlugin();
    MockWaffleCameraPluginPlatform fakePlatform = MockWaffleCameraPluginPlatform();
    WaffleCameraPluginPlatform.instance = fakePlatform;

    expect(await waffleCameraPlugin.getPlatformVersion(), '42');
  });
}
