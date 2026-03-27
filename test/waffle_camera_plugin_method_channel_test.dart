import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waffle_camera_plugin/waffle_camera_plugin_method_channel.dart';
import 'package:waffle_camera_plugin/src/camera_config.dart';
import 'package:waffle_camera_plugin/src/camera_description.dart';
import 'package:waffle_camera_plugin/src/camera_exception.dart';
import 'package:waffle_camera_plugin/src/recording_state.dart';
import 'package:waffle_camera_plugin/src/resolution_preset.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelWaffleCameraPlugin platform = MethodChannelWaffleCameraPlugin();
  const MethodChannel channel = MethodChannel('waffle_camera_plugin');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          return '42';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });

  group('getAvailableCameras', () {
    test('returns list of cameras', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'getAvailableCameras') {
              return [
                {
                  'name': 'Back Camera',
                  'lensDirection': 'back',
                  'sensorOrientation': 90,
                },
                {
                  'name': 'Front Camera',
                  'lensDirection': 'front',
                  'sensorOrientation': 270,
                },
              ];
            }
            return null;
          });

      final cameras = await platform.getAvailableCameras();
      expect(cameras.length, 2);
      expect(cameras[0].name, 'Back Camera');
      expect(cameras[0].lensDirection, LensDirection.back);
      expect(cameras[0].sensorOrientation, 90);
      expect(cameras[1].name, 'Front Camera');
      expect(cameras[1].lensDirection, LensDirection.front);
      expect(cameras[1].sensorOrientation, 270);
    });

    test('returns empty list when null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'getAvailableCameras') {
              return null;
            }
            return null;
          });

      final cameras = await platform.getAvailableCameras();
      expect(cameras.isEmpty, true);
    });

    test('throws CameraException on PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'getAvailableCameras') {
              throw PlatformException(
                code: 'camera_error',
                message: 'Camera not available',
              );
            }
            return null;
          });

      expect(
        () => platform.getAvailableCameras(),
        throwsA(
          isA<CameraException>()
              .having((e) => e.code, 'code', 'camera_error')
              .having((e) => e.message, 'message', 'Camera not available'),
        ),
      );
    });
  });

  group('createCamera', () {
    test('returns camera ID', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'createCamera') {
              return 0;
            }
            return null;
          });

      final camera = CameraDescription(
        name: 'Back Camera',
        lensDirection: LensDirection.back,
        sensorOrientation: 90,
      );
      final cameraId = await platform.createCamera(
        camera,
        const CameraConfig(resolutionPreset: ResolutionPreset.high),
      );
      expect(cameraId, 0);
    });

    test('throws CameraException when null returned', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'createCamera') {
              return null;
            }
            return null;
          });

      final camera = CameraDescription(
        name: 'Back Camera',
        lensDirection: LensDirection.back,
        sensorOrientation: 90,
      );
      expect(
        () => platform.createCamera(
          camera,
          const CameraConfig(resolutionPreset: ResolutionPreset.high),
        ),
        throwsA(
          isA<CameraException>().having(
            (e) => e.code,
            'code',
            'invalid_response',
          ),
        ),
      );
    });

    test('throws CameraException on PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'createCamera') {
              throw PlatformException(
                code: 'create_error',
                message: 'Failed to create camera',
              );
            }
            return null;
          });

      final camera = CameraDescription(
        name: 'Back Camera',
        lensDirection: LensDirection.back,
        sensorOrientation: 90,
      );
      expect(
        () => platform.createCamera(
          camera,
          const CameraConfig(resolutionPreset: ResolutionPreset.high),
        ),
        throwsA(
          isA<CameraException>().having((e) => e.code, 'code', 'create_error'),
        ),
      );
    });
  });

  group('initializeCamera', () {
    test('completes successfully', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'initializeCamera') {
              return 42; // texture ID
            }
            return null;
          });

      expect(await platform.initializeCamera(0), 42);
    });

    test('throws CameraException on PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'initializeCamera') {
              throw PlatformException(
                code: 'init_error',
                message: 'Failed to initialize',
              );
            }
            return null;
          });

      expect(
        () => platform.initializeCamera(0),
        throwsA(isA<CameraException>()),
      );
    });
  });

  group('startRecording', () {
    test('completes successfully', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'startRecording') {
              return null;
            }
            return null;
          });

      expect(() => platform.startRecording(0), returnsNormally);
    });

    test('throws CameraException on PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'startRecording') {
              throw PlatformException(
                code: 'recording_error',
                message: 'Failed to start recording',
              );
            }
            return null;
          });

      expect(() => platform.startRecording(0), throwsA(isA<CameraException>()));
    });
  });

  group('stopRecording', () {
    test('returns file path', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'stopRecording') {
              return '/path/to/video.mp4';
            }
            return null;
          });

      final filePath = await platform.stopRecording(0);
      expect(filePath, '/path/to/video.mp4');
    });

    test('throws CameraException when null returned', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'stopRecording') {
              return null;
            }
            return null;
          });

      expect(() => platform.stopRecording(0), throwsA(isA<CameraException>()));
    });

    test('throws CameraException on PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'stopRecording') {
              throw PlatformException(
                code: 'stop_error',
                message: 'Failed to stop recording',
              );
            }
            return null;
          });

      expect(() => platform.stopRecording(0), throwsA(isA<CameraException>()));
    });
  });

  group('pauseRecording', () {
    test('completes successfully', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'pauseRecording') {
              return null;
            }
            return null;
          });

      expect(() => platform.pauseRecording(0), returnsNormally);
    });

    test('throws CameraException on PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'pauseRecording') {
              throw PlatformException(
                code: 'pause_error',
                message: 'Failed to pause recording',
              );
            }
            return null;
          });

      expect(() => platform.pauseRecording(0), throwsA(isA<CameraException>()));
    });
  });

  group('resumeRecording', () {
    test('completes successfully', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'resumeRecording') {
              return null;
            }
            return null;
          });

      expect(() => platform.resumeRecording(0), returnsNormally);
    });

    test('throws CameraException on PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'resumeRecording') {
              throw PlatformException(
                code: 'resume_error',
                message: 'Failed to resume recording',
              );
            }
            return null;
          });

      expect(
        () => platform.resumeRecording(0),
        throwsA(isA<CameraException>()),
      );
    });
  });

  group('disposeCamera', () {
    test('completes successfully', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'disposeCamera') {
              return null;
            }
            return null;
          });

      expect(() => platform.disposeCamera(0), returnsNormally);
    });

    test('throws CameraException on PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'disposeCamera') {
              throw PlatformException(
                code: 'dispose_error',
                message: 'Failed to dispose camera',
              );
            }
            return null;
          });

      expect(() => platform.disposeCamera(0), throwsA(isA<CameraException>()));
    });
  });

  group('onRecordingStateChanged', () {
    test('returns stream of RecordingState', () async {
      const EventChannel eventChannel = EventChannel(
        'waffle_camera_plugin/recording_state_0',
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            eventChannel,
            MockStreamHandler.inline(
              onListen: (arguments, sink) {
                sink.success('recording');
                return null;
              },
              onCancel: (arguments) {
                return null;
              },
            ),
          );

      final stream = platform.onRecordingStateChanged(0);
      final state = await stream.first;
      expect(state, RecordingState.recording);
    });
  });
}
