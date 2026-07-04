/// Enum representing the internal camera switching implementation path.
///
/// This is an internal-only enum that determines which optimized or fallback
/// camera switching strategy is used for the current platform and hardware.
/// External users always see the same public API regardless of which path is selected.
enum SwitchingPath {
  /// iOS optimized path using AVCaptureMultiCamSession.
  ///
  /// Available only on iOS devices that support MultiCam (iPhone XS and newer).
  /// This path provides the fastest camera switching without segment merging.
  iosOptimizedMultiCam,

  /// Fallback path using segment recording with merge on stop.
  ///
  /// Used on iOS devices without MultiCam support.
  /// Records segments and merges them when recording stops.
  fallbackSegmentMerge,

  /// Android path using CameraX persistent recording across camera rebinds.
  ///
  /// Used on Android devices that pass runtime front/back camera checks.
  /// Records one continuous file without segment merging.
  androidPersistentRecording,

  /// Legacy Android segment-merge path value retained for enum compatibility.
  ///
  /// New Android recordings no longer use this path.
  androidFallbackSegmentMerge,
}
