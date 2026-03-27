import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pretty_awesome_camera/pretty_awesome_camera.dart';
import 'package:pretty_awesome_camera/pretty_awesome_camera_platform_interface.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Android Camera Integration Tests', () {
    late PrettyAwesomeCameraPlatform platform;

    setUp(() {
      platform = PrettyAwesomeCameraPlatform.instance;
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

      // Pause recording
      await platform.pauseRecording(cameraId);

      // Wait a bit
      await Future.delayed(const Duration(milliseconds: 500));

      // Resume recording
      await platform.resumeRecording(cameraId);

      // Wait a bit
      await Future.delayed(const Duration(seconds: 1));

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

    test('error: resume without pause', () async {
      final cameras = await platform.getAvailableCameras();
      final camera = cameras.first;

      final cameraId = await platform.createCamera(
        camera,
        const CameraConfig(resolutionPreset: ResolutionPreset.high),
      );
      await platform.initializeCamera(cameraId);

      // Start recording
      await platform.startRecording(cameraId);

      // Try to resume without pausing
      expect(
        () => platform.resumeRecording(cameraId),
        throwsA(isA<CameraException>()),
      );

      // Cleanup
      await platform.stopRecording(cameraId);
      await platform.disposeCamera(cameraId);
    });

    test('error: start recording twice', () async {
      final cameras = await platform.getAvailableCameras();
      final camera = cameras.first;

      final cameraId = await platform.createCamera(
        camera,
        const CameraConfig(resolutionPreset: ResolutionPreset.high),
      );
      await platform.initializeCamera(cameraId);

      // Start recording
      await platform.startRecording(cameraId);

      // Try to start again
      expect(
        () => platform.startRecording(cameraId),
        throwsA(isA<CameraException>()),
      );

      // Cleanup
      await platform.stopRecording(cameraId);
      await platform.disposeCamera(cameraId);
    });

    test('camera switching', () async {
      final cameras = await platform.getAvailableCameras();

      // Skip if only one camera
      if (cameras.length < 2) {
        return;
      }

      // Test first camera
      final cameraId1 = await platform.createCamera(
        cameras[0],
        const CameraConfig(resolutionPreset: ResolutionPreset.high),
      );
      await platform.initializeCamera(cameraId1);
      await platform.disposeCamera(cameraId1);

      // Test second camera
      final cameraId2 = await platform.createCamera(
        cameras[1],
        const CameraConfig(resolutionPreset: ResolutionPreset.high),
      );
      await platform.initializeCamera(cameraId2);
      await platform.disposeCamera(cameraId2);
    });

    test('different quality settings', () async {
      final cameras = await platform.getAvailableCameras();
      final camera = cameras.first;

      for (final preset in ResolutionPreset.values) {
        final cameraId = await platform.createCamera(
          camera,
          CameraConfig(resolutionPreset: preset),
        );
        await platform.initializeCamera(cameraId);

        // Quick recording test
        await platform.startRecording(cameraId);
        await Future.delayed(const Duration(milliseconds: 500));
        await platform.stopRecording(cameraId);

        await platform.disposeCamera(cameraId);
      }
    });
  });
}
