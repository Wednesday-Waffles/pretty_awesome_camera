import '../models/camera_config.dart';
import '../models/camera_description.dart';
import '../models/camera_exception.dart';
import '../models/camera_state.dart';

/// Internal controller snapshot used to track platform ids and transient data.
class CameraSnapshot {
  const CameraSnapshot({
    required this.state,
    this.cameraId,
    this.textureId,
  });

  CameraSnapshot.uninitialized({required CameraConfig config})
    : this(state: CameraUninitializedState(config: config));

  final CameraState state;
  final int? cameraId;
  final int? textureId;

  CameraConfig get config => switch (state) {
    CameraUninitializedState(:final config) => config,
    CameraInitializingState(:final config) => config,
    CameraReadyState(:final config) => config,
    CameraVideoRecordedState(:final config) => config,
    CameraStartingRecordingState(:final config) => config,
    CameraRecordingState(:final config) => config,
    CameraPausedState(:final config) => config,
    CameraSwitchingState(:final config) => config,
    CameraStoppingRecordingState(:final config) => config,
    CameraDisposedState(:final config) => config,
  };

  CameraDescription? get description => switch (state) {
    CameraUninitializedState(:final description) => description,
    CameraInitializingState(:final description) => description,
    CameraReadyState(:final description) => description,
    CameraVideoRecordedState(:final description) => description,
    CameraStartingRecordingState(:final description) => description,
    CameraRecordingState(:final description) => description,
    CameraPausedState(:final description) => description,
    CameraSwitchingState(:final description) => description,
    CameraStoppingRecordingState(:final description) => description,
    CameraDisposedState(:final description) => description,
  };

  CameraException? get error => switch (state) {
    CameraUninitializedState(:final error) => error,
    CameraInitializingState(:final error) => error,
    CameraReadyState(:final error) => error,
    CameraVideoRecordedState(:final error) => error,
    CameraStartingRecordingState(:final error) => error,
    CameraRecordingState(:final error) => error,
    CameraPausedState(:final error) => error,
    CameraSwitchingState(:final error) => error,
    CameraStoppingRecordingState(:final error) => error,
    CameraDisposedState(:final error) => error,
  };

  bool get isInitialized => switch (state) {
    CameraReadyState() ||
    CameraVideoRecordedState() ||
    CameraStartingRecordingState() ||
    CameraRecordingState() ||
    CameraPausedState() ||
    CameraSwitchingState() ||
    CameraStoppingRecordingState() => true,
    CameraUninitializedState() ||
    CameraInitializingState() ||
    CameraDisposedState() => false,
  };

  bool get isDisposed => state is CameraDisposedState;

  CameraSnapshot copyWith({
    CameraState? state,
    int? cameraId,
    int? textureId,
    bool clearCameraId = false,
    bool clearTextureId = false,
  }) {
    return CameraSnapshot(
      state: state ?? this.state,
      cameraId: clearCameraId ? null : (cameraId ?? this.cameraId),
      textureId: clearTextureId ? null : (textureId ?? this.textureId),
    );
  }
}
