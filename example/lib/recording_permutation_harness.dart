import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:pretty_awesome_camera/pretty_awesome_camera.dart';

const _harnessResolutionPreset = ResolutionPreset.medium;
const _harnessVideoBitrate = 800000;
const _metadataSuffix = '.pretty_camera_harness.json';

enum RecordingPermutationScenario {
  recordStop,
  pauseResumeTwice,
  flipTwice,
  pauseStop,
  rapidStartStop,
}

extension RecordingPermutationScenarioLabel on RecordingPermutationScenario {
  String get id {
    return switch (this) {
      RecordingPermutationScenario.recordStop => 'record_stop',
      RecordingPermutationScenario.pauseResumeTwice => 'pause_resume_twice',
      RecordingPermutationScenario.flipTwice => 'flip_twice',
      RecordingPermutationScenario.pauseStop => 'pause_stop',
      RecordingPermutationScenario.rapidStartStop => 'rapid_start_stop',
    };
  }

  String get label {
    return switch (this) {
      RecordingPermutationScenario.recordStop => 'Record -> stop',
      RecordingPermutationScenario.pauseResumeTwice =>
        'Record -> pause x2 -> resume -> stop',
      RecordingPermutationScenario.flipTwice => 'Record -> flip x2 -> stop',
      RecordingPermutationScenario.pauseStop => 'Record -> pause -> stop',
      RecordingPermutationScenario.rapidStartStop => 'Rapid start -> stop',
    };
  }

  static RecordingPermutationScenario? fromId(String id) {
    for (final scenario in RecordingPermutationScenario.values) {
      if (scenario.id == id) {
        return scenario;
      }
    }
    return null;
  }
}

class RecordingPermutationResult {
  const RecordingPermutationResult({
    required this.scenario,
    required this.startedAt,
    required this.stoppedAt,
    required this.wallClockDuration,
    required this.pausedDuration,
    required this.expectedDuration,
    required this.operations,
    required this.cameraLens,
    this.requestedResolutionPreset = _harnessResolutionPreset,
    this.targetVideoBitrate = _harnessVideoBitrate,
    this.deviceModel,
    this.isEmulator,
    this.videoPath,
    this.metadataPath,
    this.skippedReason,
    this.error,
  });

  final RecordingPermutationScenario scenario;
  final DateTime startedAt;
  final DateTime stoppedAt;
  final Duration wallClockDuration;
  final Duration pausedDuration;
  final Duration expectedDuration;
  final List<String> operations;
  final LensDirection cameraLens;
  final ResolutionPreset requestedResolutionPreset;
  final int? targetVideoBitrate;
  final String? deviceModel;
  final bool? isEmulator;
  final String? videoPath;
  final String? metadataPath;
  final String? skippedReason;
  final String? error;

  bool get expectsOutput =>
      scenario != RecordingPermutationScenario.rapidStartStop;

  bool get isSuccess =>
      error == null && !isSkipped && (!expectsOutput || videoPath != null);

  bool get isSkipped => skippedReason != null;

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': 1,
      'scenario': scenario.id,
      'startedAt': startedAt.toIso8601String(),
      'stoppedAt': stoppedAt.toIso8601String(),
      'wallClockDurationMs': wallClockDuration.inMilliseconds,
      'pausedDurationMs': pausedDuration.inMilliseconds,
      'expectedDurationMs': expectedDuration.inMilliseconds,
      'operations': operations,
      'cameraLens': cameraLens.name,
      'requestedResolutionPreset': requestedResolutionPreset.name,
      'targetVideoBitrate': targetVideoBitrate,
      'deviceModel': deviceModel,
      'isEmulator': isEmulator,
      'videoPath': videoPath,
      'metadataPath': metadataPath,
      'skippedReason': skippedReason,
      'error': error,
    };
  }
}

class RecordingPermutationHarness {
  RecordingPermutationHarness({
    PrettyAwesomeCameraPlatform? platform,
    this.shortClipDuration = const Duration(milliseconds: 900),
    this.pauseDuration = const Duration(milliseconds: 450),
    this.rapidClipDuration = const Duration(milliseconds: 250),
  }) : _platform = platform ?? PrettyAwesomeCameraPlatform.instance;

  final PrettyAwesomeCameraPlatform _platform;
  final Duration shortClipDuration;
  final Duration pauseDuration;
  final Duration rapidClipDuration;

  Future<List<RecordingPermutationResult>> runAll({
    List<RecordingPermutationScenario> scenarios =
        RecordingPermutationScenario.values,
  }) async {
    final results = <RecordingPermutationResult>[];
    for (final scenario in scenarios) {
      results.add(await run(scenario));
    }
    return results;
  }

  Future<RecordingPermutationResult> run(
    RecordingPermutationScenario scenario,
  ) async {
    final cameras = await _platform.getAvailableCameras();
    if (cameras.isEmpty) {
      return _skippedResult(scenario, 'No cameras available.');
    }

    if (scenario == RecordingPermutationScenario.flipTwice &&
        !_hasFrontAndBack(cameras)) {
      return _skippedResult(
        scenario,
        'Front and back cameras are required for flip permutation.',
      );
    }

    final camera = _preferredCamera(cameras);
    final operations = <String>[];
    int? cameraId;
    var startedAt = DateTime.now();
    var stoppedAt = startedAt;
    var pausedDuration = Duration.zero;
    String? videoPath;

    try {
      cameraId = await _platform.createCamera(
        camera,
        const CameraConfig(
          resolutionPreset: _harnessResolutionPreset,
          videoBitrate: _harnessVideoBitrate,
        ),
      );
      operations.add('createCamera:${camera.lensDirection.name}');

      await _platform.initializeCamera(cameraId);
      operations.add('initializeCamera');

      await _platform.startRecording(cameraId);
      operations.add('startRecording');
      startedAt = DateTime.now();

      switch (scenario) {
        case RecordingPermutationScenario.recordStop:
          await Future<void>.delayed(shortClipDuration);
        case RecordingPermutationScenario.pauseResumeTwice:
          await Future<void>.delayed(shortClipDuration);
          pausedDuration += await _pauseAndResume(cameraId, operations);
          await Future<void>.delayed(shortClipDuration);
          pausedDuration += await _pauseAndResume(cameraId, operations);
          await Future<void>.delayed(shortClipDuration);
        case RecordingPermutationScenario.flipTwice:
          await Future<void>.delayed(shortClipDuration);
          await _platform.switchCamera(cameraId);
          operations.add('switchCamera');
          await Future<void>.delayed(shortClipDuration);
          await _platform.switchCamera(cameraId);
          operations.add('switchCamera');
          await Future<void>.delayed(shortClipDuration);
        case RecordingPermutationScenario.pauseStop:
          await Future<void>.delayed(shortClipDuration);
          final pauseStartedAt = DateTime.now();
          await _platform.pauseRecording(cameraId);
          operations.add('pauseRecording');
          await Future<void>.delayed(pauseDuration);
          pausedDuration += DateTime.now().difference(pauseStartedAt);
        case RecordingPermutationScenario.rapidStartStop:
          await Future<void>.delayed(rapidClipDuration);
      }

      stoppedAt = DateTime.now();
      videoPath = await _platform.stopRecording(cameraId);
      operations.add('stopRecording');

      final deviceMetadata = await _deviceMetadata();
      final result = RecordingPermutationResult(
        scenario: scenario,
        startedAt: startedAt,
        stoppedAt: stoppedAt,
        wallClockDuration: stoppedAt.difference(startedAt),
        pausedDuration: pausedDuration,
        expectedDuration: stoppedAt.difference(startedAt) - pausedDuration,
        operations: operations,
        cameraLens: camera.lensDirection,
        deviceModel: deviceMetadata.deviceModel,
        isEmulator: deviceMetadata.isEmulator,
        videoPath: videoPath,
      );
      return _writeMetadata(result);
    } catch (error) {
      stoppedAt = DateTime.now();
      if (cameraId != null) {
        await _bestEffortStop(cameraId);
      }
      return RecordingPermutationResult(
        scenario: scenario,
        startedAt: startedAt,
        stoppedAt: stoppedAt,
        wallClockDuration: stoppedAt.difference(startedAt),
        pausedDuration: pausedDuration,
        expectedDuration: stoppedAt.difference(startedAt) - pausedDuration,
        operations: operations,
        cameraLens: camera.lensDirection,
        videoPath: videoPath,
        error: error.toString(),
      );
    } finally {
      if (cameraId != null) {
        await _bestEffortDispose(cameraId);
      }
    }
  }

  Future<Duration> _pauseAndResume(
    int cameraId,
    List<String> operations,
  ) async {
    final pauseStartedAt = DateTime.now();
    await _platform.pauseRecording(cameraId);
    operations.add('pauseRecording');
    await Future<void>.delayed(pauseDuration);
    final pausedDuration = DateTime.now().difference(pauseStartedAt);
    await _platform.resumeRecording(cameraId);
    operations.add('resumeRecording');
    return pausedDuration;
  }

  Future<RecordingPermutationResult> _writeMetadata(
    RecordingPermutationResult result,
  ) async {
    final videoPath = result.videoPath;
    if (videoPath == null || videoPath.isEmpty) {
      if (!result.expectsOutput) {
        final outputDirectory = await _harnessOutputDirectory();
        final metadataPath =
            '${outputDirectory.path}/${result.scenario.id}_${DateTime.now().millisecondsSinceEpoch}$_metadataSuffix';
        final withPath = RecordingPermutationResult(
          scenario: result.scenario,
          startedAt: result.startedAt,
          stoppedAt: result.stoppedAt,
          wallClockDuration: result.wallClockDuration,
          pausedDuration: result.pausedDuration,
          expectedDuration: result.expectedDuration,
          operations: result.operations,
          cameraLens: result.cameraLens,
          requestedResolutionPreset: result.requestedResolutionPreset,
          targetVideoBitrate: result.targetVideoBitrate,
          deviceModel: result.deviceModel,
          isEmulator: result.isEmulator,
          metadataPath: metadataPath,
        );
        await File(metadataPath).writeAsString(
          const JsonEncoder.withIndent('  ').convert(withPath.toJson()),
        );
        return withPath;
      }
      return RecordingPermutationResult(
        scenario: result.scenario,
        startedAt: result.startedAt,
        stoppedAt: result.stoppedAt,
        wallClockDuration: result.wallClockDuration,
        pausedDuration: result.pausedDuration,
        expectedDuration: result.expectedDuration,
        operations: result.operations,
        cameraLens: result.cameraLens,
        deviceModel: result.deviceModel,
        isEmulator: result.isEmulator,
        error: 'stopRecording returned no output path.',
      );
    }

    final metadataPath = '$videoPath.pretty_camera_harness.json';
    final withPath = RecordingPermutationResult(
      scenario: result.scenario,
      startedAt: result.startedAt,
      stoppedAt: result.stoppedAt,
      wallClockDuration: result.wallClockDuration,
      pausedDuration: result.pausedDuration,
      expectedDuration: result.expectedDuration,
      operations: result.operations,
      cameraLens: result.cameraLens,
      requestedResolutionPreset: result.requestedResolutionPreset,
      targetVideoBitrate: result.targetVideoBitrate,
      deviceModel: result.deviceModel,
      isEmulator: result.isEmulator,
      videoPath: videoPath,
      metadataPath: metadataPath,
    );
    await File(metadataPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(withPath.toJson()),
    );
    return withPath;
  }

  RecordingPermutationResult _skippedResult(
    RecordingPermutationScenario scenario,
    String reason,
  ) {
    final now = DateTime.now();
    return RecordingPermutationResult(
      scenario: scenario,
      startedAt: now,
      stoppedAt: now,
      wallClockDuration: Duration.zero,
      pausedDuration: Duration.zero,
      expectedDuration: Duration.zero,
      operations: const [],
      cameraLens: LensDirection.external,
      skippedReason: reason,
    );
  }

  CameraDescription _preferredCamera(List<CameraDescription> cameras) {
    return cameras.firstWhere(
      (camera) => camera.lensDirection == LensDirection.front,
      orElse: () => cameras.first,
    );
  }

  bool _hasFrontAndBack(List<CameraDescription> cameras) {
    final hasFront = cameras.any(
      (camera) => camera.lensDirection == LensDirection.front,
    );
    final hasBack = cameras.any(
      (camera) => camera.lensDirection == LensDirection.back,
    );
    return hasFront && hasBack;
  }

  Future<void> _bestEffortStop(int cameraId) async {
    try {
      await _platform.stopRecording(cameraId);
    } catch (_) {}
  }

  Future<void> _bestEffortDispose(int cameraId) async {
    try {
      await _platform.disposeCamera(cameraId);
    } catch (_) {}
  }

  Future<Directory> _harnessOutputDirectory() async {
    final temp = Directory.systemTemp;
    final output = temp.path.endsWith('/code_cache')
        ? Directory('${temp.parent.path}/cache')
        : temp;
    await output.create(recursive: true);
    return output;
  }

  Future<_HarnessDeviceMetadata> _deviceMetadata() async {
    if (!Platform.isAndroid) {
      return const _HarnessDeviceMetadata();
    }
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return _HarnessDeviceMetadata(
        deviceModel: info.model,
        isEmulator: !info.isPhysicalDevice,
      );
    } catch (_) {
      return const _HarnessDeviceMetadata();
    }
  }
}

class _HarnessDeviceMetadata {
  const _HarnessDeviceMetadata({this.deviceModel, this.isEmulator});

  final String? deviceModel;
  final bool? isEmulator;
}
