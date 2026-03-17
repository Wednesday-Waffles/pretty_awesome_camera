import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'src/camera_description.dart';
import 'src/recording_state.dart';
import 'src/resolution_preset.dart';
import 'src/switching_path.dart';
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

  /// Checks if the camera with the given ID can be switched during recording.
  ///
  /// Returns true if the camera supports switching, false otherwise.
  /// Throws [CameraException] if the camera is not initialized.
  Future<bool> canSwitchCamera(int cameraId) {
    throw UnimplementedError('canSwitchCamera() has not been implemented.');
  }

  /// Switches to the camera with the given ID during recording.
  ///
  /// This method allows switching to a different camera without stopping the recording.
  /// Throws [CameraException] with code 'invalidState' if not currently recording.
  /// Throws [CameraException] with code 'switchInProgress' if a switch is already in progress.
  Future<void> switchCamera(int cameraId) {
    throw UnimplementedError('switchCamera() has not been implemented.');
  }

  /// Convenience getter to check if the current camera can be switched.
  ///
  /// This is a helper method that checks if camera switching is currently possible.
  /// Returns true if a camera switch can be initiated, false otherwise.
  /// Throws [CameraException] if no camera is currently active.
  Future<bool> get canSwitchCurrentCamera {
    throw UnimplementedError(
      'canSwitchCurrentCamera() has not been implemented.',
    );
  }

  /// Detects if the device supports the optimized camera switching path.
  ///
  /// On iOS, this checks if AVCaptureMultiCamSession.isMultiCamSupported is true.
  /// On Android, this returns false as v4.1 uses fallback path only.
  ///
  /// Returns true if optimized path is supported, false otherwise.
  /// Throws [CameraException] if capability detection fails.
  Future<bool> isMultiCamSupported() {
    throw UnimplementedError('isMultiCamSupported() has not been implemented.');
  }

  /// Gets the detected camera switching path for this device.
  ///
  /// This determines which implementation strategy is used: optimized path
  /// for supported devices or fallback segment-merge path for others.
  ///
  /// Returns the detected [SwitchingPath] as a string for platform communication.
  /// Throws [CameraException] if path detection fails.
  Future<String> getSwitchingPath() {
    throw UnimplementedError('getSwitchingPath() has not been implemented.');
  }
}
