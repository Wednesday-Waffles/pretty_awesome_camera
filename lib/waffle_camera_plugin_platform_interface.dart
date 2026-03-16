import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'waffle_camera_plugin_method_channel.dart';

abstract class WaffleCameraPluginPlatform extends PlatformInterface {
  /// Constructs a WaffleCameraPluginPlatform.
  WaffleCameraPluginPlatform() : super(token: _token);

  static final Object _token = Object();

  static WaffleCameraPluginPlatform _instance = MethodChannelWaffleCameraPlugin();

  /// The default instance of [WaffleCameraPluginPlatform] to use.
  ///
  /// Defaults to [MethodChannelWaffleCameraPlugin].
  static WaffleCameraPluginPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [WaffleCameraPluginPlatform] when
  /// they register themselves.
  static set instance(WaffleCameraPluginPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
