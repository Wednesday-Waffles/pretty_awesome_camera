import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'src/camera_description.dart';
import 'src/recording_state.dart';
import 'src/resolution_preset.dart';
import 'waffle_camera_plugin_method_channel.dart';

abstract class WaffleCameraPluginPlatform extends PlatformInterface {
  /// Constructs a WaffleCameraPluginPlatform.
  WaffleCameraPluginPlatform() : super(token: _token);

  static final Object _token = Object();

  static WaffleCameraPluginPlatform _instance =
      MethodChannelWaffleCameraPlugin();

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

  /// Retrieves a list of available cameras on the device.
  Future<List<CameraDescription>> getAvailableCameras() {
    throw UnimplementedError('getAvailableCameras() has not been implemented.');
  }

  /// Creates a camera instance with the given description and resolution preset.
  ///
  /// Returns the camera ID for use in subsequent operations.
  Future<int> createCamera(CameraDescription camera, ResolutionPreset preset) {
    throw UnimplementedError('createCamera() has not been implemented.');
  }

  /// Initializes the camera with the given ID.
  Future<void> initializeCamera(int cameraId) {
    throw UnimplementedError('initializeCamera() has not been implemented.');
  }

  /// Starts recording video from the camera with the given ID.
  Future<void> startRecording(int cameraId) {
    throw UnimplementedError('startRecording() has not been implemented.');
  }

  /// Stops recording and returns the file path of the saved video.
  Future<String> stopRecording(int cameraId) {
    throw UnimplementedError('stopRecording() has not been implemented.');
  }

  /// Pauses recording on the camera with the given ID.
  Future<void> pauseRecording(int cameraId) {
    throw UnimplementedError('pauseRecording() has not been implemented.');
  }

  /// Resumes recording on the camera with the given ID.
  Future<void> resumeRecording(int cameraId) {
    throw UnimplementedError('resumeRecording() has not been implemented.');
  }

  /// Disposes the camera with the given ID, freeing resources.
  Future<void> disposeCamera(int cameraId) {
    throw UnimplementedError('disposeCamera() has not been implemented.');
  }

  /// Returns a stream of recording state changes for the camera with the given ID.
  Stream<RecordingState> onRecordingStateChanged(int cameraId) {
    throw UnimplementedError(
      'onRecordingStateChanged() has not been implemented.',
    );
  }
}
