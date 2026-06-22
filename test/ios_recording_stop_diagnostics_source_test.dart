import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('iOS recording stop diagnostics', () {
    test('snapshots converter diagnostics before finishStop cleanup', () {
      final source = File(
        'ios/Classes/PrettyAwesomeCameraPlugin.swift',
      ).readAsStringSync();
      final finishStopIndex = source.indexOf('let finishStop: () -> Void = {');

      expect(finishStopIndex, greaterThanOrEqualTo(0));

      final finishStopSource = source.substring(finishStopIndex);
      final converterSnapshot = finishStopSource.indexOf(
        'let hadAudioConverter = cameraInstance.audioConverter != nil',
      );
      final formatSnapshot = finishStopSource.indexOf(
        'let audioConverterInputFormat = cameraInstance.audioConverterInputFormat',
      );
      final converterCleanup = finishStopSource.indexOf(
        'cameraInstance.resetAudioConverter()',
      );

      expect(converterSnapshot, greaterThanOrEqualTo(0));
      expect(formatSnapshot, greaterThanOrEqualTo(0));
      expect(converterCleanup, greaterThanOrEqualTo(0));
      expect(converterSnapshot, lessThan(converterCleanup));
      expect(formatSnapshot, lessThan(converterCleanup));
      expect(
        finishStopSource,
        contains('hasAudioConverter: hadAudioConverter'),
      );
      expect(
        finishStopSource,
        contains('audioConverterInputFormat: audioConverterInputFormat'),
      );
      expect(source, contains('"native_audio_converter_input_sample_rate"'));
      expect(source, contains('"native_audio_converter_input_channel_count"'));
      expect(source, contains('"native_audio_conv_rate"'));
      expect(source, contains('"native_audio_conv_chans"'));
      expect(source, contains('"native_underlying_error_domain"'));
      expect(source, contains('"native_underlying_error_code"'));
      expect(source, contains('"native_under_err_domain"'));
      expect(source, contains('"native_under_err_code"'));
    });
  });
}
