import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('iOS recording timeline wiring', () {
    late String source;

    setUpAll(() {
      source = File(
        'ios/Classes/PrettyAwesomeCameraPlugin.swift',
      ).readAsStringSync();
    });

    test('audio and video no longer share discontinuity state', () {
      expect(source, contains('fileprivate var _videoTimeline'));
      expect(source, contains('fileprivate var _audioTimeline'));
      expect(source, isNot(contains('fileprivate var _timeOffset')));
      expect(source, isNot(contains('fileprivate var _lastSampleTime')));
      expect(source, isNot(contains('fileprivate var _discontinuityPending')));
    });

    test('camera switch arms both tracks and waits for stable video', () {
      final switchStart = source.indexOf('private func switchCamera(');
      final stopStart = source.indexOf(
        'private func stopRecording(',
        switchStart,
      );
      expect(switchStart, greaterThanOrEqualTo(0));
      expect(stopStart, greaterThan(switchStart));

      final switchSource = source.substring(switchStart, stopStart);
      expect(
        switchSource,
        contains('cameraInstance._videoTimeline.markDiscontinuity()'),
      );
      expect(
        switchSource,
        contains('cameraInstance._audioTimeline.markDiscontinuity()'),
      );
      expect(
        switchSource,
        contains('cameraInstance._cameraSwitchTimelinePending = true'),
      );

      final videoStart = source.indexOf(
        'private func handleVideoSampleBuffer(',
      );
      final audioExtension = source.indexOf(
        'extension PrettyAwesomeCameraPlugin: AVCaptureAudioDataOutputSampleBufferDelegate',
      );
      final videoSource = source.substring(videoStart, audioExtension);
      expect(
        videoSource,
        contains('cameraInstance._cameraSwitchTimelinePending = false'),
      );
      expect(
        videoSource,
        contains('cameraInstance._videoTimeline.consumePendingDiscontinuity'),
      );
    });

    test('both audio paths use only the audio timeline', () {
      final audioExtension = source.indexOf(
        'extension PrettyAwesomeCameraPlugin: AVCaptureAudioDataOutputSampleBufferDelegate',
      );
      expect(audioExtension, greaterThanOrEqualTo(0));
      final audioSource = source.substring(audioExtension);

      expect(
        'cameraInstance._audioTimeline.adjustedTime'.allMatches(audioSource),
        hasLength(2),
      );
      expect(
        'if cameraInstance._cameraSwitchTimelinePending'.allMatches(
          audioSource,
        ),
        hasLength(2),
      );
      expect(audioSource, isNot(contains('cameraInstance._videoTimeline')));
    });

    test('audio route transitions drop without retiming', () {
      expect(source, contains('_audioRouteDiscontinuityPending'));
      expect(
        'cameraInstance._audioTimeline.observeDroppedSample'.allMatches(source),
        hasLength(2),
      );
    });
  });
}
