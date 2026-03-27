import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/camera_config.dart';
import '../models/camera_description.dart';
import '../models/camera_exception.dart';
import '../models/camera_state.dart';
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

  Future<void> initialize() async {
    await prewarmUp();
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

  Future<void> startRecording() async {
    _assertInitialized('startRecording');
    _assertState(
      allows: (state) =>
          state is CameraReadyState || state is CameraVideoRecordedState,
      method: 'startRecording',
    );

    final previous = _cameraSnapshot;
    _setValueSafely(
      _cameraSnapshot.copyWith(state: _cameraStartingRecordingState()),
    );

    try {
      await _platform.startRecording(cameraId!);
      _setValueSafely(_cameraSnapshot.copyWith(state: _cameraRecordingState()));
    } on CameraException catch (error) {
      _setValueSafely(previous.copyWith(state: _stateWithError(previous.state, error)));
      rethrow;
    }
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
      _setValueSafely(previous.copyWith(state: _stateWithError(previous.state, error)));
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
      _setValueSafely(previous.copyWith(state: _stateWithError(previous.state, error)));
      rethrow;
    }
  }

  Future<void> switchCamera() async {
    _assertInitialized('switchCamera');
    _assertState(
      allows: (state) => state is CameraRecordingState,
      method: 'switchCamera',
    );

    final previous = _cameraSnapshot;
    _setValueSafely(_cameraSnapshot.copyWith(state: _cameraSwitchingState()));

    try {
      final nextDescription = await _resolveNextCameraDescription();
      final newTextureId = await _platform.switchCamera(cameraId!);
      _setValueSafely(
        _cameraSnapshot.copyWith(
          state: _cameraRecordingState(description: nextDescription),
          textureId: newTextureId,
        ),
      );
    } on CameraException catch (error) {
      _setValueSafely(previous.copyWith(state: _stateWithError(previous.state, error)));
      rethrow;
    }
  }

  Future<String> stopRecording() async {
    _assertInitialized('stopRecording');
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

    try {
      final filePath = await _platform.stopRecording(cameraId!);
      _setValueSafely(
        _cameraSnapshot.copyWith(
          state: _cameraVideoRecordedState(recordedFilePath: filePath),
        ),
      );
      return filePath;
    } on CameraException catch (error) {
      _setValueSafely(previous.copyWith(state: _stateWithError(previous.state, error)));
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

    if (currentCameraId != null) {
      await _platform.disposeCamera(currentCameraId);
    }

    _setValueSafely(
      _cameraSnapshot.copyWith(
        state: _cameraDisposedState(),
        clearCameraId: true,
        clearTextureId: true,
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
    _assertNotDisposed('switchToNextCamera');

    if (value is CameraPausedState) {
      throw CameraException(
        code: 'invalid_state',
        message: 'Cannot switch cameras while recording is paused.',
      );
    }

    final nextDescription = await _resolveNextCameraDescription();

    if (value is CameraRecordingState) {
      await switchCamera();
      return;
    }

    await reconfigure(description: nextDescription);
  }

  void clearRecordedFile() {
    _assertNotDisposed('clearRecordedFile');
    _setValueSafely(_cameraSnapshot.copyWith(state: _cameraReadyState()));
  }

  Future<void> _initializeInternal() async {
    _assertState(
      allows: (state) => state is CameraUninitializedState,
      method: 'initialize',
    );

    final previous = _cameraSnapshot;
    _setValueSafely(_cameraSnapshot.copyWith(state: _cameraInitializingState()));

    try {
      final description = await _resolveDescriptionForInitialization();
      final cameraId = await _platform.createCamera(description, config);
      final textureId = await _platform.initializeCamera(cameraId);
      await _subscribeToRecordingState(cameraId);

      _setValueSafely(
        _cameraSnapshot.copyWith(
          state: _cameraReadyState(description: description),
          cameraId: cameraId,
          textureId: textureId,
        ),
      );
    } on CameraException catch (error) {
      _setValueSafely(previous.copyWith(state: _stateWithError(previous.state, error)));
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

  void _handleRecordingState(RecordingState state) {
    switch (state) {
      case RecordingState.idle:
        if (_cameraSnapshot.state is! CameraInitializingState &&
            _cameraSnapshot.state is! CameraDisposedState &&
            _cameraSnapshot.state is! CameraReadyState &&
            _cameraSnapshot.state is! CameraVideoRecordedState) {
          _setValueSafely(_cameraSnapshot.copyWith(state: _cameraReadyState()));
        }
        return;
      case RecordingState.recording:
        _setValueSafely(_cameraSnapshot.copyWith(state: _cameraRecordingState()));
        return;
      case RecordingState.paused:
        _setValueSafely(_cameraSnapshot.copyWith(state: _cameraPausedState()));
        return;
      case RecordingState.switching:
        _setValueSafely(_cameraSnapshot.copyWith(state: _cameraSwitchingState()));
        return;
    }
  }

  void _setValueSafely(CameraSnapshot nextValue) {
    if (_isControllerDisposed) {
      return;
    }
    _cameraSnapshot = nextValue;
    super.value = nextValue.state;
  }

  void _assertInitialized(String method) {
    if (cameraId == null || textureId == null) {
      throw CameraException(
        code: 'not_initialized',
        message: 'Cannot call $method before initialize() completes.',
      );
    }
  }

  void _assertNotDisposed(String method) {
    if (_cameraSnapshot.isDisposed) {
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

  CameraState _cameraPausedState() => CameraPausedState(
    config: config,
    description: _cameraSnapshot.description!,
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
    final currentCameraId = cameraId;
    if (currentCameraId != null) {
      unawaited(_platform.disposeCamera(currentCameraId));
    }
    super.dispose();
  }
}
