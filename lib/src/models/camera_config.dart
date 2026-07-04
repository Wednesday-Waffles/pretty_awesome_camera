import 'camera_description.dart';
import 'resolution_preset.dart';

/// Immutable configuration used when creating and initializing a camera.
class CameraConfig {
  /// Requested recording/preview quality preset.
  final ResolutionPreset resolutionPreset;

  /// Optional preferred lens to use when selecting a camera.
  final LensDirection? lensDirection;

  /// Optional target video encoding bitrate, in bits per second.
  final int? videoBitrate;

  const CameraConfig({
    this.resolutionPreset = ResolutionPreset.high,
    this.lensDirection,
    this.videoBitrate,
  });

  CameraConfig copyWith({
    ResolutionPreset? resolutionPreset,
    LensDirection? lensDirection,
    int? videoBitrate,
    bool clearLensDirection = false,
    bool clearVideoBitrate = false,
  }) {
    return CameraConfig(
      resolutionPreset: resolutionPreset ?? this.resolutionPreset,
      lensDirection: clearLensDirection
          ? null
          : (lensDirection ?? this.lensDirection),
      videoBitrate: clearVideoBitrate
          ? null
          : (videoBitrate ?? this.videoBitrate),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'resolutionPreset': resolutionPreset.name,
      'lensDirection': lensDirection?.name,
      'videoBitrate': videoBitrate,
    };
  }
}
