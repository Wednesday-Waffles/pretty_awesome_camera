import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../models/audio_device_changed_event.dart';
import '../models/camera_config.dart';
import '../models/camera_description.dart';
import '../models/camera_initialization_result.dart';
import '../models/recording_state.dart';
import '../models/switching_path.dart';
import 'pretty_awesome_camera_method_channel.dart';

abstract class PrettyAwesomeCameraPlatform extends PlatformInterface {
  /// Constructs a PrettyAwesomeCameraPlatform.
  PrettyAwesomeCameraPlatform() : super(token: _token);

  static final Object _token = Object();

  static PrettyAwesomeCameraPlatform _instance =
      MethodChannelPrettyAwesomeCamera();

  /// The default instance of [PrettyAwesomeCameraPlatform] to use.
  ///
  /// Defaults to [MethodChannelPrettyAwesomeCamera].
  static PrettyAwesomeCameraPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [PrettyAwesomeCameraPlatform] when
  /// they register themselves.
  static set instance(PrettyAwesomeCameraPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  /// Returns build provenance for the underlying native implementation, such
  /// as the plugin git SHA, bundled camera framework version, and capability
  /// flags.
  ///
  /// Only implemented on Android. Builds without this method surface a
  /// [CameraException] mapped from the missing plugin handler, which callers
  /// can treat as "provenance unavailable".
  Future<Map<String, Object?>> getBuildInfo() {
    throw UnimplementedError('getBuildInfo() has not been implemented.');
  }

  /// Retrieves a list of available cameras on the device.
  Future<List<CameraDescription>> getAvailableCameras() {
    throw UnimplementedError('getAvailableCameras() has not been implemented.');
  }

  /// Creates a camera instance with the given description and resolution preset.
  ///
  /// Returns the camera ID for use in subsequent operations.
  Future<int> createCamera(CameraDescription camera, CameraConfig config) {
    throw UnimplementedError('createCamera() has not been implemented.');
  }

  /// Initializes the camera with the given ID.
  ///
  /// Returns the texture ID and preview dimensions for rendering the camera preview.
  Future<CameraInitializationResult> initializeCamera(int cameraId) {
    throw UnimplementedError('initializeCamera() has not been implemented.');
  }

  /// Starts recording video from the camera with the given ID.
  Future<void> startRecording(int cameraId) {
    throw UnimplementedError('startRecording() has not been implemented.');
  }

  /// Stops recording and returns the file path of the saved video,
  /// or null if recording was stopped before any frames were captured.
  Future<String?> stopRecording(int cameraId) {
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

  /// Sets the video zoom factor for the camera with the given ID.
  ///
  /// Platform implementations clamp the requested factor to the active
  /// camera device's supported zoom range.
  Future<double> setZoom(int cameraId, double zoomFactor) {
    throw UnimplementedError('setZoom() has not been implemented.');
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

  /// Returns a stream of audio device route changes for the camera with the given ID.
  Stream<AudioDeviceChangedEvent> onAudioDeviceChanged(int cameraId) {
    throw UnimplementedError(
      'onAudioDeviceChanged() has not been implemented.',
    );
  }

  /// Checks if the camera with the given ID can be switched MID-RECORDING.
  ///
  /// This intentionally reports the in-flight recording switch capability
  /// only — it returns false whenever no recording is active (both
  /// platforms), and on Android also once the active recording has pause
  /// history. It does NOT answer "may [switchCamera] be called": preview
  /// (not-recording) switches are always supported on both platforms even
  /// while this returns false. Gate preview flip UI on camera availability,
  /// not on this method.
  ///
  /// Throws [CameraException] if the camera is not initialized.
  Future<bool> canSwitchCamera(int cameraId) {
    throw UnimplementedError('canSwitchCamera() has not been implemented.');
  }

  /// Switches to the opposite camera (front ↔ back).
  ///
  /// Supported while previewing (not recording) and while actively
  /// recording. Returns the new texture ID and preview dimensions after
  /// switching.
  /// Throws [CameraException] with code 'switchInProgress' if a switch is already in progress.
  /// Throws [CameraException] with code 'PAUSED_FLIP_UNSUPPORTED' on Android
  /// while the recording is paused, and 'PAUSE_HISTORY_FLIP_UNSUPPORTED'
  /// once the active recording has been paused at least once.
  Future<CameraInitializationResult> switchCamera(int cameraId) {
    throw UnimplementedError('switchCamera() has not been implemented.');
  }

  /// Convenience getter to check if any current camera can be switched
  /// MID-RECORDING. Same semantics as [canSwitchCamera] — see its note about
  /// preview switches.
  ///
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
