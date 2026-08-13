import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_awesome_camera/pretty_awesome_camera.dart';

class FakeCameraPlatform extends PrettyAwesomeCameraPlatform {
  final StreamController<RecordingState> recordingStateController =
      StreamController<RecordingState>.broadcast();
  final StreamController<AudioDeviceChangedEvent> audioDeviceChangedController =
      StreamController<AudioDeviceChangedEvent>.broadcast();
  final StreamController<AudioLevelEvent> audioLevelController =
      StreamController<AudioLevelEvent>.broadcast();
  List<CameraDescription> availableCameras = [];
  int getAvailableCamerasCallCount = 0;
  final List<SalvagePolicy> startRecordingCalls = <SalvagePolicy>[];

  int nextCameraId = 1;
  int nextTextureId = 101;
  int? lastRecordingSettingsCameraId;
  int? lastZoomCameraId;
  double? lastZoomFactor;
  String stopRecordingPath = '/tmp/test.mov';
  CameraPreviewSize previewSize = const CameraPreviewSize(
    width: 1440,
    height: 1080,
  );

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
  Future<CameraInitializationResult> initializeCamera(int cameraId) async {
    return CameraInitializationResult(
      textureId: nextTextureId++,
      previewSize: previewSize,
    );
  }

  Map<String, Object?>? startInfo = const {
    'audioPortType': 'MicrophoneBuiltIn',
    'isBluetoothInput': false,
  };

  @override
  Future<Map<String, Object?>?> startRecording(
    int cameraId, {
    SalvagePolicy salvagePolicy = SalvagePolicy.off,
  }) async {
    startRecordingCalls.add(salvagePolicy);
    return startInfo;
  }

  @override
  Future<Map<String, Object?>> getRecordingSettings(int cameraId) async {
    lastRecordingSettingsCameraId = cameraId;
    return {
      'requested_bitrate': 2500000,
      'resolved_resolution': '1280x720',
      'capture_preset': 'high',
    };
  }

  @override
  Future<String> stopRecording(int cameraId) async => stopRecordingPath;

  @override
  Future<void> pauseRecording(int cameraId) async {}

  @override
  Future<void> resumeRecording(int cameraId) async {}

  @override
  Future<double> setZoom(int cameraId, double zoomFactor) async {
    lastZoomCameraId = cameraId;
    lastZoomFactor = zoomFactor;
    return zoomFactor;
  }

  @override
  Future<void> disposeCamera(int cameraId) async {}

  @override
  Stream<RecordingState> onRecordingStateChanged(int cameraId) {
    return recordingStateController.stream;
  }

  @override
  Stream<AudioDeviceChangedEvent> onAudioDeviceChanged(int cameraId) {
    return audioDeviceChangedController.stream;
  }

  @override
  Stream<AudioLevelEvent> onAudioLevel(int cameraId) {
    return audioLevelController.stream;
  }

  @override
  Future<bool> canSwitchCamera(int cameraId) async => true;

  @override
  Future<CameraInitializationResult> switchCamera(int cameraId) async {
    return CameraInitializationResult(
      textureId: nextTextureId++,
      previewSize: previewSize,
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

  // --- salvage ---
  CameraException? startSegmentError;
  final List<SalvagePolicy> startSegmentCalls = <SalvagePolicy>[];
  List<SegmentSealOutcome> drainedOutcomes = const <SegmentSealOutcome>[];
  int consumeSealedSegmentsCallCount = 0;
  RecordingCapabilities capabilities = const RecordingCapabilities(
    supportsSegmentSeal: true,
    supportsConcat: true,
  );

  @override
  Future<Map<String, Object?>?> startRecordingSegment(
    int cameraId, {
    SalvagePolicy salvagePolicy = SalvagePolicy.off,
  }) async {
    startSegmentCalls.add(salvagePolicy);
    final error = startSegmentError;
    if (error != null) {
      throw error;
    }
    return startInfo;
  }

  @override
  Future<SegmentSealOutcome> sealRecordingSegment(
    int cameraId, {
    required String reason,
  }) async {
    return SegmentSealOutcome(
      ok: true,
      reason: reason,
      writerStatus: 'writing',
      sealLatency: const Duration(milliseconds: 12),
      segment: RecordedSegment(
        path: '/tmp/segment.mov',
        duration: const Duration(seconds: 5),
        reason: reason,
      ),
    );
  }

  @override
  Future<List<SegmentSealOutcome>> consumeSealedSegments(int cameraId) async {
    consumeSealedSegmentsCallCount++;
    final outcomes = drainedOutcomes;
    drainedOutcomes = const <SegmentSealOutcome>[];
    return outcomes;
  }

  @override
  Future<WriterFailureReport?> consumeWriterFailure(int cameraId) async => null;

  @override
  Future<SegmentConcatResult> concatenateSegments({
    required List<String> segmentPaths,
    required String outputPath,
  }) async {
    return SegmentConcatResult(
      path: outputPath,
      duration: const Duration(seconds: 10),
    );
  }

  @override
  Future<RecordingCapabilities> getRecordingCapabilities() async =>
      capabilities;
}

/// Builds the name-only notification native emits for salvage events.
///
/// Deliberately constructed the way the real event model does — with only the
/// four keys it preserves — so a test cannot accidentally rely on a payload
/// that would be dropped in production.
AudioDeviceChangedEvent _salvageEvent(String name) => AudioDeviceChangedEvent(
  event: name,
  deviceName: 'iPhone Microphone',
  portType: 'MicrophoneBuiltIn',
  isBluetooth: false,
);

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
    await platform.audioDeviceChangedController.close();
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

  test('prewarmUp transitions to ready with ids', () async {
    final controller = CameraController(
      description: description,
      platform: platform,
    );

    await controller.prewarmUp();

    expect(controller.value, isA<CameraReadyState>());
    expect(controller.cameraId, isNotNull);
    expect(controller.textureId, isNotNull);
    expect(controller.previewSize, equals(platform.previewSize));
    expect(controller.previewAspectRatio, closeTo(0.75, 0.0001));
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

  test(
    'create falls back to front camera when config lensDirection is null',
    () async {
      final controller = await CameraController.create(
        config: const CameraConfig(lensDirection: null),
        platform: platform,
      );

      expect(controller.description.lensDirection, LensDirection.front);
      expect(controller.value, isA<CameraUninitializedState>());
    },
  );

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

  test('switchCamera updates selected camera before prewarm', () async {
    final controller = CameraController(
      description: description,
      availableCameras: platform.availableCameras,
      platform: platform,
    );

    await controller.switchCamera();

    expect(controller.value, isA<CameraUninitializedState>());
    expect(controller.description.lensDirection, LensDirection.front);
    expect(controller.textureId, isNull);
  });

  test('recording lifecycle transitions are enforced', () async {
    final controller = CameraController(
      description: description,
      platform: platform,
    );

    await controller.prewarmUp();
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

    await controller.prewarmUp();
    final initialTextureId = controller.textureId;
    await controller.startRecording();
    await controller.switchCamera();

    expect(controller.value, isA<CameraRecordingState>());
    expect(controller.textureId, isNot(initialTextureId));
    expect(controller.description.lensDirection, LensDirection.front);
  });

  test('switchCamera reconfigures when not recording', () async {
    final controller = CameraController(
      description: description,
      availableCameras: platform.availableCameras,
      platform: platform,
    );

    await controller.prewarmUp();
    await controller.switchCamera();

    expect(controller.value, isA<CameraReadyState>());
    expect(controller.description.lensDirection, LensDirection.front);
  });

  test('switchToNextCamera remains an alias for switchCamera', () async {
    final controller = CameraController(
      description: description,
      availableCameras: platform.availableCameras,
      platform: platform,
    );

    await controller.prewarmUp();
    await controller.switchToNextCamera();

    expect(controller.value, isA<CameraReadyState>());
    expect(controller.description.lensDirection, LensDirection.front);
  });

  test('setZoom delegates to the active platform camera', () async {
    final controller = CameraController(
      description: description,
      platform: platform,
    );

    await controller.prewarmUp();
    final appliedZoom = await controller.setZoom(2.5);

    expect(platform.lastZoomCameraId, controller.cameraId);
    expect(platform.lastZoomFactor, 2.5);
    expect(appliedZoom, 2.5);
  });

  test(
    'getRecordingSettings delegates to the active platform camera',
    () async {
      final controller = CameraController(
        description: description,
        platform: platform,
      );

      await controller.prewarmUp();
      final settings = await controller.getRecordingSettings();

      expect(platform.lastRecordingSettingsCameraId, controller.cameraId);
      expect(settings, {
        'requested_bitrate': 2500000,
        'resolved_resolution': '1280x720',
        'capture_preset': 'high',
      });
    },
  );

  test('setZoom after dispose throws disposed before platform call', () async {
    final controller = CameraController(
      description: description,
      platform: platform,
    );

    await controller.prewarmUp();
    controller.dispose();

    expect(
      () => controller.setZoom(2.5),
      throwsA(isA<CameraException>().having((e) => e.code, 'code', 'disposed')),
    );
    expect(platform.lastZoomCameraId, isNull);
    expect(platform.lastZoomFactor, isNull);
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

    await controller.prewarmUp();
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

  test('audio device stream errors are swallowed after prewarm', () async {
    final controller = CameraController(
      description: description,
      platform: platform,
    );
    final uncaughtErrors = <Object>[];

    await runZonedGuarded<Future<void>>(
      () async {
        await controller.prewarmUp();
        platform.audioDeviceChangedController.addError(
          const CameraException(
            code: 'stream_error',
            message: 'Missing audio EventChannel',
          ),
        );
        await Future<void>.delayed(Duration.zero);
      },
      (Object error, StackTrace stackTrace) {
        uncaughtErrors.add(error);
      },
    );

    expect(uncaughtErrors, isEmpty);
    expect(controller.value, isA<CameraReadyState>());
  });

  test('dispose transitions to disposed state', () async {
    final controller = CameraController(
      description: description,
      platform: platform,
    );

    await controller.prewarmUp();
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

  group('segment salvage', () {
    Future<CameraController> recordingController({
      SalvagePolicy policy = SalvagePolicy.seal,
    }) async {
      final controller = CameraController(
        description: description,
        platform: platform,
      );
      addTearDown(controller.dispose);
      await controller.prewarmUp();
      await controller.startRecording(salvagePolicy: policy);
      return controller;
    }

    /// Delivers a native notification and lets the stream drain.
    Future<void> emit(String name) async {
      platform.audioDeviceChangedController.add(_salvageEvent(name));
      await Future<void>.delayed(Duration.zero);
    }

    test('the salvage policy reaches the platform on start', () async {
      final controller = CameraController(
        description: description,
        platform: platform,
      );
      addTearDown(controller.dispose);
      await controller.prewarmUp();

      await controller.startRecording(
        salvagePolicy: SalvagePolicy.sealInterruptOnly,
      );

      expect(platform.startRecordingCalls, [SalvagePolicy.sealInterruptOnly]);
    });

    test('the policy defaults to off, so an upgrade changes nothing', () async {
      final controller = CameraController(
        description: description,
        platform: platform,
      );
      addTearDown(controller.dispose);
      await controller.prewarmUp();

      await controller.startRecording();

      expect(platform.startRecordingCalls, [SalvagePolicy.off]);
    });

    test('no listener ever observes the seal while the controller still '
        'claims to be recording', () async {
      final controller = await recordingController();
      expect(controller.value, isA<CameraRecordingState>());

      // A listener that reacted to the seal while the controller still said
      // "recording" would have every restart rejected by the startRecording
      // guard.
      //
      // Honest caveat, established by mutation-testing this test: swapping the
      // two lines in `_handleAudioDeviceEvent` does NOT make it fail. The
      // ordering is guaranteed structurally rather than by discipline —
      // ValueNotifier notifies synchronously from inside the transition, and a
      // broadcast stream delivers in a later microtask, so both listener kinds
      // see the new state either way. This test pins the observable contract;
      // it is not a regression guard for statement order.
      final notifierObserved = <String>[];
      void onNotify() => notifierObserved.add(controller.value.name);
      controller.addListener(onNotify);
      addTearDown(() => controller.removeListener(onNotify));

      final streamObserved = <String>[];
      controller.onAudioDeviceChanged.listen((event) {
        streamObserved.add('${event.event}:${controller.value.name}');
      });

      await emit(recordingSegmentSealedEvent);

      expect(notifierObserved, ['segmentSealed']);
      expect(streamObserved, ['recordingSegmentSealed:segmentSealed']);
      expect(controller.value, isA<CameraSegmentSealedState>());
      expect(controller.sealedSegmentCount, 1);
    });

    test('a failed seal does not claim a segment exists', () async {
      final controller = await recordingController();

      await emit(recordingSegmentSealFailedEvent);

      // The recording is over either way, so restarting must be legal — but
      // nothing was salvaged, so the count must not move.
      expect(controller.value, isA<CameraReadyState>());
      expect(controller.sealedSegmentCount, 0);
    });

    test('writer failure with prior segments keeps them reachable', () async {
      final controller = await recordingController();
      await emit(recordingSegmentSealedEvent);
      await controller.startRecordingSegment(salvagePolicy: SalvagePolicy.seal);
      expect(controller.value, isA<CameraRecordingState>());

      await emit(recordingWriterFailedEvent);

      expect(controller.value, isA<CameraSegmentSealedState>());
      expect(controller.sealedSegmentCount, 1);
    });

    test('writer failure with nothing salvaged lands on ready', () async {
      final controller = await recordingController();

      await emit(recordingWriterFailedEvent);

      expect(controller.value, isA<CameraReadyState>());
      expect(controller.sealedSegmentCount, 0);
    });

    test('both restart choices are legal from a sealed state', () async {
      final controller = await recordingController();
      await emit(recordingSegmentSealedEvent);

      // Continue appends.
      await controller.startRecordingSegment(salvagePolicy: SalvagePolicy.seal);
      expect(controller.value, isA<CameraRecordingState>());
      expect(controller.sealedSegmentCount, 1);

      await emit(recordingSegmentSealedEvent);
      expect(controller.sealedSegmentCount, 2);

      // Start Over supersedes.
      await controller.startRecording(salvagePolicy: SalvagePolicy.seal);
      expect(controller.value, isA<CameraRecordingState>());
      expect(controller.sealedSegmentCount, 0);
    });

    test('a failed continue leaves the other choices live', () async {
      final controller = await recordingController();
      await emit(recordingSegmentSealedEvent);

      platform.startSegmentError = CameraException(
        code: 'SEGMENT_START_ERROR',
        message: 'audio session still seized',
      );

      await expectLater(
        controller.startRecordingSegment(salvagePolicy: SalvagePolicy.seal),
        throwsA(isA<CameraException>()),
      );

      // Crucially the state carries no error. `CameraBuilderState` turns any
      // error-carrying state into an error state whose only action is
      // reconfigure, which would replace three live choices with a dead end.
      final state = controller.value;
      expect(state, isA<CameraSegmentSealedState>());
      expect(state.error, isNull);
      expect((state as CameraSegmentSealedState).sealedSegmentCount, 1);

      final builderState = CameraBuilderState.fromController(controller, state);
      expect(builderState, isA<CameraBuilderSegmentSealedState>());
    });

    test(
      'an idle recording-state event does not wipe a sealed session',
      () async {
        final controller = await recordingController();
        await emit(recordingSegmentSealedEvent);

        // Both platforms emit exactly one `idle` when this stream is subscribed.
        platform.recordingStateController.add(RecordingState.idle);
        await Future<void>.delayed(Duration.zero);

        expect(controller.value, isA<CameraSegmentSealedState>());
      },
    );

    test(
      'draining is destructive, so a repeat notification yields nothing',
      () async {
        final controller = await recordingController();
        platform.drainedOutcomes = <SegmentSealOutcome>[
          SegmentSealOutcome(
            ok: true,
            reason: SegmentSealReasons.audioInterruption,
            writerStatus: 'writing',
            sealLatency: const Duration(milliseconds: 8),
            segment: RecordedSegment(
              path: '/tmp/a.mov',
              duration: const Duration(seconds: 3),
              reason: SegmentSealReasons.audioInterruption,
            ),
          ),
        ];

        expect((await controller.consumeSealedSegments()).length, 1);
        expect(await controller.consumeSealedSegments(), isEmpty);
        expect(platform.consumeSealedSegmentsCallCount, 2);
      },
    );

    test(
      'a seal-capable but concat-incapable build is not salvage-capable',
      () async {
        final controller = CameraController(
          description: description,
          platform: platform,
        );
        addTearDown(controller.dispose);
        await controller.prewarmUp();

        platform.capabilities = const RecordingCapabilities(
          supportsSegmentSeal: true,
          supportsConcat: false,
        );

        final capabilities = await controller.getRecordingCapabilities();

        // Offering to continue a recording that can never be reassembled is
        // worse than offering nothing.
        expect(capabilities.supportsSalvage, isFalse);
      },
    );
  });
}
