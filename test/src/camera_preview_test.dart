import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_awesome_camera/pretty_awesome_camera.dart';

class _FakePreviewCameraPlatform extends PrettyAwesomeCameraPlatform {
  @override
  Future<List<CameraDescription>> getAvailableCameras() async => const [];

  @override
  Future<int> createCamera(
    CameraDescription camera,
    CameraConfig config,
  ) async => 1;

  @override
  Future<CameraInitializationResult> initializeCamera(int cameraId) async {
    return const CameraInitializationResult(
      textureId: 42,
      previewSize: CameraPreviewSize(width: 1440, height: 1080),
    );
  }

  @override
  Future<void> startRecording(int cameraId) async {}

  @override
  Future<String> stopRecording(int cameraId) async => '/tmp/test.mov';

  @override
  Future<void> pauseRecording(int cameraId) async {}

  @override
  Future<void> resumeRecording(int cameraId) async {}

  @override
  Future<void> disposeCamera(int cameraId) async {}

  @override
  Stream<RecordingState> onRecordingStateChanged(int cameraId) =>
      const Stream<RecordingState>.empty();

  @override
  Future<bool> canSwitchCamera(int cameraId) async => true;

  @override
  Future<CameraInitializationResult> switchCamera(int cameraId) async {
    return const CameraInitializationResult(
      textureId: 43,
      previewSize: CameraPreviewSize(width: 1440, height: 1080),
    );
  }

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
  TestWidgetsFlutterBinding.ensureInitialized();

  late CameraController controller;

  setUp(() async {
    controller = CameraController(
      description: const CameraDescription(
        name: 'Front Camera',
        lensDirection: LensDirection.front,
        sensorOrientation: 90,
      ),
      platform: _FakePreviewCameraPlatform(),
    );
    await controller.prewarmUp();
  });

  tearDown(() async {
    await controller.disposeCamera();
    controller.dispose();
  });

  testWidgets('uses the current layout ratio by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 300,
          height: 600,
          child: CameraPreview(controller: controller),
        ),
      ),
    );

    expect(find.byType(AspectRatio), findsNothing);
    expect(find.byType(OverflowBox), findsOneWidget);
  });

  testWidgets('applies the requested aspect ratio as a crop container', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 300,
          height: 600,
          child: CameraPreview(
            controller: controller,
            aspectRatio: 9 / 16,
          ),
        ),
      ),
    );

    final outerAspectRatio = tester.widget<AspectRatio>(find.byType(AspectRatio));

    expect(outerAspectRatio.aspectRatio, closeTo(9 / 16, 0.0001));
    expect(find.byType(OverflowBox), findsOneWidget);
  });
}
