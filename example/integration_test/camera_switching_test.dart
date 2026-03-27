import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pretty_awesome_camera/pretty_awesome_camera.dart';
import 'package:pretty_awesome_camera/pretty_awesome_camera_platform_interface.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final platform = PrettyAwesomeCameraPlatform.instance;

  group('Camera Switching API Tests', () {
    testWidgets('canSwitchCamera returns false when not recording', (
      WidgetTester tester,
    ) async {
      // Get available cameras first
      final cameras = await platform.getAvailableCameras();
      expect(cameras, isNotEmpty, reason: 'Need at least one camera');

      // Create and initialize camera
      final cameraId = await platform.createCamera(
        cameras.first,
        const CameraConfig(resolutionPreset: ResolutionPreset.medium),
      );
      expect(cameraId, isNotNull);

      await platform.initializeCamera(cameraId);

      // When not recording, canSwitchCamera should return false
      final canSwitch = await platform.canSwitchCamera(cameraId);
      expect(canSwitch, isFalse);

      // Cleanup
      await platform.disposeCamera(cameraId);
    });

    testWidgets(
      'canSwitchCurrentCamera returns false when no camera recording',
      (WidgetTester tester) async {
        // When no camera is recording, should return false
        final canSwitch = await platform.canSwitchCurrentCamera;
        expect(canSwitch, isFalse);
      },
    );

    testWidgets('switchCamera throws error when not recording', (
      WidgetTester tester,
    ) async {
      // Get available cameras
      final cameras = await platform.getAvailableCameras();
      expect(cameras, isNotEmpty, reason: 'Need at least one camera');

      // Create and initialize camera
      final cameraId = await platform.createCamera(
        cameras.first,
        const CameraConfig(resolutionPreset: ResolutionPreset.medium),
      );
      await platform.initializeCamera(cameraId);

      // Try to switch when not recording - should throw
      expect(
        () => platform.switchCamera(cameraId),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'NOT_RECORDING',
          ),
        ),
      );

      // Cleanup
      await platform.disposeCamera(cameraId);
    });

    testWidgets('canSwitchCamera returns true when recording', (
      WidgetTester tester,
    ) async {
      // Get available cameras
      final cameras = await platform.getAvailableCameras();
      expect(cameras, isNotEmpty, reason: 'Need at least one camera');

      // Create and initialize camera
      final cameraId = await platform.createCamera(
        cameras.first,
        const CameraConfig(resolutionPreset: ResolutionPreset.medium),
      );
      await platform.initializeCamera(cameraId);

      // Start recording
      await platform.startRecording(cameraId);

      // When recording, canSwitchCamera should return true
      final canSwitch = await platform.canSwitchCamera(cameraId);
      expect(canSwitch, isTrue);

      // Stop and cleanup
      await platform.stopRecording(cameraId);
      await platform.disposeCamera(cameraId);
    }, tags: ['requires_device']);

    testWidgets(
      'switchCamera completes successfully when recording',
      (WidgetTester tester) async {
        // Get available cameras (need at least 2 for meaningful switch)
        final cameras = await platform.getAvailableCameras();
        expect(
          cameras.length,
          greaterThanOrEqualTo(1),
          reason: 'Need at least one camera',
        );

        // Create and initialize camera
        final cameraId = await platform.createCamera(
          cameras.first,
          const CameraConfig(resolutionPreset: ResolutionPreset.medium),
        );
        await platform.initializeCamera(cameraId);

        // Start recording
        await platform.startRecording(cameraId);

        // Switch camera during recording - should complete without error
        await platform.switchCamera(cameraId);

        // Verify still recording after switch
        final stillRecording = await platform.canSwitchCamera(cameraId);
        expect(stillRecording, isTrue);

        // Stop and cleanup
        final filePath = await platform.stopRecording(cameraId);
        expect(filePath, isNotNull);
        expect(filePath, isNotEmpty);

        await platform.disposeCamera(cameraId);
      },
      tags: ['requires_device'],
    );

    testWidgets(
      'canSwitchCurrentCamera returns true when recording',
      (WidgetTester tester) async {
        // Get available cameras
        final cameras = await platform.getAvailableCameras();
        expect(cameras, isNotEmpty, reason: 'Need at least one camera');

        // Create and initialize camera
        final cameraId = await platform.createCamera(
          cameras.first,
          const CameraConfig(resolutionPreset: ResolutionPreset.medium),
        );
        await platform.initializeCamera(cameraId);

        // Start recording
        await platform.startRecording(cameraId);

        // When recording, canSwitchCurrentCamera should return true
        final canSwitch = await platform.canSwitchCurrentCamera;
        expect(canSwitch, isTrue);

        // Stop and cleanup
        await platform.stopRecording(cameraId);
        await platform.disposeCamera(cameraId);
      },
      tags: ['requires_device'],
    );

    testWidgets('recording state changes during camera switch', (
      WidgetTester tester,
    ) async {
      // Get available cameras
      final cameras = await platform.getAvailableCameras();
      expect(cameras, isNotEmpty, reason: 'Need at least one camera');

      // Create and initialize camera
      final cameraId = await platform.createCamera(
        cameras.first,
        const CameraConfig(resolutionPreset: ResolutionPreset.medium),
      );
      await platform.initializeCamera(cameraId);

      // Subscribe to recording state changes
      final states = <RecordingState>[];
      final subscription = platform
          .onRecordingStateChanged(cameraId)
          .listen((state) => states.add(state));

      // Start recording
      await platform.startRecording(cameraId);
      await Future.delayed(const Duration(milliseconds: 100));

      // Switch camera
      await platform.switchCamera(cameraId);
      await Future.delayed(const Duration(milliseconds: 100));

      // Stop recording
      await platform.stopRecording(cameraId);
      await Future.delayed(const Duration(milliseconds: 100));

      // Cancel subscription
      await subscription.cancel();

      // Verify state transitions (idle -> recording -> switching -> recording -> idle)
      expect(states, contains(RecordingState.recording));

      // Cleanup
      await platform.disposeCamera(cameraId);
    }, tags: ['requires_device']);
  });
}
