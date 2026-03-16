/// Describes a camera device.
class CameraDescription {
  /// Human-readable name of the camera (e.g., 'Front Camera', 'Back Camera').
  final String name;

  /// The direction the camera is facing.
  final LensDirection lensDirection;

  /// The physical orientation of the camera sensor on the device, in degrees.
  /// Common values are 0, 90, 180, 270.
  final int sensorOrientation;

  /// Creates a [CameraDescription] with the given properties.
  const CameraDescription({
    required this.name,
    required this.lensDirection,
    required this.sensorOrientation,
  });

  @override
  String toString() =>
      'CameraDescription(name: $name, lensDirection: $lensDirection, sensorOrientation: $sensorOrientation)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraDescription &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          lensDirection == other.lensDirection &&
          sensorOrientation == other.sensorOrientation;

  @override
  int get hashCode =>
      name.hashCode ^ lensDirection.hashCode ^ sensorOrientation.hashCode;
}

/// Defines the direction the camera lens is facing.
enum LensDirection {
  /// Camera is facing the user (selfie camera).
  front,

  /// Camera is facing away from the user (rear camera).
  back,

  /// External camera (e.g., USB camera).
  external,
}
