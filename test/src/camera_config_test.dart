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
}
