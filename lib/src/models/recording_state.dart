/// Represents the current state of video recording.
enum RecordingState {
  /// Camera is idle, not recording.
  idle,

  /// Camera is actively recording.
  recording,

  /// Camera is recording but paused.
  paused,

  /// Camera is switching to another camera during recording.
  switching,
}
