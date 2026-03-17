import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/services.dart';

import 'camera_exception.dart';
import 'switching_path.dart';

/// Detects and manages camera switching capabilities for the current platform.
///
/// This class determines which camera switching implementation path (optimized
/// or fallback) should be used based on platform capabilities and device support.
/// Path selection happens before recording begins to ensure a consistent switching
/// strategy throughout the recording session.
class SwitchingCapability {
  static const MethodChannel _methodChannel = MethodChannel(
    'waffle_camera_plugin',
  );

  /// The detected switching path for the current platform and device.
  SwitchingPath? _detectedPath;

  /// Gets the detected switching path, detecting it if not already cached.
  Future<SwitchingPath> get detectedPath async {
    if (_detectedPath != null) {
      return _detectedPath!;
    }
    _detectedPath = await _detectSwitchingPath();
    return _detectedPath!;
  }

  /// Detects the optimal camera switching path for the current device.
  ///
  /// Uses the following decision logic:
  /// 1. On iOS: Check if AVCaptureMultiCamSession.isMultiCamSupported is true.
  ///    - If true, use iosOptimizedMultiCam (fast switching without merge)
  ///    - If false, use fallbackSegmentMerge (slower but reliable segment merge)
  /// 2. On Android: Always use androidFallbackSegmentMerge in v4.1.
  ///    - Future v4.2 may add optimized path after validation.
  ///
  /// Throws [CameraException] if capability detection fails.
  Future<SwitchingPath> _detectSwitchingPath() async {
    try {
      if (Platform.isIOS) {
        return await _detectIOSSwitchingPath();
      } else if (Platform.isAndroid) {
        return await _detectAndroidSwitchingPath();
      } else {
        throw CameraException(
          code: 'unsupported_platform',
          message: 'Camera switching is not supported on this platform',
        );
      }
    } catch (e) {
      if (e is CameraException) {
        rethrow;
      }
      throw CameraException(
        code: 'capability_detection_failed',
        message: 'Failed to detect camera switching capability: $e',
      );
    }
  }

  /// Detects the optimal switching path on iOS.
  Future<SwitchingPath> _detectIOSSwitchingPath() async {
    try {
      final isMultiCamSupported = await _methodChannel.invokeMethod<bool>(
        'isMultiCamSupported',
      );

      final supported = isMultiCamSupported ?? false;
      final path = supported
          ? SwitchingPath.iosOptimizedMultiCam
          : SwitchingPath.fallbackSegmentMerge;

      developer.log(
        'iOS switching path selected: $path (MultiCam supported: $supported)',
        name: 'waffle_camera.switching',
      );

      return path;
    } on PlatformException catch (e) {
      developer.log(
        'iOS MultiCam detection failed: ${e.code} - ${e.message}',
        name: 'waffle_camera.switching',
      );

      // Fall back to fallback path if detection fails
      developer.log(
        'Falling back to segment merge path due to detection failure',
        name: 'waffle_camera.switching',
      );

      return SwitchingPath.fallbackSegmentMerge;
    }
  }

  /// Detects the optimal switching path on Android.
  ///
  /// In v4.1, always returns the fallback path.
  /// Future v4.2 may use [_detectAndroidConcurrentCameras] to evaluate
  /// optimized path support.
  Future<SwitchingPath> _detectAndroidSwitchingPath() async {
    // v4.1: Always use fallback path on Android
    developer.log(
      'Android switching path selected: androidFallbackSegmentMerge (v4.1 constraint)',
      name: 'waffle_camera.switching',
    );

    return SwitchingPath.androidFallbackSegmentMerge;
  }

  /// Future-facing helper for Android concurrent camera detection.
  ///
  /// This method is for v4.2 research and evaluation.
  /// It checks if the platform reports concurrent camera support using
  /// CameraManager.getConcurrentCameraIds() on Android API 30+.
  ///
  /// Returns true only if concurrent cameras are reported as supported.
  /// Note: Concurrent camera reporting is necessary but not sufficient
  /// proof that a practical single-encoder switching flow can be implemented.
  ///
  /// Throws [CameraException] if the detection fails or is not supported.
  // ignore: unused_element - Reserved for v4.2 Android optimization research
  Future<bool> _detectAndroidConcurrentCameras() async {
    try {
      final hasConcurrent = await _methodChannel.invokeMethod<bool>(
        'hasAndroidConcurrentCameras',
      );

      return hasConcurrent ?? false;
    } on PlatformException catch (e) {
      throw CameraException(
        code: e.code,
        message: e.message ?? 'Failed to detect Android concurrent cameras',
      );
    }
  }

  /// Synchronously checks if the optimized camera switching path can be used.
  ///
  /// This is a convenience method that uses the cached detected path.
  /// Returns true only if the optimized path (iosOptimizedMultiCam) is available.
  /// This method does NOT perform detection; call [detectedPath] first.
  ///
  /// Returns false if path has not been detected yet or if fallback path is selected.
  bool canUseOptimizedPath() {
    return _detectedPath == SwitchingPath.iosOptimizedMultiCam;
  }

  /// Clears the cached path detection result.
  ///
  /// Useful for testing or if platform state changes dynamically.
  void clearCache() {
    _detectedPath = null;
  }
}
