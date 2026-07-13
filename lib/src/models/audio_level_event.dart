/// A throttled audio-level sample emitted while the camera's audio pipeline
/// is running.
///
/// Cadence and coverage differ by platform:
/// - iOS emits at ~4 Hz whenever the capture session runs (preview, paused,
///   and recording), computed as RMS/peak over the raw PCM buffers.
/// - Android emits at ~1 Hz and ONLY while a recording is active
///   (CameraX `VideoRecordEvent.Status` → `AudioStats`).
///
/// Consumers implementing silence detection must treat stream *staleness*
/// (no event for a while during an active recording) as its own signal —
/// during OS audio interruptions the stream stalls rather than reporting
/// silence.
class AudioLevelEvent {
  /// Normalized peak amplitude in [0, 1].
  ///
  /// Matches Android's `AudioStats.audioAmplitude` semantics; on iOS this is
  /// the normalized window peak derived from PCM samples.
  final double amplitude;

  /// Peak level in dBFS for the emission window. iOS only; null on Android.
  final double? peakDbfs;

  /// Average (RMS) level in dBFS for the emission window. iOS only; null on
  /// Android.
  final double? averageDbfs;

  /// Platform audio state.
  ///
  /// Android reports CameraX's causal states: `active`, `disabled`, `muted`,
  /// `sourceSilenced` (mic taken by another app / privacy toggle / call),
  /// `sourceError`, `encoderError`. iOS has no equivalent OS signal and
  /// always reports `unknown`.
  final String audioState;

  /// Native monotonic timestamp in milliseconds. Only meaningful for
  /// ordering/staleness within one stream — not wall-clock time.
  final int timestampMs;

  const AudioLevelEvent({
    required this.amplitude,
    this.peakDbfs,
    this.averageDbfs,
    this.audioState = 'unknown',
    required this.timestampMs,
  });

  factory AudioLevelEvent.fromMap(Map<dynamic, dynamic> map) {
    return AudioLevelEvent(
      amplitude: (map['amplitude'] as num?)?.toDouble() ?? 0.0,
      peakDbfs: (map['peakDbfs'] as num?)?.toDouble(),
      averageDbfs: (map['averageDbfs'] as num?)?.toDouble(),
      audioState: map['audioState'] as String? ?? 'unknown',
      timestampMs: (map['timestampMs'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'amplitude': amplitude,
      'peakDbfs': peakDbfs,
      'averageDbfs': averageDbfs,
      'audioState': audioState,
      'timestampMs': timestampMs,
    };
  }

  @override
  String toString() {
    return 'AudioLevelEvent(amplitude: $amplitude, peakDbfs: $peakDbfs, '
        'averageDbfs: $averageDbfs, audioState: $audioState, '
        'timestampMs: $timestampMs)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AudioLevelEvent &&
        other.amplitude == amplitude &&
        other.peakDbfs == peakDbfs &&
        other.averageDbfs == averageDbfs &&
        other.audioState == audioState &&
        other.timestampMs == timestampMs;
  }

  @override
  int get hashCode =>
      Object.hash(amplitude, peakDbfs, averageDbfs, audioState, timestampMs);
}
