// You have generated a new plugin project without specifying the `--platforms`
// flag. A plugin project with no platform support was generated. To add a
// platform, run `flutter create -t plugin --platforms <platforms> .` under the
// same directory. You can also find a detailed instruction on how to add
// platforms in the `pubspec.yaml` at
// https://flutter.dev/to/pubspec-plugin-platforms.

import 'waffle_camera_plugin_platform_interface.dart';

// Type definitions and exceptions
export 'src/camera_exception.dart';
export 'src/camera_description.dart';
export 'src/resolution_preset.dart';
export 'src/recording_state.dart';

// Widgets
export 'camera_preview.dart';

class WaffleCameraPlugin {
  Future<String?> getPlatformVersion() {
    return WaffleCameraPluginPlatform.instance.getPlatformVersion();
  }
}
