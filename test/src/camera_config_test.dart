import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_awesome_camera/pretty_awesome_camera.dart';

void main() {
  test('serializes optional video bitrate', () {
    const config = CameraConfig(
      resolutionPreset: ResolutionPreset.medium,
      lensDirection: LensDirection.front,
      videoBitrate: 800000,
    );

    expect(config.toJson(), {
      'resolutionPreset': 'medium',
      'lensDirection': 'front',
      'videoBitrate': 800000,
      'preferBluetoothMic': false,
    });
  });

  test('copyWith preserves and clears video bitrate', () {
    const config = CameraConfig(
      resolutionPreset: ResolutionPreset.medium,
      videoBitrate: 800000,
    );

    expect(
      config.copyWith(resolutionPreset: ResolutionPreset.high).videoBitrate,
      800000,
    );
    expect(config.copyWith(clearVideoBitrate: true).videoBitrate, isNull);
  });

  test('preferBluetoothMic defaults false, serializes, and copies', () {
    const config = CameraConfig();
    expect(config.preferBluetoothMic, isFalse);
    expect(config.toJson()['preferBluetoothMic'], false);

    final enabled = config.copyWith(preferBluetoothMic: true);
    expect(enabled.preferBluetoothMic, isTrue);
    expect(enabled.toJson()['preferBluetoothMic'], true);
    // Unrelated copyWith calls must not reset the flag.
    expect(
      enabled
          .copyWith(resolutionPreset: ResolutionPreset.low)
          .preferBluetoothMic,
      isTrue,
    );
  });
}
