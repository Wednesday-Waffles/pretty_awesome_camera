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

    test('camera switch arms timelines only after successful commit', () {
      final switchStart = source.indexOf('private func switchCamera(');
      final stopStart = source.indexOf(
        'private func stopRecording(',
        switchStart,
      );
      expect(switchStart, greaterThanOrEqualTo(0));
      expect(stopStart, greaterThan(switchStart));

      final switchSource = source.substring(switchStart, stopStart);

      final prepareIndex = switchSource.indexOf(
        'cameraInstance.previewTexture?.prepareForCameraSwitch',
      );
      final audioHoldIndex = switchSource.indexOf(
        'cameraInstance._cameraSwitchAudioGate.begin(',
      );
      final beginConfigurationIndex = switchSource.indexOf(
        'captureSession.beginConfiguration()',
      );
      final successfulCommitIndex = switchSource.lastIndexOf(
        'captureSession.commitConfiguration()',
      );
      final videoTimelineIndex = switchSource.indexOf(
        'cameraInstance._videoTimeline.markDiscontinuity()',
      );
      final audioTimelineIndex = switchSource.indexOf(
        'cameraInstance._audioTimeline.markDiscontinuity()',
      );
      final pendingIndex = switchSource.indexOf(
        'cameraInstance._cameraSwitchGenerationPending = switchGeneration',
      );
      final releaseIndex = switchSource.indexOf(
        'cameraInstance.previewTexture?.completeCameraSwitchStabilization()',
      );
      final successfulAudioReleaseIndex = switchSource.lastIndexOf(
        'cameraInstance._cameraSwitchAudioGate.release(',
      );

      expect(audioHoldIndex, greaterThanOrEqualTo(0));
      expect(prepareIndex, greaterThan(audioHoldIndex));
      expect(prepareIndex, greaterThanOrEqualTo(0));
      expect(beginConfigurationIndex, greaterThan(prepareIndex));
      expect(successfulCommitIndex, greaterThan(beginConfigurationIndex));
      expect(videoTimelineIndex, greaterThan(successfulCommitIndex));
      expect(audioTimelineIndex, greaterThan(successfulCommitIndex));
      expect(pendingIndex, greaterThan(successfulCommitIndex));
      expect(successfulAudioReleaseIndex, greaterThan(pendingIndex));
      expect(releaseIndex, greaterThan(pendingIndex));
      expect(releaseIndex, greaterThan(successfulAudioReleaseIndex));
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
        contains(
          'cameraInstance._cameraSwitchGenerationPending = switchGeneration',
        ),
      );
      expect(
        'cameraInstance.previewTexture?.cancelCameraSwitchStabilization()'
            .allMatches(switchSource),
        hasLength(2),
      );
      expect(
        'cameraInstance._cameraSwitchAudioGate.release('.allMatches(
          switchSource,
        ),
        hasLength(3),
      );

      final videoStart = source.indexOf(
        'private func handleVideoSampleBuffer(',
      );
      final audioExtension = source.indexOf(
        'extension PrettyAwesomeCameraPlugin: AVCaptureAudioDataOutputSampleBufferDelegate',
      );
      final videoSource = source.substring(videoStart, audioExtension);
      final sharedGapIndex = videoSource.indexOf(
        'guard let sharedGap = cameraInstance._videoTimeline',
      );
      final pendingClearIndex = videoSource.indexOf(
        'cameraInstance._cameraSwitchGenerationPending = nil',
      );
      expect(
        videoSource,
        contains('cameraInstance._cameraSwitchGenerationPending = nil'),
      );
      expect(
        videoSource,
        contains('guard switchGeneration == pendingGeneration'),
      );
      expect(
        videoSource,
        contains('consumePendingDiscontinuityGap(at: currentTime)'),
      );
      expect(
        videoSource,
        contains('cameraInstance._audioTimeline.applyPendingDiscontinuityGap('),
      );
      expect(sharedGapIndex, greaterThanOrEqualTo(0));
      expect(pendingClearIndex, greaterThan(sharedGapIndex));

      // The switch-attributed compression counter must accumulate exactly at
      // the shared-gap release so the client can reconcile wall-clock
      // recording time against the compressed media timeline.
      final compressionAccumulateIndex = videoSource.indexOf(
        'cameraInstance._cameraSwitchTimelineCompressionMs +=',
      );
      expect(compressionAccumulateIndex, greaterThan(sharedGapIndex));
      expect(compressionAccumulateIndex, lessThan(pendingClearIndex));
      // The credit must be active-recording time only: pause spans folded
      // into a switch gap (flip while paused) are excluded, because the
      // client's recording timer already stops during pauses.
      expect(
        videoSource,
        contains('max(0, sharedGapMs - pausedOverlapMs)'),
      );
      expect(
        source,
        contains('cameraInstance._cameraSwitchTimelineCompressionMs = 0'),
      );
      expect(
        source,
        contains('cameraInstance._cameraSwitchPausedOverlapMs = 0'),
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
        'cameraInstance._cameraSwitchAudioGate.isHolding ||'.allMatches(
          audioSource,
        ),
        hasLength(2),
      );
      expect(
        'cameraInstance._cameraSwitchAudioReleasePending'.allMatches(
          audioSource,
        ),
        hasLength(4),
      );
      expect(audioSource, isNot(contains('cameraInstance._videoTimeline')));
    });

    test('audio route transitions drop without retiming', () {
      expect(source, contains('_audioRouteDiscontinuityPending'));
      expect(
        'if cameraInstance._audioRouteDiscontinuityPending {'.allMatches(
          source,
        ),
        hasLength(2),
      );
      expect(
        'cameraInstance._audioTimeline.observeDroppedSample'.allMatches(source),
        hasLength(4),
      );
    });
  });
}
