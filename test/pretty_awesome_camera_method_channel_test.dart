import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_awesome_camera/pretty_awesome_camera.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelPrettyAwesomeCamera platform =
      MethodChannelPrettyAwesomeCamera();
  const MethodChannel channel = MethodChannel('pretty_awesome_camera');

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
              return {
                'textureId': 42,
                'previewSize': {'width': 1440, 'height': 1080},
              };
            }
            return null;
          });

      final result = await platform.initializeCamera(0);
      expect(result.textureId, 42);
      expect(result.previewSize?.width, 1440);
      expect(result.previewSize?.height, 1080);
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

    test('returns null when null returned', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'stopRecording') {
              return null;
            }
            return null;
          });

      final filePath = await platform.stopRecording(0);
      expect(filePath, isNull);
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

  group('setZoom', () {
    test('sends camera ID and zoom factor', () async {
      MethodCall? capturedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            capturedCall = methodCall;
            if (methodCall.method == 'setZoom') {
              return 2.25;
            }
            return null;
          });

      final appliedZoom = await platform.setZoom(7, 2.5);

      expect(capturedCall?.method, 'setZoom');
      expect(capturedCall?.arguments, {'cameraId': 7, 'zoom': 2.5});
      expect(appliedZoom, 2.25);
    });

    test('throws CameraException on PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'setZoom') {
              throw PlatformException(
                code: 'zoom_error',
                message: 'Failed to zoom',
              );
            }
            return null;
          });

      expect(() => platform.setZoom(0, 2), throwsA(isA<CameraException>()));
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
        'pretty_awesome_camera/recording_state_0',
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            eventChannel,
            MockStreamHandler.inline(
              onListen: (arguments, sink) {
                sink.success('recording');
              },
              onCancel: (arguments) {},
            ),
          );

      final stream = platform.onRecordingStateChanged(0);
      final state = await stream.first;
      expect(state, RecordingState.recording);
    });
  });

  group('onAudioDeviceChanged', () {
    test('returns stream of audio device change events', () async {
      const EventChannel eventChannel = EventChannel(
        'pretty_awesome_camera/audio_device_0',
      );

      final mockEvent = {
        'event': 'route_change',
        'deviceName': 'Apple AirPods',
        'portType': 'BluetoothHFP',
        'isBluetooth': true,
      };

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            eventChannel,
            MockStreamHandler.inline(
              onListen: (arguments, sink) {
                sink.success(mockEvent);
              },
              onCancel: (arguments) {},
            ),
          );

      final stream = platform.onAudioDeviceChanged(0);
      final event = await stream.first;
      expect(event, isA<AudioDeviceChangedEvent>());
      expect(event.event, 'route_change');
      expect(event.deviceName, 'Apple AirPods');
      expect(event.portType, 'BluetoothHFP');
      expect(event.isBluetooth, true);
    });
  });
}
