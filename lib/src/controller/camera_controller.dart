import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/audio_device_changed_event.dart';
import '../models/audio_level_event.dart';
import '../models/camera_config.dart';
import '../models/camera_description.dart';
import '../models/camera_exception.dart';
import '../models/camera_preview_size.dart';
import '../models/camera_state.dart';
import '../models/recorded_segment.dart';
import '../models/recording_state.dart';
import '../platform/pretty_awesome_camera_platform_interface.dart';
import 'camera_snapshot.dart';

/// High-level controller that owns camera lifecycle and recording transitions.
class CameraController extends ValueNotifier<CameraState> {
  static PrettyAwesomeCameraPlatform? _cachedCameraPlatform;
  static List<CameraDescription>? _cachedAvailableCameras;

  final PrettyAwesomeCameraPlatform _platform;
  final LensDirection _preferredLens;
  List<CameraDescription> _availableCameras;
  CameraSnapshot _cameraSnapshot;

  StreamSubscription<RecordingState>? _recordingStateSubscription;
  bool _isControllerDisposed = false;
  Future<void>? _initializationFuture;
  Future<String?>? _stopRecordingFuture;
  Future<SegmentSealOutcome>? _sealSegmentFuture;
  Future<void>? _switchCameraFuture;

  /// Segments sealed so far in the current session.
  ///
  /// Reset by a fresh start (including Start Over) and by a completed stop,
  /// but deliberately **not** by [startRecordingSegment] — continuing a
  /// session appends to what was salvaged rather than replacing it.
  ///
  /// This is also what lets writer-failure handling pick the right recovery
  /// state without a payload: the failure notification carries no data, so the
  /// controller has to know locally whether anything survives.
  int _sealedSegmentCount = 0;

  /// How many segments have been sealed in the current session.
  int get sealedSegmentCount => _sealedSegmentCount;
  StreamSubscription<AudioDeviceChangedEvent>? _audioDeviceSubscription;
  final StreamController<AudioDeviceChangedEvent>
  _audioDeviceChangedController =
      StreamController<AudioDeviceChangedEvent>.broadcast();

  /// Stream of audio input device change events.
  Stream<AudioDeviceChangedEvent> get onAudioDeviceChanged =>
      _audioDeviceChangedController.stream;

  StreamSubscription<AudioLevelEvent>? _audioLevelSubscription;
  int? _audioLevelCameraId;
  late final StreamController<AudioLevelEvent> _audioLevelController =
      StreamController<AudioLevelEvent>.broadcast(
        onListen: _connectAudioLevelStream,
        onCancel: _disconnectAudioLevelStream,
      );

  /// Throttled stream of audio-level samples. See [AudioLevelEvent] for
  /// per-platform cadence/coverage and the staleness caveat.
  ///
  /// The native EventChannel is only attached while this stream has
  /// listeners — with none, the platforms skip metering work entirely, which
  /// is what makes the app-side stream flag a true operational kill switch.
  Stream<AudioLevelEvent> get onAudioLevel => _audioLevelController.stream;

  Map<String, Object?>? _lastRecordingStartInfo;

  /// Audio-route info reported by the platform when the most recent
  /// recording started (null before the first recording, or when the native
  /// build predates start-info).
  Map<String, Object?>? get lastRecordingStartInfo => _lastRecordingStartInfo;

  CameraController({
    CameraDescription? description,
    LensDirection preferredLens = LensDirection.front,
    CameraConfig config = const CameraConfig(),
    List<CameraDescription> availableCameras = const [],
    PrettyAwesomeCameraPlatform? platform,
  }) : _platform = platform ?? PrettyAwesomeCameraPlatform.instance,
       _preferredLens = preferredLens,
       _availableCameras = List<CameraDescription>.unmodifiable(
         availableCameras,
       ),
       _cameraSnapshot = CameraSnapshot(
         state: CameraUninitializedState(
           config: config,
           description: description,
           hasMultipleCameras: availableCameras.length > 1,
         ),
       ),
       super(
         CameraUninitializedState(
           config: config,
           description: description,
           hasMultipleCameras: availableCameras.length > 1,
         ),
       );

  static Future<CameraController> create({
    LensDirection? preferredLens,
    CameraConfig config = const CameraConfig(),
    PrettyAwesomeCameraPlatform? platform,
  }) async {
    final resolvedPlatform = platform ?? PrettyAwesomeCameraPlatform.instance;
    final resolvedPreferredLens = preferredLens ?? config.lensDirection;
    final availableCameras = await preloadAvailableCameras(
      platform: resolvedPlatform,
    );
    final description = selectPreferredCamera(
      availableCameras,
      preferredLens: resolvedPreferredLens ?? LensDirection.front,
    );
    return CameraController(
      description: description,
      preferredLens: resolvedPreferredLens ?? LensDirection.front,
      config: config,
      availableCameras: availableCameras,
      platform: resolvedPlatform,
    );
  }

  static Future<List<CameraDescription>> preloadAvailableCameras({
    PrettyAwesomeCameraPlatform? platform,
    bool forceRefresh = false,
  }) async {
    final resolvedPlatform = platform ?? PrettyAwesomeCameraPlatform.instance;

    if (!forceRefresh &&
        identical(_cachedCameraPlatform, resolvedPlatform) &&
        _cachedAvailableCameras != null) {
      return List<CameraDescription>.unmodifiable(_cachedAvailableCameras!);
    }

    final availableCameras = List<CameraDescription>.unmodifiable(
      await resolvedPlatform.getAvailableCameras(),
    );
    _cachedCameraPlatform = resolvedPlatform;
    _cachedAvailableCameras = availableCameras;
    return List<CameraDescription>.unmodifiable(availableCameras);
  }

  static List<CameraDescription>? getCachedAvailableCameras({
    PrettyAwesomeCameraPlatform? platform,
  }) {
    final resolvedPlatform = platform ?? PrettyAwesomeCameraPlatform.instance;
    if (!identical(_cachedCameraPlatform, resolvedPlatform)) {
      return null;
    }
    final availableCameras = _cachedAvailableCameras;
    if (availableCameras == null) {
      return null;
    }
    return List<CameraDescription>.unmodifiable(availableCameras);
  }

  static void clearAvailableCamerasCache({
    PrettyAwesomeCameraPlatform? platform,
  }) {
    final resolvedPlatform = platform ?? PrettyAwesomeCameraPlatform.instance;
    if (identical(_cachedCameraPlatform, resolvedPlatform)) {
      _cachedCameraPlatform = null;
      _cachedAvailableCameras = null;
    }
  }

  static CameraDescription selectPreferredCamera(
    List<CameraDescription> availableCameras, {
    LensDirection? preferredLens,
  }) {
    if (availableCameras.isEmpty) {
      throw CameraException(
        code: 'no_cameras_available',
        message: 'No cameras are available on this device.',
      );
    }

    return availableCameras.firstWhere(
      (camera) => camera.lensDirection == preferredLens,
      orElse: () => availableCameras.first,
    );
  }

  CameraDescription get description => _cameraSnapshot.description!;

  CameraConfig get config => _cameraSnapshot.config;

  int? get cameraId => _cameraSnapshot.cameraId;

  int? get textureId => _cameraSnapshot.textureId;

  CameraPreviewSize? get previewSize => _cameraSnapshot.previewSize;

  double? get previewAspectRatio => previewSize?.portraitAspectRatio;

  List<CameraDescription> get availableCameras =>
      List<CameraDescription>.unmodifiable(_availableCameras);

  bool get hasMultipleCameras => _availableCameras.length > 1;

  Future<bool> isMultiCamSupported() {
    _assertNotDisposed('isMultiCamSupported');
    return _platform.isMultiCamSupported();
  }

  Future<String> getSwitchingPath() {
    _assertNotDisposed('getSwitchingPath');
    return _platform.getSwitchingPath();
  }

  Future<void> prewarmUp() {
    _assertNotDisposed('initialize');
    if (_cameraSnapshot.isInitialized) {
      return Future.value();
    }
    final inFlight = _initializationFuture;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _initializeInternal();
    _initializationFuture = future;
    return future.whenComplete(() {
      if (identical(_initializationFuture, future)) {
        _initializationFuture = null;
      }
    });
  }

  /// Starts recording and returns the platform's start-info map (audio route
  /// stamp; null when unavailable). The result resolves only after the
  /// native recorder confirms engagement.
  Future<Map<String, Object?>?> startRecording({
    SalvagePolicy salvagePolicy = SalvagePolicy.off,
  }) async {
    _assertInitialized('startRecording');
    _assertState(
      allows: (state) =>
          state is CameraReadyState ||
          state is CameraVideoRecordedState ||
          // A native seal leaves the session alive but not recording. Both
          // restart choices — append and start-fresh — arrive here, so
          // rejecting this state would strand every salvaged take.
          state is CameraSegmentSealedState,
      method: 'startRecording',
    );

    // A fresh take supersedes anything salvaged; the caller owns those files
    // and is responsible for deleting them.
    _sealedSegmentCount = 0;
    return _startRecordingInternal(
      () => _platform.startRecording(cameraId!, salvagePolicy: salvagePolicy),
    );
  }

  /// Starts a new segment that appends to the segments already sealed in this
  /// session.
  ///
  /// Unlike [startRecording] this preserves [sealedSegmentCount], so a failure
  /// here leaves the salvaged segments — and therefore the other two choices —
  /// reachable.
  Future<Map<String, Object?>?> startRecordingSegment({
    SalvagePolicy salvagePolicy = SalvagePolicy.off,
  }) async {
    _assertInitialized('startRecordingSegment');
    _assertState(
      allows: (state) => state is CameraSegmentSealedState,
      method: 'startRecordingSegment',
    );

    return _startRecordingInternal(
      () => _platform.startRecordingSegment(
        cameraId!,
        salvagePolicy: salvagePolicy,
      ),
    );
  }

  Future<Map<String, Object?>?> _startRecordingInternal(
    Future<Map<String, Object?>?> Function() start,
  ) async {
    final previous = _cameraSnapshot;
    _setValueSafely(
      _cameraSnapshot.copyWith(state: _cameraStartingRecordingState()),
    );

    try {
      final startInfo = await start();
      _lastRecordingStartInfo = startInfo;
      _setValueSafely(_cameraSnapshot.copyWith(state: _cameraRecordingState()));
      return startInfo;
    } on CameraException catch (error) {
      // Restore the state we came from, error attached. When that was
      // `CameraSegmentSealedState` its segment count survives `copyWith`, so a
      // failed attempt leaves the remaining choices live rather than looking
      // like a session with nothing to salvage.
      _setValueSafely(
        previous.copyWith(state: _stateWithError(previous.state, error)),
      );
      rethrow;
    }
  }

  /// Finalizes the in-flight segment, leaving the camera session running.
  ///
  /// Concurrent calls share one in-flight future, mirroring [stopRecording]'s
  /// de-duplication: a seal triggered natively and a seal requested from Dart
  /// must not both finalize the same writer.
  Future<SegmentSealOutcome> sealRecordingSegment({
    required String reason,
  }) async {
    _assertInitialized('sealRecordingSegment');

    final inFlight = _sealSegmentFuture;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _sealRecordingSegmentInternal(reason: reason);
    _sealSegmentFuture = future;
    return future.whenComplete(() {
      if (identical(_sealSegmentFuture, future)) {
        _sealSegmentFuture = null;
      }
    });
  }

  Future<SegmentSealOutcome> _sealRecordingSegmentInternal({
    required String reason,
  }) async {
    final outcome = await _platform.sealRecordingSegment(
      cameraId!,
      reason: reason,
    );
    if (outcome.ok) {
      _applySegmentSealed();
    }
    return outcome;
  }

  /// Drains the native stash of seal outcomes. Draining is destructive.
  Future<List<SegmentSealOutcome>> consumeSealedSegments() {
    _assertInitialized('consumeSealedSegments');
    return _platform.consumeSealedSegments(cameraId!);
  }

  /// Drains the writer-failure diagnostic stash, or null when there is none.
  Future<WriterFailureReport?> consumeWriterFailure() {
    _assertInitialized('consumeWriterFailure');
    return _platform.consumeWriterFailure(cameraId!);
  }

  /// Concatenates [segmentPaths] in order into [outputPath].
  Future<SegmentConcatResult> concatenateSegments({
    required List<String> segmentPaths,
    required String outputPath,
  }) {
    _assertNotDisposed('concatenateSegments');
    return _platform.concatenateSegments(
      segmentPaths: segmentPaths,
      outputPath: outputPath,
    );
  }

  /// Reports what the underlying native build can do. Never throws for a
  /// native build that predates salvage — it reports
  /// [RecordingCapabilities.none].
  Future<RecordingCapabilities> getRecordingCapabilities() {
    _assertNotDisposed('getRecordingCapabilities');
    return _platform.getRecordingCapabilities();
  }

  Future<Map<String, Object?>> getRecordingSettings() {
    _assertNotDisposed('getRecordingSettings');
    _assertInitialized('getRecordingSettings');
    return _platform.getRecordingSettings(cameraId!);
  }

  Future<void> pauseRecording() async {
    _assertInitialized('pauseRecording');
    _assertState(
      allows: (state) => state is CameraRecordingState,
      method: 'pauseRecording',
    );

    final previous = _cameraSnapshot;
    try {
      await _platform.pauseRecording(cameraId!);
      _setValueSafely(_cameraSnapshot.copyWith(state: _cameraPausedState()));
    } on CameraException catch (error) {
      _setValueSafely(
        previous.copyWith(state: _stateWithError(previous.state, error)),
      );
      rethrow;
    }
  }

  Future<void> resumeRecording() async {
    _assertInitialized('resumeRecording');
    _assertState(
      allows: (state) => state is CameraPausedState,
      method: 'resumeRecording',
    );

    final previous = _cameraSnapshot;
    try {
      await _platform.resumeRecording(cameraId!);
      _setValueSafely(_cameraSnapshot.copyWith(state: _cameraRecordingState()));
    } on CameraException catch (error) {
      _setValueSafely(
        previous.copyWith(state: _stateWithError(previous.state, error)),
      );
      rethrow;
    }
  }

  Future<double> setZoom(double zoomFactor) {
    _assertNotDisposed('setZoom');
    _assertInitialized('setZoom');
    return _platform.setZoom(cameraId!, zoomFactor);
  }

  Future<void> switchCamera() async {
    _assertNotDisposed('switchCamera');

    final inFlight = _switchCameraFuture;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _switchCameraInternal();
    _switchCameraFuture = future;
    return future.whenComplete(() {
      if (identical(_switchCameraFuture, future)) {
        _switchCameraFuture = null;
      }
    });
  }

  Future<void> _switchCameraInternal() async {
    if (value is CameraSwitchingState) {
      return;
    }

    if (value is CameraStartingRecordingState ||
        value is CameraStoppingRecordingState) {
      throw CameraException(
        code: 'invalid_state',
        message: 'Cannot switch camera while starting or stopping recording.',
      );
    }

    final nextDescription = await _resolveNextCameraDescription();

    if (value is CameraRecordingState) {
      await _switchCameraDuringRecording(nextDescription);
      return;
    }

    if (value is CameraPausedState) {
      await _switchCameraDuringPaused(nextDescription);
      return;
    }

    if (value is CameraReadyState || value is CameraVideoRecordedState) {
      final previous = _cameraSnapshot;
      _setValueSafely(_cameraSnapshot.copyWith(state: _cameraSwitchingState()));

      try {
        final switchResult = await _platform.switchCamera(cameraId!);
        if (value is CameraSwitchingState) {
          _setValueSafely(
            _cameraSnapshot.copyWith(
              state: _cameraReadyState(description: nextDescription),
              textureId: switchResult.textureId,
              previewSize: switchResult.previewSize,
            ),
          );
        } else {
          _setValueSafely(
            _cameraSnapshot.copyWith(
              state: value.copyWith(description: nextDescription),
              textureId: switchResult.textureId,
              previewSize: switchResult.previewSize,
            ),
          );
        }
      } on CameraException catch (error) {
        if (value is CameraSwitchingState) {
          _setValueSafely(
            previous.copyWith(state: _stateWithError(previous.state, error)),
          );
        }
        rethrow;
      }
      return;
    }

    if (value is CameraUninitializedState) {
      _setValueSafely(
        _cameraSnapshot.copyWith(
          state: value.copyWith(description: nextDescription),
        ),
      );
      return;
    }

    await reconfigure(description: nextDescription);
  }

  Future<void> _switchCameraDuringRecording(
    CameraDescription nextDescription,
  ) async {
    final previous = _cameraSnapshot;
    _setValueSafely(_cameraSnapshot.copyWith(state: _cameraSwitchingState()));

    try {
      final switchResult = await _platform.switchCamera(cameraId!);
      if (value is CameraSwitchingState) {
        _setValueSafely(
          _cameraSnapshot.copyWith(
            state: _cameraRecordingState(description: nextDescription),
            textureId: switchResult.textureId,
            previewSize: switchResult.previewSize,
          ),
        );
      } else {
        _setValueSafely(
          _cameraSnapshot.copyWith(
            state: value.copyWith(description: nextDescription),
            textureId: switchResult.textureId,
            previewSize: switchResult.previewSize,
          ),
        );
      }
    } on CameraException catch (error) {
      if (value is CameraSwitchingState) {
        _setValueSafely(
          previous.copyWith(state: _stateWithError(previous.state, error)),
        );
      }
      rethrow;
    }
  }

  Future<void> _switchCameraDuringPaused(
    CameraDescription nextDescription,
  ) async {
    final previous = _cameraSnapshot;
    _setValueSafely(_cameraSnapshot.copyWith(state: _cameraSwitchingState()));

    try {
      final switchResult = await _platform.switchCamera(cameraId!);
      if (value is CameraSwitchingState) {
        _setValueSafely(
          _cameraSnapshot.copyWith(
            state: _cameraPausedState(description: nextDescription),
            textureId: switchResult.textureId,
            previewSize: switchResult.previewSize,
          ),
        );
      } else {
        _setValueSafely(
          _cameraSnapshot.copyWith(
            state: value.copyWith(description: nextDescription),
            textureId: switchResult.textureId,
            previewSize: switchResult.previewSize,
          ),
        );
      }
    } on CameraException catch (error) {
      if (value is CameraSwitchingState) {
        _setValueSafely(
          previous.copyWith(state: _stateWithError(previous.state, error)),
        );
      }
      rethrow;
    }
  }

  Future<String?> stopRecording() async {
    _assertInitialized('stopRecording');

    // If already stopping, return the in-flight future to deduplicate
    // concurrent calls (e.g. double-tap on the stop button).
    final inFlight = _stopRecordingFuture;
    if (inFlight != null) {
      return inFlight;
    }

    _assertState(
      allows: (state) =>
          state is CameraRecordingState ||
          state is CameraPausedState ||
          state is CameraSwitchingState,
      method: 'stopRecording',
    );

    final previous = _cameraSnapshot;
    _setValueSafely(
      _cameraSnapshot.copyWith(state: _cameraStoppingRecordingState()),
    );

    final future = _stopRecordingInternal(previous);
    _stopRecordingFuture = future;
    return future.whenComplete(() {
      if (identical(_stopRecordingFuture, future)) {
        _stopRecordingFuture = null;
      }
    });
  }

  Future<String?> _stopRecordingInternal(CameraSnapshot previous) async {
    try {
      final filePath = await _platform.stopRecording(cameraId!);
      // The session is over either way; segment bookkeeping does not carry
      // across takes.
      _sealedSegmentCount = 0;
      if (filePath != null) {
        _setValueSafely(
          _cameraSnapshot.copyWith(
            state: _cameraVideoRecordedState(recordedFilePath: filePath),
          ),
        );
      } else {
        // Recording stopped before any frames were captured.
        // Transition back to ready state.
        _setValueSafely(_cameraSnapshot.copyWith(state: _cameraReadyState()));
      }
      return filePath;
    } on CameraException catch (error) {
      _setValueSafely(
        previous.copyWith(state: _stateWithError(previous.state, error)),
      );
      rethrow;
    }
  }

  Future<void> disposeCamera() async {
    if (_cameraSnapshot.isDisposed) {
      return;
    }

    final currentCameraId = cameraId;
    await _recordingStateSubscription?.cancel();
    _recordingStateSubscription = null;
    await _audioDeviceSubscription?.cancel();
    _audioDeviceSubscription = null;
    await _audioLevelSubscription?.cancel();
    _audioLevelSubscription = null;
    _audioLevelCameraId = null;

    if (currentCameraId != null) {
      await _platform.disposeCamera(currentCameraId);
    }

    _setValueSafely(
      _cameraSnapshot.copyWith(
        state: _cameraDisposedState(),
        clearCameraId: true,
        clearTextureId: true,
        clearPreviewSize: true,
      ),
    );
  }

  Future<void> reconfigure({
    CameraDescription? description,
    CameraConfig? config,
  }) async {
    _assertNotDisposed('reconfigure');

    final nextDescription = description ?? this.description;
    final nextConfig = config ?? this.config;

    await disposeCamera();

    _setValueSafely(
      CameraSnapshot(
        state: CameraUninitializedState(
          config: nextConfig,
          description: nextDescription,
          hasMultipleCameras: hasMultipleCameras,
        ),
      ),
    );

    await prewarmUp();
  }

  Future<void> refreshAvailableCameras() async {
    _assertNotDisposed('refreshAvailableCameras');
    _availableCameras = await preloadAvailableCameras(
      platform: _platform,
      forceRefresh: true,
    );
  }

  Future<void> switchToNextCamera() async {
    await switchCamera();
  }

  void clearRecordedFile() {
    _assertNotDisposed('clearRecordedFile');
    _sealedSegmentCount = 0;
    _setValueSafely(_cameraSnapshot.copyWith(state: _cameraReadyState()));
  }

  Future<void> _initializeInternal() async {
    _assertState(
      allows: (state) => state is CameraUninitializedState,
      method: 'initialize',
    );

    final previous = _cameraSnapshot;
    _setValueSafely(
      _cameraSnapshot.copyWith(state: _cameraInitializingState()),
    );

    try {
      final description = await _resolveDescriptionForInitialization();
      final cameraId = await _platform.createCamera(description, config);
      final initializationResult = await _platform.initializeCamera(cameraId);
      await _subscribeToRecordingState(cameraId);
      await _subscribeToAudioDeviceChanged(cameraId);
      _audioLevelCameraId = cameraId;
      if (_audioLevelController.hasListener) {
        _connectAudioLevelStream();
      }

      _setValueSafely(
        _cameraSnapshot.copyWith(
          state: _cameraReadyState(description: description),
          cameraId: cameraId,
          textureId: initializationResult.textureId,
          previewSize: initializationResult.previewSize,
        ),
      );
    } on CameraException catch (error) {
      _setValueSafely(
        previous.copyWith(state: _stateWithError(previous.state, error)),
      );
      rethrow;
    }
  }

  Future<CameraDescription> _resolveDescriptionForInitialization() async {
    final currentDescription = _cameraSnapshot.description;
    if (currentDescription != null) {
      return currentDescription;
    }

    await _ensureAvailableCamerasLoaded();
    final description = selectPreferredCamera(
      _availableCameras,
      preferredLens: _preferredLens,
    );
    _setValueSafely(
      _cameraSnapshot.copyWith(
        state: CameraUninitializedState(
          config: config,
          description: description,
          hasMultipleCameras: hasMultipleCameras,
        ),
      ),
    );
    return description;
  }

  Future<CameraDescription> _resolveNextCameraDescription() async {
    await _ensureAvailableCamerasLoaded();

    if (_availableCameras.length < 2) {
      throw CameraException(
        code: 'no_alternative_camera',
        message: 'No secondary camera is available to switch to.',
      );
    }

    final currentIndex = _availableCameras.indexOf(description);
    if (currentIndex == -1) {
      return _availableCameras.first;
    }

    final nextIndex = (currentIndex + 1) % _availableCameras.length;
    return _availableCameras[nextIndex];
  }

  Future<void> _ensureAvailableCamerasLoaded() async {
    if (_availableCameras.isNotEmpty) {
      return;
    }

    final cachedAvailableCameras = getCachedAvailableCameras(
      platform: _platform,
    );
    if (cachedAvailableCameras != null) {
      _availableCameras = cachedAvailableCameras;
      return;
    }

    _availableCameras = await preloadAvailableCameras(platform: _platform);
  }

  Future<void> _subscribeToRecordingState(int cameraId) async {
    await _recordingStateSubscription?.cancel();
    _recordingStateSubscription = _platform
        .onRecordingStateChanged(cameraId)
        .listen(_handleRecordingState);
  }

  Future<void> _subscribeToAudioDeviceChanged(int cameraId) async {
    await _audioDeviceSubscription?.cancel();
    _audioDeviceSubscription = _platform
        .onAudioDeviceChanged(cameraId)
        .listen(
          _handleAudioDeviceEvent,
          onError: (Object error, StackTrace stackTrace) {
            debugPrint(
              'pretty_awesome_camera audio device stream error: $error',
            );
          },
        );
  }

  /// Applies salvage state transitions **before** forwarding the event.
  ///
  /// Ordering is load-bearing. A native seal happens outside any controller
  /// method, so without this the controller would still claim to be recording
  /// while listeners react to the seal — and every restart would then be
  /// rejected by the `startRecording` guard. Because [_setValueSafely]
  /// notifies synchronously, no listener can observe the notification while
  /// the controller is stale.
  void _handleAudioDeviceEvent(AudioDeviceChangedEvent event) {
    switch (event.event) {
      case recordingSegmentSealedEvent:
        _applySegmentSealed();
      case recordingWriterFailedEvent:
        _applyWriterFailed();
    }
    _audioDeviceChangedController.add(event);
  }

  void _applySegmentSealed() {
    if (_isControllerDisposed || _cameraSnapshot.description == null) {
      return;
    }
    // A seal ends the in-flight recording. Any state that was mid-recording
    // moves to sealed; anything else (already sealed, ready, disposed) is left
    // alone so a duplicate notification is a no-op.
    final state = _cameraSnapshot.state;
    final wasRecording =
        state is CameraRecordingState ||
        state is CameraPausedState ||
        state is CameraStartingRecordingState ||
        state is CameraSwitchingState;
    if (!wasRecording) {
      return;
    }
    _sealedSegmentCount += 1;
    _setValueSafely(
      _cameraSnapshot.copyWith(state: _cameraSegmentSealedState()),
    );
  }

  /// Writer death is a *detected loss*, never a salvage: by the time it is
  /// observable the writer has already failed, and a failed writer can never
  /// be finalized. Native has torn the dead writer down and preserved any
  /// earlier stash; all the controller must do is stop claiming to record, and
  /// land in a state from which restarting is legal.
  void _applyWriterFailed() {
    if (_isControllerDisposed || _cameraSnapshot.description == null) {
      return;
    }
    final state = _cameraSnapshot.state;
    if (state is CameraDisposedState || state is CameraUninitializedState) {
      return;
    }
    _setValueSafely(
      _cameraSnapshot.copyWith(
        state: _sealedSegmentCount > 0
            ? _cameraSegmentSealedState()
            : _cameraReadyState(),
      ),
    );
  }

  void _connectAudioLevelStream() {
    final cameraId = _audioLevelCameraId;
    if (cameraId == null ||
        _audioLevelSubscription != null ||
        _isControllerDisposed) {
      return;
    }
    _audioLevelSubscription = _platform
        .onAudioLevel(cameraId)
        .listen(
          _audioLevelController.add,
          onError: (Object error, StackTrace stackTrace) {
            debugPrint(
              'pretty_awesome_camera audio level stream error: $error',
            );
          },
        );
  }

  void _disconnectAudioLevelStream() {
    final subscription = _audioLevelSubscription;
    _audioLevelSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
  }

  void _handleRecordingState(RecordingState state) {
    switch (state) {
      case RecordingState.idle:
        if (_cameraSnapshot.state is! CameraInitializingState &&
            _cameraSnapshot.state is! CameraDisposedState &&
            _cameraSnapshot.state is! CameraReadyState &&
            _cameraSnapshot.state is! CameraVideoRecordedState &&
            _cameraSnapshot.state is! CameraStoppingRecordingState) {
          _setValueSafely(_cameraSnapshot.copyWith(state: _cameraReadyState()));
        }
        return;
      case RecordingState.recording:
        _setValueSafely(
          _cameraSnapshot.copyWith(state: _cameraRecordingState()),
        );
        return;
      case RecordingState.paused:
        _setValueSafely(_cameraSnapshot.copyWith(state: _cameraPausedState()));
        return;
      case RecordingState.switching:
        _setValueSafely(
          _cameraSnapshot.copyWith(state: _cameraSwitchingState()),
        );
        return;
    }
  }

  void _setValueSafely(CameraSnapshot nextValue) {
    if (_isControllerDisposed) {
      return;
    }
    _cameraSnapshot = nextValue;
    // Wrap notifyListeners to prevent listener errors from propagating
    // back into controller state transitions. A misbehaving listener
    // (e.g. calling setState after dispose) should not break the
    // controller's internal state machine.
    try {
      super.value = nextValue.state;
    } catch (_) {
      // Listener errors are intentionally swallowed here. The controller
      // has already updated its internal snapshot; the notification
      // failure is a UI-layer concern, not a camera lifecycle issue.
    }
  }

  void _assertInitialized(String method) {
    if (cameraId == null || textureId == null) {
      throw CameraException(
        code: 'not_initialized',
        message: 'Cannot call $method before prewarmUp() completes.',
      );
    }
  }

  void _assertNotDisposed(String method) {
    if (_isControllerDisposed || _cameraSnapshot.isDisposed) {
      throw CameraException(
        code: 'disposed',
        message: 'Cannot call $method after the controller is disposed.',
      );
    }
  }

  void _assertState({
    required bool Function(CameraState state) allows,
    required String method,
  }) {
    if (!allows(value)) {
      throw CameraException(
        code: 'invalid_state',
        message: 'Cannot call $method while in ${value.name} state.',
      );
    }
  }

  CameraState _stateWithError(CameraState state, CameraException error) {
    return state.copyWith(error: error, hasMultipleCameras: hasMultipleCameras);
  }

  CameraState _cameraInitializingState() => CameraInitializingState(
    config: config,
    description: _cameraSnapshot.description,
    hasMultipleCameras: hasMultipleCameras,
  );

  CameraState _cameraReadyState({CameraDescription? description}) =>
      CameraReadyState(
        config: config,
        description: description ?? _cameraSnapshot.description!,
        hasMultipleCameras: hasMultipleCameras,
      );

  CameraState _cameraVideoRecordedState({required String recordedFilePath}) =>
      CameraVideoRecordedState(
        config: config,
        description: _cameraSnapshot.description!,
        recordedFilePath: recordedFilePath,
        hasMultipleCameras: hasMultipleCameras,
      );

  CameraState _cameraStartingRecordingState() => CameraStartingRecordingState(
    config: config,
    description: _cameraSnapshot.description!,
    hasMultipleCameras: hasMultipleCameras,
  );

  CameraState _cameraRecordingState({CameraDescription? description}) =>
      CameraRecordingState(
        config: config,
        description: description ?? _cameraSnapshot.description!,
        hasMultipleCameras: hasMultipleCameras,
      );

  CameraState _cameraPausedState({CameraDescription? description}) =>
      CameraPausedState(
        config: config,
        description: description ?? _cameraSnapshot.description!,
        hasMultipleCameras: hasMultipleCameras,
      );

  CameraState _cameraSegmentSealedState() => CameraSegmentSealedState(
    config: config,
    description: _cameraSnapshot.description!,
    sealedSegmentCount: _sealedSegmentCount,
    hasMultipleCameras: hasMultipleCameras,
  );

  CameraState _cameraSwitchingState() => CameraSwitchingState(
    config: config,
    description: _cameraSnapshot.description!,
    hasMultipleCameras: hasMultipleCameras,
  );

  CameraState _cameraStoppingRecordingState() => CameraStoppingRecordingState(
    config: config,
    description: _cameraSnapshot.description!,
    hasMultipleCameras: hasMultipleCameras,
  );

  CameraState _cameraDisposedState() => CameraDisposedState(
    config: config,
    description: _cameraSnapshot.description,
    hasMultipleCameras: hasMultipleCameras,
  );

  @override
  void dispose() {
    _isControllerDisposed = true;
    final subscription = _recordingStateSubscription;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    _recordingStateSubscription = null;

    final audioSubscription = _audioDeviceSubscription;
    if (audioSubscription != null) {
      unawaited(audioSubscription.cancel());
    }
    _audioDeviceSubscription = null;
    unawaited(_audioDeviceChangedController.close());

    final audioLevelSubscription = _audioLevelSubscription;
    if (audioLevelSubscription != null) {
      unawaited(audioLevelSubscription.cancel());
    }
    _audioLevelSubscription = null;
    unawaited(_audioLevelController.close());

    final currentCameraId = cameraId;
    if (currentCameraId != null) {
      unawaited(_platform.disposeCamera(currentCameraId));
    }
    super.dispose();
  }
}
