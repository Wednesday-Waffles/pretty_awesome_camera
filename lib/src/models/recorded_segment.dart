/// Models for interrupted-recording salvage.
///
/// A recording session can become an ordered list of *finalized* segment
/// files. Native seals the in-flight segment at interruption onset (while the
/// writer is still healthy) and stashes the result; Dart drains the stash over
/// the method channel. The seal *notification* carries no payload — see
/// [MethodChannelPrettyAwesomeCamera.onAudioDeviceChanged] — so every piece of
/// metadata in this file arrives via an explicit method call.
library;

/// Notification name emitted when native has sealed a segment.
///
/// It is a bare name by design. The event model behind the audio-device
/// channel keeps only four keys and silently drops everything else, so a
/// payload-carrying event would arrive looking healthy with its payload gone.
/// The media is already safe when this fires; call
/// [CameraController.consumeSealedSegments] to fetch the metadata.
const String recordingSegmentSealedEvent = 'recordingSegmentSealed';

/// Notification name emitted when a seal attempt produced nothing playable.
///
/// Success and failure need distinct names, not a payload field. The listener
/// has to choose its next state *before* it can drain the stash, and the event
/// model keeps only the name — so the one bit that decides "is there a
/// segment?" has to travel in the name itself. The attempt is still stashed,
/// so a failed seal remains visible to telemetry.
const String recordingSegmentSealFailedEvent = 'recordingSegmentSealFailed';

/// Notification name emitted when the native writer has died mid-recording.
///
/// Also a bare name; call [CameraController.consumeWriterFailure] for the
/// diagnostics.
const String recordingWriterFailedEvent = 'recordingWriterFailed';

/// Whether — and how — native may seal the in-flight segment by itself.
///
/// Decided by the caller once per take and sent with the start call, so native
/// never has to infer intent from pause state (which would race the Dart
/// lifecycle callbacks).
enum SalvagePolicy {
  /// Native seals nothing. Interruption and background handling behave exactly
  /// as they did before salvage existed. This is the default, so an upgraded
  /// plugin cannot change recording behavior until a caller opts in.
  off('off'),

  /// Native seals on interruption *and* on backgrounding.
  seal('seal'),

  /// Native seals on genuine device-contention interruptions only. Background
  /// transitions are left to the caller, which keeps an existing
  /// pause-on-background implementation in charge.
  sealInterruptOnly('seal_interrupt_only');

  const SalvagePolicy(this.wireName);

  /// The value sent across the method channel.
  final String wireName;

  /// Parses [wireName], falling back to [SalvagePolicy.off] for anything
  /// unrecognised — an unknown policy must never enable sealing.
  static SalvagePolicy fromWireName(String? value) {
    for (final policy in SalvagePolicy.values) {
      if (policy.wireName == value) {
        return policy;
      }
    }
    return SalvagePolicy.off;
  }
}

/// A finalized, playable segment file produced by a successful seal.
class RecordedSegment {
  const RecordedSegment({
    required this.path,
    required this.duration,
    required this.reason,
  });

  /// Absolute path of the finalized file. The caller owns this file: nothing
  /// in the plugin will ever delete it.
  final String path;

  /// Duration native measured for this segment.
  final Duration duration;

  /// Why the segment was sealed, as reported by native (see
  /// [SegmentSealReasons]).
  final String reason;

  @override
  String toString() =>
      'RecordedSegment(path: $path, duration: $duration, reason: $reason)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RecordedSegment &&
        other.path == path &&
        other.duration == duration &&
        other.reason == reason;
  }

  @override
  int get hashCode => Object.hash(path, duration, reason);
}

/// The outcome of one seal *attempt*.
///
/// Failed attempts are recorded too: without them a seal-success rate could
/// never be measured, and a rollout would only ever sample the takes that
/// worked.
class SegmentSealOutcome {
  const SegmentSealOutcome({
    required this.ok,
    required this.reason,
    required this.writerStatus,
    required this.sealLatency,
    this.segment,
  });

  /// Whether the attempt produced a finalized, playable file.
  final bool ok;

  /// The finalized segment. Non-null if and only if [ok] is true.
  final RecordedSegment? segment;

  /// Why the seal was attempted (see [SegmentSealReasons]).
  final String reason;

  /// How long the seal took, measured natively from trigger to finalize.
  final Duration sealLatency;

  /// Native writer/recorder status observed at the moment of the attempt.
  /// Useful for telling "sealed a healthy writer" apart from "the writer was
  /// already dead".
  final String writerStatus;

  /// Builds an outcome from a native map. Unknown or missing keys degrade to
  /// a failed outcome rather than throwing — a malformed drain must not take
  /// the recorder down.
  factory SegmentSealOutcome.fromMap(Map<dynamic, dynamic> map) {
    final ok = map['ok'] as bool? ?? false;
    final path = map['path'] as String?;
    final durationMs = (map['durationMs'] as num?)?.toInt() ?? 0;
    final reason = map['reason'] as String? ?? SegmentSealReasons.unknown;
    final writerStatus = map['writerStatus'] as String? ?? 'unknown';
    final sealLatencyMs = (map['sealLatencyMs'] as num?)?.toInt() ?? 0;

    // `ok` without a path is a contradiction; treat it as a failure so callers
    // can rely on `segment != null` whenever `ok` is true.
    final hasFile = ok && path != null && path.isNotEmpty;

    return SegmentSealOutcome(
      ok: hasFile,
      reason: reason,
      writerStatus: writerStatus,
      sealLatency: Duration(milliseconds: sealLatencyMs),
      segment: hasFile
          ? RecordedSegment(
              path: path,
              duration: Duration(milliseconds: durationMs),
              reason: reason,
            )
          : null,
    );
  }

  @override
  String toString() =>
      'SegmentSealOutcome(ok: $ok, segment: $segment, reason: $reason, '
      'writerStatus: $writerStatus, sealLatency: $sealLatency)';
}

/// The reason strings native uses for a seal attempt.
abstract final class SegmentSealReasons {
  static const String audioInterruption = 'audio_interruption';
  static const String sessionInterrupted = 'session_interrupted';
  static const String backgrounded = 'backgrounded';
  static const String audioSourceSilenced = 'audio_source_silenced';
  static const String explicit = 'explicit';
  static const String unknown = 'unknown';
}

/// Diagnostics for a writer that died mid-recording.
///
/// This is a *detected-loss* report, never a salvage: by the time a writer
/// failure is observable the writer has already failed, and a failed writer
/// can never be finalized — so the in-flight media is gone. The value of the
/// report is that the caller learns within a tick instead of at the recording
/// time limit.
class WriterFailureReport {
  const WriterFailureReport({
    required this.stage,
    required this.errorDomain,
    required this.errorCode,
    required this.elapsed,
  });

  /// Where the writer died: `start_writing`, `append_video`, `append_audio`.
  final String stage;

  /// Platform error domain, or an empty string when native had none.
  final String errorDomain;

  /// Platform error code, or 0 when native had none.
  final int errorCode;

  /// How long the recording had been running when the writer died.
  final Duration elapsed;

  factory WriterFailureReport.fromMap(Map<dynamic, dynamic> map) {
    return WriterFailureReport(
      stage: map['stage'] as String? ?? 'unknown',
      errorDomain: map['errorDomain'] as String? ?? '',
      errorCode: (map['errorCode'] as num?)?.toInt() ?? 0,
      elapsed: Duration(milliseconds: (map['elapsedMs'] as num?)?.toInt() ?? 0),
    );
  }

  @override
  String toString() =>
      'WriterFailureReport(stage: $stage, errorDomain: $errorDomain, '
      'errorCode: $errorCode, elapsed: $elapsed)';
}

/// What the underlying native build can actually do.
///
/// Callers must treat a build that can seal but not concatenate as
/// *unsupported*: offering to continue a recording that can never be
/// reassembled is worse than offering nothing.
class RecordingCapabilities {
  const RecordingCapabilities({
    required this.supportsSegmentSeal,
    required this.supportsConcat,
  });

  /// No capability at all — the value used when the native build predates
  /// salvage and reports `NOT_IMPLEMENTED`.
  static const RecordingCapabilities none = RecordingCapabilities(
    supportsSegmentSeal: false,
    supportsConcat: false,
  );

  final bool supportsSegmentSeal;
  final bool supportsConcat;

  /// True only when the full salvage flow can be honoured end to end.
  bool get supportsSalvage => supportsSegmentSeal && supportsConcat;

  factory RecordingCapabilities.fromMap(Map<dynamic, dynamic> map) {
    return RecordingCapabilities(
      supportsSegmentSeal: map['supportsSegmentSeal'] as bool? ?? false,
      supportsConcat: map['supportsConcat'] as bool? ?? false,
    );
  }

  @override
  String toString() =>
      'RecordingCapabilities(supportsSegmentSeal: $supportsSegmentSeal, '
      'supportsConcat: $supportsConcat)';
}

/// The result of concatenating an ordered list of segments.
class SegmentConcatResult {
  const SegmentConcatResult({required this.path, required this.duration});

  /// Absolute path of the concatenated output. The caller owns this file.
  final String path;

  /// Duration native measured for the output. Callers should compare it
  /// against the sum of the input durations and reject an output that drifts:
  /// "the concat succeeded" is not the same as "the output is playable".
  final Duration duration;

  factory SegmentConcatResult.fromMap(Map<dynamic, dynamic> map) {
    return SegmentConcatResult(
      path: map['path'] as String? ?? '',
      duration: Duration(
        milliseconds: (map['durationMs'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  @override
  String toString() => 'SegmentConcatResult(path: $path, duration: $duration)';
}
