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

  /// Android only: request Bluetooth-mic routing (communication device /
  /// legacy SCO) before each recording starts when a Bluetooth input is
  /// present. Best-effort — routing failures fall back to the built-in mic
  /// and never fail the recording. iOS ignores this flag (the audio session
  /// already honors Bluetooth via `.allowBluetooth` system routing).
  final bool preferBluetoothMic;

  const CameraConfig({
    this.resolutionPreset = ResolutionPreset.high,
    this.lensDirection,
    this.videoBitrate,
    this.preferBluetoothMic = false,
  });

  CameraConfig copyWith({
    ResolutionPreset? resolutionPreset,
    LensDirection? lensDirection,
    int? videoBitrate,
    bool? preferBluetoothMic,
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
      preferBluetoothMic: preferBluetoothMic ?? this.preferBluetoothMic,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'resolutionPreset': resolutionPreset.name,
      'lensDirection': lensDirection?.name,
      'videoBitrate': videoBitrate,
      'preferBluetoothMic': preferBluetoothMic,
    };
  }
}
