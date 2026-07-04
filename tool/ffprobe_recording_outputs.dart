import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const _metadataSuffix = '.pretty_camera_harness.json';
const _durationToleranceMs = 500;
const _bitrateToleranceRatio = 0.25;
const _resolutionToleranceRatio = 0.25;
const _presetShortSide = {
  'low': 240,
  'medium': 480,
  'high': 720,
  'veryHigh': 1080,
  'max': 2160,
};

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/ffprobe_recording_outputs.dart <metadata-file-or-directory> [...]',
    );
    exitCode = 64;
    return;
  }

  final metadataFiles = <File>[];
  for (final arg in args) {
    final entityType = await FileSystemEntity.type(arg);
    if (entityType == FileSystemEntityType.directory) {
      await for (final entity in Directory(arg).list(recursive: true)) {
        if (entity is File && entity.path.endsWith(_metadataSuffix)) {
          metadataFiles.add(entity);
        }
      }
    } else if (entityType == FileSystemEntityType.file) {
      final file = File(arg);
      if (file.path.endsWith(_metadataSuffix)) {
        metadataFiles.add(file);
      }
    }
  }

  if (metadataFiles.isEmpty) {
    stderr.writeln('No $_metadataSuffix files found.');
    exitCode = 1;
    return;
  }

  final failures = <String>[];
  for (final metadataFile in metadataFiles) {
    try {
      final result = await _validateRecording(metadataFile);
      stdout.writeln(
        'PASS ${result.scenario}: ${result.video.path} '
        'duration=${result.durationMs}ms expected=${result.expectedMs}ms '
        'video=${result.videoWidth}x${result.videoHeight} '
        'bitrate=${result.bitrate ?? 'unknown'}bps',
      );
    } catch (error) {
      failures.add('${metadataFile.path}: $error');
    }
  }

  if (failures.isNotEmpty) {
    stderr.writeln('ffprobe validation failed:');
    for (final failure in failures) {
      stderr.writeln('- $failure');
    }
    exitCode = 1;
  }
}

Future<_ValidationResult> _validateRecording(File metadataFile) async {
  final metadata = jsonDecode(await metadataFile.readAsString()) as Map;
  final scenario = metadata['scenario'] as String? ?? 'unknown';
  if (metadata['skippedReason'] != null) {
    throw StateError(
      'Scenario $scenario was skipped: ${metadata['skippedReason']}',
    );
  }
  if (metadata['error'] != null) {
    throw StateError(
      'Scenario $scenario recorded an error: ${metadata['error']}',
    );
  }

  final expectedMs = (metadata['expectedDurationMs'] as num?)?.round();
  if (expectedMs == null || expectedMs <= 0) {
    throw StateError('Scenario $scenario has invalid expectedDurationMs.');
  }

  final video = await _resolveVideoFile(metadataFile, metadata);
  if (!await video.exists()) {
    throw StateError('Video file not found: ${video.path}');
  }

  final probe = await _ffprobeJson([
    '-show_format',
    '-show_streams',
    '-show_entries',
    'format=duration,bit_rate:stream=index,codec_type,width,height,bit_rate',
    video.path,
  ]);
  final streams = (probe['streams'] as List? ?? const []).cast<Map>();
  final videoStreams = streams
      .where((stream) => stream['codec_type'] == 'video')
      .toList(growable: false);
  final videoTracks = videoStreams.length;
  final audioTracks = streams
      .where((stream) => stream['codec_type'] == 'audio')
      .length;

  if (videoTracks != 1 || audioTracks != 1) {
    throw StateError(
      'Expected exactly 1 video and 1 audio track, got video=$videoTracks audio=$audioTracks.',
    );
  }

  final videoStream = videoStreams.single;
  final videoWidth = (videoStream['width'] as num?)?.toInt();
  final videoHeight = (videoStream['height'] as num?)?.toInt();
  if (videoWidth == null || videoHeight == null) {
    throw StateError('ffprobe did not report video dimensions.');
  }
  _assertExpectedResolution(metadata, videoWidth, videoHeight);

  final format = probe['format'] as Map? ?? const {};
  final durationSeconds = double.tryParse('${format['duration']}');
  if (durationSeconds == null || durationSeconds <= 0) {
    throw StateError('ffprobe did not report a positive duration.');
  }
  final durationMs = (durationSeconds * 1000).round();
  final durationDelta = (durationMs - expectedMs).abs();
  final effectiveToleranceMs = math.min(_durationToleranceMs, expectedMs ~/ 2);
  if (durationDelta > effectiveToleranceMs) {
    throw StateError(
      'Duration delta ${durationDelta}ms exceeds ${effectiveToleranceMs}ms '
      '(actual=${durationMs}ms expected=${expectedMs}ms).',
    );
  }

  final bitrate =
      int.tryParse('${videoStream['bit_rate']}') ??
      int.tryParse('${format['bit_rate']}');
  _assertExpectedBitrate(metadata, bitrate);

  await _assertMonotonicFramePts(video);

  return _ValidationResult(
    scenario: scenario,
    video: video,
    durationMs: durationMs,
    expectedMs: expectedMs,
    videoWidth: videoWidth,
    videoHeight: videoHeight,
    bitrate: bitrate,
  );
}

void _assertExpectedResolution(Map metadata, int videoWidth, int videoHeight) {
  final preset = metadata['requestedResolutionPreset'] as String?;
  final expectedShortSide = _presetShortSide[preset];
  if (expectedShortSide == null) {
    return;
  }

  final actualShortSide = math.min(videoWidth, videoHeight);
  final minimum = (expectedShortSide * (1 - _resolutionToleranceRatio)).round();
  final maximum = (expectedShortSide * (1 + _resolutionToleranceRatio)).round();
  if (actualShortSide < minimum || actualShortSide > maximum) {
    throw StateError(
      'Expected $preset short side near ${expectedShortSide}px, got '
      '${videoWidth}x$videoHeight.',
    );
  }
}

void _assertExpectedBitrate(Map metadata, int? actualBitrate) {
  final targetBitrate = (metadata['targetVideoBitrate'] as num?)?.round();
  if (targetBitrate == null || targetBitrate <= 0) {
    return;
  }
  if (actualBitrate == null || actualBitrate <= 0) {
    throw StateError('ffprobe did not report bitrate.');
  }

  final minimum = (targetBitrate * (1 - _bitrateToleranceRatio)).round();
  final maximum = (targetBitrate * (1 + _bitrateToleranceRatio)).round();
  if (actualBitrate < minimum || actualBitrate > maximum) {
    throw StateError(
      'Bitrate $actualBitrate bps is outside +/-25% of target '
      '$targetBitrate bps.',
    );
  }
}

Future<File> _resolveVideoFile(File metadataFile, Map metadata) async {
  final videoPath = metadata['videoPath'] as String?;
  if (videoPath == null || videoPath.isEmpty) {
    throw StateError('metadata missing videoPath.');
  }

  final original = File(videoPath);
  if (await original.exists()) {
    return original;
  }

  final basename = videoPath.split('/').last;
  return File('${metadataFile.parent.path}${Platform.pathSeparator}$basename');
}

Future<Map<String, Object?>> _ffprobeJson(List<String> args) async {
  final result = await Process.run('ffprobe', [
    '-v',
    'error',
    '-of',
    'json',
    ...args,
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'ffprobe failed (${result.exitCode}): ${result.stderr}'.trim(),
    );
  }
  return jsonDecode(result.stdout as String) as Map<String, Object?>;
}

Future<void> _assertMonotonicFramePts(File video) async {
  final probe = await _ffprobeJson([
    '-show_frames',
    '-show_entries',
    'frame=stream_index,best_effort_timestamp_time,pts_time',
    video.path,
  ]);
  final frames = (probe['frames'] as List? ?? const []).cast<Map>();
  final lastPtsByStream = <int, double>{};

  for (final frame in frames) {
    final streamIndex = (frame['stream_index'] as num?)?.toInt();
    final pts =
        double.tryParse('${frame['best_effort_timestamp_time']}') ??
        double.tryParse('${frame['pts_time']}');
    if (streamIndex == null || pts == null) {
      continue;
    }
    final lastPts = lastPtsByStream[streamIndex];
    if (lastPts != null && pts + 0.000001 < lastPts) {
      throw StateError(
        'Non-monotonic PTS on stream $streamIndex: $pts after $lastPts.',
      );
    }
    lastPtsByStream[streamIndex] = math.max(pts, lastPts ?? pts);
  }

  if (lastPtsByStream.isEmpty) {
    throw StateError('ffprobe returned no frame PTS values.');
  }
}

class _ValidationResult {
  const _ValidationResult({
    required this.scenario,
    required this.video,
    required this.durationMs,
    required this.expectedMs,
    required this.videoWidth,
    required this.videoHeight,
    required this.bitrate,
  });

  final String scenario;
  final File video;
  final int durationMs;
  final int expectedMs;
  final int videoWidth;
  final int videoHeight;
  final int? bitrate;
}
