import 'camera_config.dart';
import 'camera_description.dart';
import 'camera_exception.dart';

sealed class CameraState {
  const CameraState({
    required this.config,
    this.description,
    this.error,
    this.hasMultipleCameras = false,
  });

  final CameraConfig config;
  final CameraDescription? description;
  final CameraException? error;
  final bool hasMultipleCameras;

  String get name;

  CameraState copyWith({
    CameraConfig? config,
    CameraDescription? description,
    CameraException? error,
    bool? hasMultipleCameras,
  });
}

final class CameraUninitializedState extends CameraState {
  const CameraUninitializedState({
    required super.config,
    super.description,
    super.error,
    super.hasMultipleCameras,
  });

  @override
  String get name => 'uninitialized';

  bool get isUninitialized => true;

  @override
  CameraUninitializedState copyWith({
    CameraConfig? config,
    CameraDescription? description,
    CameraException? error,
    bool? hasMultipleCameras,
  }) {
    return CameraUninitializedState(
      config: config ?? this.config,
      description: description ?? this.description,
      error: error ?? this.error,
      hasMultipleCameras: hasMultipleCameras ?? this.hasMultipleCameras,
    );
  }
}

final class CameraInitializingState extends CameraState {
  const CameraInitializingState({
    required super.config,
    super.description,
    super.error,
    super.hasMultipleCameras,
  });

  @override
  String get name => 'initializing';

  bool get isInitializing => true;

  @override
  CameraInitializingState copyWith({
    CameraConfig? config,
    CameraDescription? description,
    CameraException? error,
    bool? hasMultipleCameras,
  }) {
    return CameraInitializingState(
      config: config ?? this.config,
      description: description ?? this.description,
      error: error ?? this.error,
      hasMultipleCameras: hasMultipleCameras ?? this.hasMultipleCameras,
    );
  }
}

final class CameraReadyState extends CameraState {
  const CameraReadyState({
    required super.config,
    required CameraDescription super.description,
    super.error,
    super.hasMultipleCameras,
  });

  @override
  String get name => 'ready';

  bool get isInitialized => true;

  bool get isReady => true;

  bool get canStartRecording => true;

  @override
  CameraReadyState copyWith({
    CameraConfig? config,
    CameraDescription? description,
    CameraException? error,
    bool? hasMultipleCameras,
  }) {
    return CameraReadyState(
      config: config ?? this.config,
      description: description ?? this.description!,
      error: error ?? this.error,
      hasMultipleCameras: hasMultipleCameras ?? this.hasMultipleCameras,
    );
  }
}

final class CameraVideoRecordedState extends CameraState {
  const CameraVideoRecordedState({
    required super.config,
    required CameraDescription super.description,
    required this.recordedFilePath,
    super.error,
    super.hasMultipleCameras,
  });

  final String recordedFilePath;

  @override
  String get name => 'videoRecorded';

  bool get isInitialized => true;

  bool get isReady => true;

  bool get canStartRecording => true;

  @override
  CameraVideoRecordedState copyWith({
    CameraConfig? config,
    CameraDescription? description,
    CameraException? error,
    bool? hasMultipleCameras,
  }) {
    return CameraVideoRecordedState(
      config: config ?? this.config,
      description: description ?? this.description!,
      recordedFilePath: recordedFilePath,
      error: error ?? this.error,
      hasMultipleCameras: hasMultipleCameras ?? this.hasMultipleCameras,
    );
  }
}

/// The in-flight segment was sealed by native — typically because an OS
/// interruption or a background transition began — and the camera session is
/// still alive and previewing.
///
/// This is deliberately **not** [CameraVideoRecordedState]: that state means
/// "a finished recording is ready to hand downstream", and consumers wire it
/// straight into their delivery path. A sealed segment must instead wait for
/// the user to decide what happens to it, so it needs a state of its own.
///
/// Recording is no longer running here, so this state permits starting again —
/// either appending a new segment ([CameraController.startRecordingSegment])
/// or discarding and starting fresh ([CameraController.startRecording]).
final class CameraSegmentSealedState extends CameraState {
  const CameraSegmentSealedState({
    required super.config,
    required CameraDescription super.description,
    required this.sealedSegmentCount,
    super.error,
    super.hasMultipleCameras,
  });

  /// How many segments have been sealed in this session so far. Always >= 1
  /// when reached by a seal; it can be 0 only if a consumer constructs the
  /// state directly.
  final int sealedSegmentCount;

  @override
  String get name => 'segmentSealed';

  bool get isInitialized => true;

  bool get canStartRecording => true;

  bool get canResumeSegment => true;

  @override
  CameraSegmentSealedState copyWith({
    CameraConfig? config,
    CameraDescription? description,
    CameraException? error,
    bool? hasMultipleCameras,
  }) {
    return CameraSegmentSealedState(
      config: config ?? this.config,
      description: description ?? this.description!,
      // Preserved deliberately: a failed restart attaches an error to this
      // state, and losing the count here would make the failure look like a
      // session with nothing salvaged.
      sealedSegmentCount: sealedSegmentCount,
      error: error ?? this.error,
      hasMultipleCameras: hasMultipleCameras ?? this.hasMultipleCameras,
    );
  }
}

final class CameraStartingRecordingState extends CameraState {
  const CameraStartingRecordingState({
    required super.config,
    required CameraDescription super.description,
    super.error,
    super.hasMultipleCameras,
  });

  @override
  String get name => 'startingRecording';

  bool get isInitialized => true;

  bool get isRecording => true;

  @override
  CameraStartingRecordingState copyWith({
    CameraConfig? config,
    CameraDescription? description,
    CameraException? error,
    bool? hasMultipleCameras,
  }) {
    return CameraStartingRecordingState(
      config: config ?? this.config,
      description: description ?? this.description!,
      error: error ?? this.error,
      hasMultipleCameras: hasMultipleCameras ?? this.hasMultipleCameras,
    );
  }
}

final class CameraRecordingState extends CameraState {
  const CameraRecordingState({
    required super.config,
    required CameraDescription super.description,
    super.error,
    super.hasMultipleCameras,
  });

  @override
  String get name => 'recording';

  bool get isInitialized => true;

  bool get isRecording => true;

  bool get canPauseRecording => true;

  bool get canStopRecording => true;

  bool get canSwitchCamera => true;

  @override
  CameraRecordingState copyWith({
    CameraConfig? config,
    CameraDescription? description,
    CameraException? error,
    bool? hasMultipleCameras,
  }) {
    return CameraRecordingState(
      config: config ?? this.config,
      description: description ?? this.description!,
      error: error ?? this.error,
      hasMultipleCameras: hasMultipleCameras ?? this.hasMultipleCameras,
    );
  }
}

final class CameraPausedState extends CameraState {
  const CameraPausedState({
    required super.config,
    required CameraDescription super.description,
    super.error,
    super.hasMultipleCameras,
  });

  @override
  String get name => 'paused';

  bool get isInitialized => true;

  bool get isPaused => true;

  bool get canResumeRecording => true;

  bool get canStopRecording => true;

  @override
  CameraPausedState copyWith({
    CameraConfig? config,
    CameraDescription? description,
    CameraException? error,
    bool? hasMultipleCameras,
  }) {
    return CameraPausedState(
      config: config ?? this.config,
      description: description ?? this.description!,
      error: error ?? this.error,
      hasMultipleCameras: hasMultipleCameras ?? this.hasMultipleCameras,
    );
  }
}

final class CameraSwitchingState extends CameraState {
  const CameraSwitchingState({
    required super.config,
    required CameraDescription super.description,
    super.error,
    super.hasMultipleCameras,
  });

  @override
  String get name => 'switchingCamera';

  bool get isInitialized => true;

  bool get isSwitchingCamera => true;

  bool get canStopRecording => true;

  @override
  CameraSwitchingState copyWith({
    CameraConfig? config,
    CameraDescription? description,
    CameraException? error,
    bool? hasMultipleCameras,
  }) {
    return CameraSwitchingState(
      config: config ?? this.config,
      description: description ?? this.description!,
      error: error ?? this.error,
      hasMultipleCameras: hasMultipleCameras ?? this.hasMultipleCameras,
    );
  }
}

final class CameraStoppingRecordingState extends CameraState {
  const CameraStoppingRecordingState({
    required super.config,
    required CameraDescription super.description,
    super.error,
    super.hasMultipleCameras,
  });

  @override
  String get name => 'stoppingRecording';

  bool get isInitialized => true;

  @override
  CameraStoppingRecordingState copyWith({
    CameraConfig? config,
    CameraDescription? description,
    CameraException? error,
    bool? hasMultipleCameras,
  }) {
    return CameraStoppingRecordingState(
      config: config ?? this.config,
      description: description ?? this.description!,
      error: error ?? this.error,
      hasMultipleCameras: hasMultipleCameras ?? this.hasMultipleCameras,
    );
  }
}

final class CameraDisposedState extends CameraState {
  const CameraDisposedState({
    required super.config,
    super.description,
    super.error,
    super.hasMultipleCameras,
  });

  @override
  String get name => 'disposed';

  @override
  CameraDisposedState copyWith({
    CameraConfig? config,
    CameraDescription? description,
    CameraException? error,
    bool? hasMultipleCameras,
  }) {
    return CameraDisposedState(
      config: config ?? this.config,
      description: description ?? this.description,
      error: error ?? this.error,
      hasMultipleCameras: hasMultipleCameras ?? this.hasMultipleCameras,
    );
  }
}
