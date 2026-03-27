import 'package:flutter_test/flutter_test.dart';
import 'package:waffle_camera_plugin/waffle_camera_plugin.dart';
import 'package:waffle_camera_plugin/waffle_camera_plugin_method_channel.dart';
import 'package:waffle_camera_plugin/waffle_camera_plugin_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockWaffleCameraPluginPlatform
    with MockPlatformInterfaceMixin
    implements WaffleCameraPluginPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<List<CameraDescription>> getAvailableCameras() {
    throw UnimplementedError();
  }

  @override
  Future<int> createCamera(CameraDescription camera, CameraConfig config) {
    throw UnimplementedError();
  }

  @override
  Future<int> initializeCamera(int cameraId) {
    throw UnimplementedError();
  }

  @override
  Future<void> startRecording(int cameraId) {
    throw UnimplementedError();
  }

  @override
  Future<String> stopRecording(int cameraId) {
    throw UnimplementedError();
  }

  @override
  Future<void> pauseRecording(int cameraId) {
    throw UnimplementedError();
  }

  @override
  Future<void> resumeRecording(int cameraId) {
    throw UnimplementedError();
  }

  @override
  Future<void> disposeCamera(int cameraId) {
    throw UnimplementedError();
  }

  @override
  Stream<RecordingState> onRecordingStateChanged(int cameraId) {
    throw UnimplementedError();
  }

  @override
  Future<bool> canSwitchCamera(int cameraId) {
    throw UnimplementedError();
  }

  @override
  Future<int> switchCamera(int cameraId) {
    throw UnimplementedError();
  }

  @override
  Future<bool> get canSwitchCurrentCamera {
    throw UnimplementedError();
  }

  @override
  Future<bool> isMultiCamSupported() {
    throw UnimplementedError();
  }

  @override
  Future<String> getSwitchingPath() {
    throw UnimplementedError();
  }
}

class ConcreteWaffleCameraPluginPlatform extends WaffleCameraPluginPlatform {
  @override
  Future<List<CameraDescription>> getAvailableCameras() {
    throw UnimplementedError();
  }

  @override
  Future<int> createCamera(CameraDescription camera, CameraConfig config) {
    throw UnimplementedError();
  }

  @override
  Future<int> initializeCamera(int cameraId) {
    throw UnimplementedError();
  }

  @override
  Future<void> startRecording(int cameraId) {
    throw UnimplementedError();
  }

  @override
  Future<String> stopRecording(int cameraId) {
    throw UnimplementedError();
  }

  @override
  Future<void> pauseRecording(int cameraId) {
    throw UnimplementedError();
  }

  @override
  Future<void> resumeRecording(int cameraId) {
    throw UnimplementedError();
  }

  @override
  Future<void> disposeCamera(int cameraId) {
    throw UnimplementedError();
  }

  @override
  Stream<RecordingState> onRecordingStateChanged(int cameraId) {
    throw UnimplementedError();
  }

  @override
  Future<bool> canSwitchCamera(int cameraId) {
    throw UnimplementedError();
  }

  @override
  Future<int> switchCamera(int cameraId) {
    throw UnimplementedError();
  }

  @override
  Future<bool> get canSwitchCurrentCamera {
    throw UnimplementedError();
  }

  @override
  Future<bool> isMultiCamSupported() {
    throw UnimplementedError();
  }

  @override
  Future<String> getSwitchingPath() {
    throw UnimplementedError();
  }
}

void main() {
  final WaffleCameraPluginPlatform initialPlatform =
      WaffleCameraPluginPlatform.instance;

  test('$MethodChannelWaffleCameraPlugin is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelWaffleCameraPlugin>());
  });

  group('Platform interface methods throw UnimplementedError by default', () {
    late WaffleCameraPluginPlatform platform;

    setUp(() {
      platform = ConcreteWaffleCameraPluginPlatform();
    });

    test('getAvailableCameras throws UnimplementedError', () {
      expect(
        () => platform.getAvailableCameras(),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('createCamera throws UnimplementedError', () {
      final camera = CameraDescription(
        name: 'Test Camera',
        lensDirection: LensDirection.back,
        sensorOrientation: 0,
      );
      expect(
        () => platform.createCamera(camera, const CameraConfig()),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('initializeCamera throws UnimplementedError', () {
      expect(
        () => platform.initializeCamera(0),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('startRecording throws UnimplementedError', () {
      expect(
        () => platform.startRecording(0),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('stopRecording throws UnimplementedError', () {
      expect(
        () => platform.stopRecording(0),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('pauseRecording throws UnimplementedError', () {
      expect(
        () => platform.pauseRecording(0),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('resumeRecording throws UnimplementedError', () {
      expect(
        () => platform.resumeRecording(0),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('disposeCamera throws UnimplementedError', () {
      expect(
        () => platform.disposeCamera(0),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('onRecordingStateChanged throws UnimplementedError', () {
      expect(
        () => platform.onRecordingStateChanged(0),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });
}
