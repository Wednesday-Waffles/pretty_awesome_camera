import '../controller/camera_controller.dart';
import 'camera_config.dart';
import 'camera_description.dart';
import 'camera_exception.dart';
import 'camera_state.dart';

/// Public-facing state exposed by [CameraBuilder].
sealed class CameraBuilderState {
  const CameraBuilderState({
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

  static CameraBuilderState fromController(
    CameraController controller,
    CameraState value,
  ) {
    final metadata = _CameraStateMetadata.from(value);

    if (metadata.error != null) {
      return CameraBuilderErrorState(
        config: metadata.config,
        error: metadata.error!,
        description: metadata.description,
        hasMultipleCameras: controller.hasMultipleCameras,
        retry: () async => controller.reconfigure(),
      );
    }

    final base = _StateBase(
      controller: controller,
      config: metadata.config,
      description: metadata.description,
      hasMultipleCameras: controller.hasMultipleCameras,
    );

    return switch (value) {
      CameraUninitializedState() => CameraBuilderPreparingState(
        config: value.config,
        description: value.description,
        hasMultipleCameras: controller.hasMultipleCameras,
      ),
      CameraInitializingState() => CameraBuilderPreparingState(
        config: value.config,
        description: value.description,
        hasMultipleCameras: controller.hasMultipleCameras,
      ),
      CameraVideoRecordedState() => CameraBuilderVideoRecordedState._fromBase(
        base,
        recordedFilePath: value.recordedFilePath,
      ),
      CameraReadyState() => CameraBuilderReadyState._fromBase(base),
      CameraStartingRecordingState() =>
        CameraBuilderStartingRecordingState._fromBase(base),
      CameraRecordingState() => CameraBuilderRecordingState._fromBase(base),
      CameraPausedState() => CameraBuilderPausedState._fromBase(base),
      CameraSwitchingState() => CameraBuilderSwitchingState._fromBase(base),
      CameraStoppingRecordingState() =>
        CameraBuilderStoppingRecordingState._fromBase(base),
      CameraDisposedState() => CameraBuilderPreparingState(
        config: value.config,
        description: value.description,
        hasMultipleCameras: controller.hasMultipleCameras,
      ),
    };
  }
}

final class CameraBuilderPreparingState extends CameraBuilderState {
  const CameraBuilderPreparingState({
    required super.config,
    super.description,
    super.error,
    super.hasMultipleCameras,
  });

  @override
  String get name => 'preparing';
}

final class CameraBuilderErrorState extends CameraBuilderState {
  const CameraBuilderErrorState({
    required super.config,
    required CameraException super.error,
    super.description,
    super.hasMultipleCameras,
    required this.retry,
  });

  final Future<void> Function() retry;

  @override
  String get name => 'error';
}

sealed class ActiveCameraState extends CameraBuilderState {
  ActiveCameraState._({
    required this.controller,
    required super.config,
    required super.description,
    required super.error,
    required super.hasMultipleCameras,
  });

  final CameraController controller;

  Future<String> getSwitchingPath() => controller.getSwitchingPath();

  Future<bool> isMultiCamSupported() => controller.isMultiCamSupported();

  Future<void> switchCamera() => controller.switchToNextCamera();

  Future<void> updateConfig(CameraConfig config) =>
      controller.reconfigure(config: config);

  void clearCapturedMedia() => controller.clearRecordedFile();
}

final class CameraBuilderReadyState extends ActiveCameraState {
  CameraBuilderReadyState._fromBase(_StateBase base)
    : super._(
        controller: base.controller,
        config: base.config,
        description: base.description,
        error: null,
        hasMultipleCameras: base.hasMultipleCameras,
      );

  Future<void> startRecording() => controller.startRecording();

  @override
  String get name => 'ready';
}

final class CameraBuilderVideoRecordedState extends ActiveCameraState {
  CameraBuilderVideoRecordedState._fromBase(
    _StateBase base, {
    required this.recordedFilePath,
  }) : super._(
         controller: base.controller,
         config: base.config,
         description: base.description,
         error: null,
         hasMultipleCameras: base.hasMultipleCameras,
       );

  final String recordedFilePath;

  Future<void> startRecording() => controller.startRecording();

  @override
  String get name => 'videoRecorded';
}

final class CameraBuilderStartingRecordingState extends ActiveCameraState {
  CameraBuilderStartingRecordingState._fromBase(_StateBase base)
    : super._(
        controller: base.controller,
        config: base.config,
        description: base.description,
        error: null,
        hasMultipleCameras: base.hasMultipleCameras,
      );

  @override
  String get name => 'startingRecording';
}

final class CameraBuilderRecordingState extends ActiveCameraState {
  CameraBuilderRecordingState._fromBase(_StateBase base)
    : super._(
        controller: base.controller,
        config: base.config,
        description: base.description,
        error: null,
        hasMultipleCameras: base.hasMultipleCameras,
      );

  Future<void> pauseRecording() => controller.pauseRecording();

  Future<String> stopRecording() => controller.stopRecording();

  @override
  String get name => 'recording';
}

final class CameraBuilderPausedState extends ActiveCameraState {
  CameraBuilderPausedState._fromBase(_StateBase base)
    : super._(
        controller: base.controller,
        config: base.config,
        description: base.description,
        error: null,
        hasMultipleCameras: base.hasMultipleCameras,
      );

  Future<void> resumeRecording() => controller.resumeRecording();

  Future<String> stopRecording() => controller.stopRecording();

  @override
  String get name => 'paused';
}

final class CameraBuilderSwitchingState extends ActiveCameraState {
  CameraBuilderSwitchingState._fromBase(_StateBase base)
    : super._(
        controller: base.controller,
        config: base.config,
        description: base.description,
        error: null,
        hasMultipleCameras: base.hasMultipleCameras,
      );

  Future<String> stopRecording() => controller.stopRecording();

  @override
  String get name => 'switchingCamera';
}

final class CameraBuilderStoppingRecordingState extends ActiveCameraState {
  CameraBuilderStoppingRecordingState._fromBase(_StateBase base)
    : super._(
        controller: base.controller,
        config: base.config,
        description: base.description,
        error: null,
        hasMultipleCameras: base.hasMultipleCameras,
      );

  @override
  String get name => 'stoppingRecording';
}

final class _StateBase {
  const _StateBase({
    required this.controller,
    required this.config,
    required this.description,
    required this.hasMultipleCameras,
  });

  final CameraController controller;
  final CameraConfig config;
  final CameraDescription? description;
  final bool hasMultipleCameras;
}

final class _CameraStateMetadata {
  const _CameraStateMetadata({
    required this.config,
    this.description,
    this.error,
  });

  final CameraConfig config;
  final CameraDescription? description;
  final CameraException? error;

  factory _CameraStateMetadata.from(CameraState state) {
    return switch (state) {
      CameraUninitializedState() => _CameraStateMetadata(
        config: state.config,
        description: state.description,
        error: state.error,
      ),
      CameraInitializingState() => _CameraStateMetadata(
        config: state.config,
        description: state.description,
        error: state.error,
      ),
      CameraReadyState() => _CameraStateMetadata(
        config: state.config,
        description: state.description,
        error: state.error,
      ),
      CameraVideoRecordedState() => _CameraStateMetadata(
        config: state.config,
        description: state.description,
        error: state.error,
      ),
      CameraStartingRecordingState() => _CameraStateMetadata(
        config: state.config,
        description: state.description,
        error: state.error,
      ),
      CameraRecordingState() => _CameraStateMetadata(
        config: state.config,
        description: state.description,
        error: state.error,
      ),
      CameraPausedState() => _CameraStateMetadata(
        config: state.config,
        description: state.description,
        error: state.error,
      ),
      CameraSwitchingState() => _CameraStateMetadata(
        config: state.config,
        description: state.description,
        error: state.error,
      ),
      CameraStoppingRecordingState() => _CameraStateMetadata(
        config: state.config,
        description: state.description,
        error: state.error,
      ),
      CameraDisposedState() => _CameraStateMetadata(
        config: state.config,
        description: state.description,
        error: state.error,
      ),
    };
  }
}
