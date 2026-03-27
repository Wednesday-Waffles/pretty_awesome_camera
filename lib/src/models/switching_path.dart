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

  /// Android fallback path using segment recording with merge on stop.
  ///
  /// Used on all Android devices in v4.1.
  /// Records segments and merges them when recording stops.
  androidFallbackSegmentMerge,
}
