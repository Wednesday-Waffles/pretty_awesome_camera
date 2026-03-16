import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'waffle_camera_plugin_platform_interface.dart';

/// An implementation of [WaffleCameraPluginPlatform] that uses method channels.
class MethodChannelWaffleCameraPlugin extends WaffleCameraPluginPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('waffle_camera_plugin');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
