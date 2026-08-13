import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../models/audio_device_changed_event.dart';
import '../models/audio_level_event.dart';
import '../models/camera_config.dart';
import '../models/camera_description.dart';
import '../models/camera_initialization_result.dart';
import '../models/recorded_segment.dart';
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
  ///
  /// Resolves once the native recorder has confirmed engagement (on Android
  /// the result is held until CameraX emits `VideoRecordEvent.Start`).
  /// Returns a start-info map describing the audio route the recording began
  /// on — keys include `audioPortType`, `audioDeviceName`,
  /// `isBluetoothInput`, and on Android additionally `isBluetoothAvailable`,
  /// `btRouteResult`, and `engagementElapsedMs`. May be null on older native
  /// builds that predate start-info.
  ///
  /// [salvagePolicy] tells native whether it may seal the in-flight segment by
  /// itself on interruption or backgrounding. It is decided once per take by
  /// the caller and defaults to [SalvagePolicy.off], so upgrading the plugin
  /// cannot change recording behavior until a caller opts in.
  Future<Map<String, Object?>?> startRecording(
    int cameraId, {
    SalvagePolicy salvagePolicy = SalvagePolicy.off,
  }) {
    throw UnimplementedError('startRecording() has not been implemented.');
  }

  /// Starts a new segment inside an existing session, appending to segments
  /// already sealed.
  ///
  /// This is not [startRecording] minus its guard. After an interruption the
  /// audio session is deactivated and the capture session may be stopped, so
  /// implementations repair both before creating a writer — otherwise the new
  /// segment is silent or empty while appearing to work.
  ///
  /// Failing here leaves the already-sealed segments untouched.
  Future<Map<String, Object?>?> startRecordingSegment(
    int cameraId, {
    SalvagePolicy salvagePolicy = SalvagePolicy.off,
  }) {
    throw UnimplementedError(
      'startRecordingSegment() has not been implemented.',
    );
  }

  /// Finalizes the in-flight segment and leaves the camera session running.
  ///
  /// Sealing an absent or already-sealed writer is not an error: the returned
  /// outcome simply reports `ok: false` with no segment.
  Future<SegmentSealOutcome> sealRecordingSegment(
    int cameraId, {
    required String reason,
  }) {
    throw UnimplementedError(
      'sealRecordingSegment() has not been implemented.',
    );
  }

  /// Atomically drains and clears the native stash of seal outcomes.
  ///
  /// One entry per seal *attempt*, in order. A duplicate notification
  /// therefore drains an empty list rather than yielding a duplicate segment.
  Future<List<SegmentSealOutcome>> consumeSealedSegments(int cameraId) {
    throw UnimplementedError(
      'consumeSealedSegments() has not been implemented.',
    );
  }

  /// Drains the writer-failure diagnostic stash, or null when the writer has
  /// not failed since the last drain.
  Future<WriterFailureReport?> consumeWriterFailure(int cameraId) {
    throw UnimplementedError(
      'consumeWriterFailure() has not been implemented.',
    );
  }

  /// Concatenates [segmentPaths] in order into [outputPath].
  ///
  /// Throws a [CameraException] with code `CONCAT_ERROR` on failure. Callers
  /// must verify the reported duration against the sum of the input durations
  /// before trusting the output — "succeeded" is not "playable".
  Future<SegmentConcatResult> concatenateSegments({
    required List<String> segmentPaths,
    required String outputPath,
  }) {
    throw UnimplementedError('concatenateSegments() has not been implemented.');
  }

  /// Reports what the underlying native build can do.
  ///
  /// Builds that predate salvage surface a [CameraException] with code
  /// `NOT_IMPLEMENTED`; implementations map that to
  /// [RecordingCapabilities.none] rather than throwing, so a stale native side
  /// degrades to "no salvage" instead of breaking the recorder.
  Future<RecordingCapabilities> getRecordingCapabilities() {
    throw UnimplementedError(
      'getRecordingCapabilities() has not been implemented.',
    );
  }

  /// Returns the requested bitrate and resolved native recording configuration
  /// for the camera with the given ID.
  ///
  /// Best-effort snapshot: `resolved_resolution` may be null while the native
  /// pipeline is (re)binding — e.g. during a camera switch — and during a
  /// switch the values may reflect the previous camera until it completes.
  Future<Map<String, Object?>> getRecordingSettings(int cameraId) {
    throw UnimplementedError(
      'getRecordingSettings() has not been implemented.',
    );
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

  /// Returns a throttled stream of audio-level samples for the camera with
  /// the given ID.
  ///
  /// iOS emits at ~4 Hz whenever the capture session runs; Android emits at
  /// ~1 Hz only while a recording is active. See [AudioLevelEvent] for the
  /// staleness caveat consumers must handle.
  Stream<AudioLevelEvent> onAudioLevel(int cameraId) {
    throw UnimplementedError('onAudioLevel() has not been implemented.');
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
