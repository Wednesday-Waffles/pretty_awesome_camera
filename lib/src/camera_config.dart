import 'camera_description.dart';
import 'resolution_preset.dart';

/// Immutable configuration used when creating and initializing a camera.
class CameraConfig {
  /// Requested recording/preview quality preset.
  final ResolutionPreset resolutionPreset;

  /// Optional preferred lens to use when selecting a camera.
  final LensDirection? lensDirection;

  const CameraConfig({
    this.resolutionPreset = ResolutionPreset.high,
    this.lensDirection,
  });

  CameraConfig copyWith({
    ResolutionPreset? resolutionPreset,
    LensDirection? lensDirection,
    bool clearLensDirection = false,
  }) {
    return CameraConfig(
      resolutionPreset: resolutionPreset ?? this.resolutionPreset,
      lensDirection: clearLensDirection
          ? null
          : (lensDirection ?? this.lensDirection),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'resolutionPreset': resolutionPreset.name,
      'lensDirection': lensDirection?.name,
    };
  }
}
