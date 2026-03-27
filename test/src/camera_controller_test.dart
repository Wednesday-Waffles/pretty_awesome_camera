import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_awesome_camera/camera_controller.dart';
import 'package:pretty_awesome_camera/src/camera_config.dart';
import 'package:pretty_awesome_camera/src/camera_description.dart';
import 'package:pretty_awesome_camera/src/camera_exception.dart';
import 'package:pretty_awesome_camera/src/camera_state.dart';
import 'package:pretty_awesome_camera/src/recording_state.dart';
import 'package:pretty_awesome_camera/src/resolution_preset.dart';
import 'package:pretty_awesome_camera/pretty_awesome_camera_platform_interface.dart';

class FakeCameraPlatform extends PrettyAwesomeCameraPlatform {
  final StreamController<RecordingState> recordingStateController =
      StreamController<RecordingState>.broadcast();
  List<CameraDescription> availableCameras = [];
  int getAvailableCamerasCallCount = 0;

  int nextCameraId = 1;
  int nextTextureId = 101;
  String stopRecordingPath = '/tmp/test.mov';

  @override
  Future<List<CameraDescription>> getAvailableCameras() async {
    getAvailableCamerasCallCount++;
    return availableCameras;
  }

  @override
  Future<int> createCamera(
    CameraDescription camera,
    CameraConfig config,
  ) async {
    return nextCameraId++;
  }

  @override
  Future<int> initializeCamera(int cameraId) async => nextTextureId++;

  @override
  Future<void> startRecording(int cameraId) async {}

  @override
  Future<String> stopRecording(int cameraId) async => stopRecordingPath;

  @override
  Future<void> pauseRecording(int cameraId) async {}

  @override
  Future<void> resumeRecording(int cameraId) async {}

  @override
  Future<void> disposeCamera(int cameraId) async {}

  @override
  Stream<RecordingState> onRecordingStateChanged(int cameraId) {
    return recordingStateController.stream;
  }

  @override
  Future<bool> canSwitchCamera(int cameraId) async => true;

  @override
  Future<int> switchCamera(int cameraId) async => nextTextureId++;

  @override
  Future<bool> get canSwitchCurrentCamera async => true;

  @override
  Future<bool> isMultiCamSupported() async => false;

  @override
  Future<String> getSwitchingPath() async => 'fallbackSegmentMerge';

  @override
  Future<String?> getPlatformVersion() async => 'test';
}

void main() {
  late FakeCameraPlatform platform;
  late CameraDescription description;

  setUp(() {
    CameraController.clearAvailableCamerasCache();
    platform = FakeCameraPlatform();
    description = const CameraDescription(
      name: 'Back Camera',
      lensDirection: LensDirection.back,
      sensorOrientation: 90,
    );
    platform.availableCameras = [
      const CameraDescription(
        name: 'Front Camera',
        lensDirection: LensDirection.front,
        sensorOrientation: 90,
      ),
      description,
    ];
  });

  tearDown(() async {
    await platform.recordingStateController.close();
  });

  test('starts uninitialized with config', () {
    final controller = CameraController(
      description: description,
      config: const CameraConfig(resolutionPreset: ResolutionPreset.veryHigh),
      platform: platform,
    );

    expect(controller.value, isA<CameraUninitializedState>());
    expect(controller.config.resolutionPreset, ResolutionPreset.veryHigh);
  });

  test('initialize transitions to ready with ids', () async {
    final controller = CameraController(
      description: description,
      platform: platform,
    );

    await controller.initialize();

    expect(controller.value, isA<CameraReadyState>());
    expect(controller.cameraId, isNotNull);
    expect(controller.textureId, isNotNull);
  });

  test('create selects the front camera without prewarming', () async {
    final controller = await CameraController.create(platform: platform);

    expect(controller.description.lensDirection, LensDirection.front);
    expect(controller.value, isA<CameraUninitializedState>());
    expect(controller.textureId, isNull);
  });

  test('create uses config lensDirection when provided', () async {
    final controller = await CameraController.create(
      config: const CameraConfig(lensDirection: LensDirection.back),
      platform: platform,
    );

    expect(controller.description.lensDirection, LensDirection.back);
    expect(controller.value, isA<CameraUninitializedState>());
  });

  test('create falls back to front camera when config lensDirection is null', () async {
    final controller = await CameraController.create(
      config: const CameraConfig(lensDirection: null),
      platform: platform,
    );

    expect(controller.description.lensDirection, LensDirection.front);
    expect(controller.value, isA<CameraUninitializedState>());
  });

  test('preloadAvailableCameras caches discovery for later prewarm', () async {
    final cached = await CameraController.preloadAvailableCameras(
      platform: platform,
    );
    final controller = CameraController(platform: platform);

    await controller.prewarmUp();

    expect(cached, isNotEmpty);
    expect(controller.description.lensDirection, LensDirection.front);
    expect(platform.getAvailableCamerasCallCount, 1);
  });

  test('preloadAvailableCameras can force refresh cache', () async {
    await CameraController.preloadAvailableCameras(platform: platform);
    await CameraController.preloadAvailableCameras(
      platform: platform,
      forceRefresh: true,
    );

    expect(platform.getAvailableCamerasCallCount, 2);
  });

  test('prewarmUp can resolve and initialize without a description', () async {
    final controller = CameraController(platform: platform);

    await controller.prewarmUp();

    expect(controller.value, isA<CameraReadyState>());
    expect(controller.description.lensDirection, LensDirection.front);
    expect(controller.textureId, isNotNull);
  });

  test('prewarmUp is idempotent once ready', () async {
    final controller = CameraController(platform: platform);

    await controller.prewarmUp();
    final firstCameraId = controller.cameraId;
    final firstTextureId = controller.textureId;

    await controller.prewarmUp();

    expect(controller.cameraId, firstCameraId);
    expect(controller.textureId, firstTextureId);
  });

  test('recording lifecycle transitions are enforced', () async {
    final controller = CameraController(
      description: description,
      platform: platform,
    );

    await controller.initialize();
    await controller.startRecording();
    expect(controller.value, isA<CameraRecordingState>());

    await controller.pauseRecording();
    expect(controller.value, isA<CameraPausedState>());

    await controller.resumeRecording();
    expect(controller.value, isA<CameraRecordingState>());

    final path = await controller.stopRecording();
    expect(path, '/tmp/test.mov');
    expect(
      controller.value,
      isA<CameraVideoRecordedState>().having(
        (value) => value.recordedFilePath,
        'recordedFilePath',
        '/tmp/test.mov',
      ),
    );
  });

  test('switch camera updates texture and returns to recording', () async {
    final controller = CameraController(
      description: description,
      availableCameras: platform.availableCameras,
      platform: platform,
    );

    await controller.initialize();
    final initialTextureId = controller.textureId;
    await controller.startRecording();
    await controller.switchCamera();

    expect(controller.value, isA<CameraRecordingState>());
    expect(controller.textureId, isNot(initialTextureId));
    expect(controller.description.lensDirection, LensDirection.front);
  });

  test('switchToNextCamera reconfigures when not recording', () async {
    final controller = CameraController(
      description: description,
      availableCameras: platform.availableCameras,
      platform: platform,
    );

    await controller.initialize();
    await controller.switchToNextCamera();

    expect(controller.value, isA<CameraReadyState>());
    expect(controller.description.lensDirection, LensDirection.front);
  });

  test('invalid transition throws camera exception', () async {
    final controller = CameraController(
      description: description,
      platform: platform,
    );

    expect(
      controller.startRecording,
      throwsA(
        isA<CameraException>().having((e) => e.code, 'code', 'not_initialized'),
      ),
    );
  });

  test('recording stream updates controller state', () async {
    final controller = CameraController(
      description: description,
      platform: platform,
    );

    await controller.initialize();
    platform.recordingStateController.add(RecordingState.recording);
    await Future<void>.delayed(Duration.zero);
    expect(controller.value, isA<CameraRecordingState>());

    platform.recordingStateController.add(RecordingState.paused);
    await Future<void>.delayed(Duration.zero);
    expect(controller.value, isA<CameraPausedState>());

    platform.recordingStateController.add(RecordingState.idle);
    await Future<void>.delayed(Duration.zero);
    expect(controller.value, isA<CameraReadyState>());
  });

  test('dispose transitions to disposed state', () async {
    final controller = CameraController(
      description: description,
      platform: platform,
    );

    await controller.initialize();
    await controller.disposeCamera();

    expect(controller.value, isA<CameraDisposedState>());
  });

  test('camera state boolean helpers match their concrete states', () {
    expect(
      CameraRecordingState(
        config: const CameraConfig(),
        description: description,
      ).isRecording,
      isTrue,
    );

    expect(
      CameraPausedState(
        config: const CameraConfig(),
        description: description,
      ).isPaused,
      isTrue,
    );

    expect(
      CameraSwitchingState(
        config: const CameraConfig(),
        description: description,
      ).isSwitchingCamera,
      isTrue,
    );
  });
}
