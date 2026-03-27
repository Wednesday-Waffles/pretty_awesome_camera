import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:waffle_camera_plugin/waffle_camera_plugin.dart';
import 'package:waffle_camera_plugin/waffle_camera_plugin_platform_interface.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('iOS Camera Integration Tests', () {
    late WaffleCameraPluginPlatform platform;

    setUp(() {
      platform = WaffleCameraPluginPlatform.instance;
    });

    test('getAvailableCameras returns camera list', () async {
      final cameras = await platform.getAvailableCameras();

      expect(cameras, isNotEmpty);
      expect(cameras.first.name, isNotEmpty);
      expect(cameras.first.lensDirection, isNotNull);
    });

    test('full recording flow - happy path', () async {
      // Get available cameras
      final cameras = await platform.getAvailableCameras();
      expect(cameras, isNotEmpty, reason: 'No cameras available');

      final camera = cameras.first;

      // Create camera
      final cameraId = await platform.createCamera(
        camera,
        const CameraConfig(resolutionPreset: ResolutionPreset.high),
      );
      expect(cameraId, isNonNegative);

      // Initialize camera
      await platform.initializeCamera(cameraId);

      // Start recording
      await platform.startRecording(cameraId);

      // Wait a bit
      await Future.delayed(const Duration(seconds: 1));

      // Pause recording (requires iOS 18+)
      try {
        await platform.pauseRecording(cameraId);

        // Wait a bit
        await Future.delayed(const Duration(milliseconds: 500));

        // Resume recording
        await platform.resumeRecording(cameraId);

        // Wait a bit
        await Future.delayed(const Duration(seconds: 1));
      } on CameraException catch (e) {
        // iOS < 18 doesn't support pause/resume
        expect(e.code, equals('UNSUPPORTED'));
      }

      // Stop recording
      final filePath = await platform.stopRecording(cameraId);
      expect(filePath, isNotEmpty);

      // Verify file exists
      final file = File(filePath);
      expect(await file.exists(), isTrue);

      // Dispose camera
      await platform.disposeCamera(cameraId);
    });

    test('error: pause without recording', () async {
      final cameras = await platform.getAvailableCameras();
      final camera = cameras.first;

      final cameraId = await platform.createCamera(
        camera,
        const CameraConfig(resolutionPreset: ResolutionPreset.high),
      );
      await platform.initializeCamera(cameraId);

      // Try to pause without recording
      expect(
        () => platform.pauseRecording(cameraId),
        throwsA(isA<CameraException>()),
      );

      await platform.disposeCamera(cameraId);
    });

    test('front and back camera support', () async {
      final cameras = await platform.getAvailableCameras();

      // Find front camera
      final frontCamera = cameras
          .where((c) => c.lensDirection == LensDirection.front)
          .firstOrNull;
      if (frontCamera != null) {
        final cameraId = await platform.createCamera(
          frontCamera,
          const CameraConfig(resolutionPreset: ResolutionPreset.high),
        );
        await platform.initializeCamera(cameraId);
        await platform.disposeCamera(cameraId);
      }

      // Find back camera
      final backCamera = cameras
          .where((c) => c.lensDirection == LensDirection.back)
          .firstOrNull;
      if (backCamera != null) {
        final cameraId = await platform.createCamera(
          backCamera,
          const CameraConfig(resolutionPreset: ResolutionPreset.high),
        );
        await platform.initializeCamera(cameraId);
        await platform.disposeCamera(cameraId);
      }
    });

    test('recording state events', () async {
      final cameras = await platform.getAvailableCameras();
      final camera = cameras.first;

      final cameraId = await platform.createCamera(
        camera,
        const CameraConfig(resolutionPreset: ResolutionPreset.high),
      );
      await platform.initializeCamera(cameraId);

      // Subscribe to recording state
      final states = <RecordingState>[];
      final subscription = platform.onRecordingStateChanged(cameraId).listen((
        state,
      ) {
        states.add(state);
      });

      // Start recording
      await platform.startRecording(cameraId);
      await Future.delayed(const Duration(milliseconds: 500));

      // Stop recording
      await platform.stopRecording(cameraId);
      await Future.delayed(const Duration(milliseconds: 500));

      // Check states
      expect(states, contains(RecordingState.recording));

      await subscription.cancel();
      await platform.disposeCamera(cameraId);
    });
  });
}
