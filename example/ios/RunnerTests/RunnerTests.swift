import Flutter
import UIKit
import XCTest
import AVFoundation


@testable import pretty_awesome_camera

// This demonstrates a simple unit test of the Swift portion of this plugin's implementation.
//
// See https://developer.apple.com/documentation/xctest for more information about using XCTest.

class RunnerTests: XCTestCase {

  func testGetPlatformVersion() {
    let plugin = PrettyAwesomeCameraPlugin()

    let call = FlutterMethodCall(methodName: "getPlatformVersion", arguments: [])

    let resultExpectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      XCTAssertEqual(result as! String, "iOS " + UIDevice.current.systemVersion)
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

}

final class RecordingAudioSettingsTests: XCTestCase {

  func testRecordingAudioSettingsUseStableAacShape() throws {
    let settings = PrettyAwesomeCameraPlugin.recordingAudioSettings()

    XCTAssertEqual(settings[AVFormatIDKey] as? AudioFormatID, kAudioFormatMPEG4AAC)
    XCTAssertEqual(settings[AVSampleRateKey] as? Double, 44100)
    XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 1)
    XCTAssertEqual(settings[AVEncoderBitRateKey] as? Int, 128000)
  }

  func testStableRecordingAudioSettingsCanBeAddedToAssetWriter() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("stable_audio_settings_\(UUID().uuidString).mov")
    try? FileManager.default.removeItem(at: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let writer = try AVAssetWriter(url: url, fileType: .mov)
    let input = AVAssetWriterInput(
      mediaType: .audio,
      outputSettings: PrettyAwesomeCameraPlugin.recordingAudioSettings()
    )

    XCTAssertTrue(writer.canAdd(input))
  }
}

final class MediaTimelineStateTests: XCTestCase {

  private func time(_ milliseconds: Int64) -> CMTime {
    CMTime(value: milliseconds, timescale: 1000)
  }

  private func appendedTime(
    _ decision: MediaTimelineAppendDecision,
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> CMTime {
    guard case .append(let adjustedTime) = decision else {
      XCTFail("Expected an append decision, got \(decision)", file: file, line: line)
      return .invalid
    }
    return adjustedTime
  }

  func testIndependentTracksAvoidTheSharedTimelineRegression() {
    var video = MediaTimelineState()
    var audio = MediaTimelineState()

    let previousVideo = appendedTime(video.adjustedTime(for: time(1033)))
    let previousAudio = appendedTime(audio.adjustedTime(for: time(1000)))

    video.markDiscontinuity()
    audio.markDiscontinuity()

    XCTAssertTrue(video.consumePendingDiscontinuity(at: time(1200)))
    XCTAssertTrue(audio.consumePendingDiscontinuity(at: time(1190)))

    let nextVideo = appendedTime(video.adjustedTime(for: time(1233)))
    let nextAudio = appendedTime(audio.adjustedTime(for: time(1213)))

    XCTAssertGreaterThan(CMTimeCompare(nextVideo, previousVideo), 0)
    XCTAssertGreaterThan(CMTimeCompare(nextAudio, previousAudio), 0)

    // The removed shared implementation could use audio's 1000 ms PTS as
    // video's last sample, subtract a 200 ms gap, and generate 1033 ms again.
    // AVAssetWriterInput rejects that non-monotonic duplicate.
    let sharedGap = CMTimeSubtract(time(1200), time(1000))
    let sharedAdjustedVideo = CMTimeSubtract(time(1233), sharedGap)
    XCTAssertLessThanOrEqual(CMTimeCompare(sharedAdjustedVideo, previousVideo), 0)
  }

  func testRepeatedDiscontinuitiesRemainMonotonicPerTrack() {
    var timeline = MediaTimelineState()
    var previous = appendedTime(timeline.adjustedTime(for: time(1000)))

    for sourceBase in [1400, 1900, 2500, 3200] {
      timeline.markDiscontinuity()
      XCTAssertTrue(timeline.consumePendingDiscontinuity(at: time(Int64(sourceBase))))
      let adjusted = appendedTime(
        timeline.adjustedTime(for: time(Int64(sourceBase + 33)))
      )
      XCTAssertGreaterThan(CMTimeCompare(adjusted, previous), 0)
      previous = adjusted
    }
  }

  func testAudioRouteDropPreservesGapWithoutRetiming() {
    var audio = MediaTimelineState()
    XCTAssertEqual(
      CMTimeCompare(appendedTime(audio.adjustedTime(for: time(1000))), time(1000)),
      0
    )

    audio.observeDroppedSample(at: time(1500))
    let postRoute = appendedTime(audio.adjustedTime(for: time(1523)))

    XCTAssertEqual(CMTimeCompare(postRoute, time(1523)), 0)
    XCTAssertEqual(CMTimeCompare(audio.timeOffset, .zero), 0)
  }

  func testNonMonotonicTimestampIsRejectedWithoutAdvancingOutputTimeline() throws {
    var timeline = MediaTimelineState()
    _ = appendedTime(timeline.adjustedTime(for: time(1000)))

    guard case .dropNonMonotonic(let candidate, let previous) =
      timeline.adjustedTime(for: time(1000)) else {
      return XCTFail("Expected duplicate PTS to be rejected")
    }
    XCTAssertEqual(CMTimeCompare(candidate, previous), 0)
    XCTAssertEqual(CMTimeCompare(try XCTUnwrap(timeline.lastSourceTime), time(1000)), 0)

    let recovered = appendedTime(timeline.adjustedTime(for: time(1033)))
    XCTAssertEqual(CMTimeCompare(recovered, time(1033)), 0)
  }
}

final class CameraSwitchFrameGateTests: XCTestCase {

  func testReconfigurationDropsDoNotConsumePostSwitchStabilizationBudget() {
    var gate = CameraSwitchFrameGate()

    XCTAssertEqual(gate.prepare(), 1)
    for _ in 0..<100 {
      XCTAssertTrue(gate.shouldDropFrame())
    }

    gate.complete(stabilizationFrameCount: 3)
    XCTAssertTrue(gate.shouldDropFrame())
    XCTAssertTrue(gate.shouldDropFrame())
    XCTAssertTrue(gate.shouldDropFrame())
    XCTAssertFalse(gate.shouldDropFrame())
    XCTAssertFalse(gate.isDroppingFrames)
  }

  func testRejectedSwitchReleasesOldCameraWithoutPostSwitchDrops() {
    var gate = CameraSwitchFrameGate()

    XCTAssertEqual(gate.prepare(), 1)
    XCTAssertTrue(gate.shouldDropFrame())

    gate.cancel()
    XCTAssertEqual(gate.generation, 0)
    XCTAssertFalse(gate.shouldDropFrame())
    XCTAssertFalse(gate.isDroppingFrames)
  }

  func testSuccessfulPreparationAdvancesTheCallbackGeneration() {
    var gate = CameraSwitchFrameGate()

    XCTAssertEqual(gate.prepare(), 1)
    gate.complete(stabilizationFrameCount: 0)
    XCTAssertEqual(gate.prepare(), 2)
    gate.complete(stabilizationFrameCount: 0)
    XCTAssertEqual(gate.generation, 2)
  }

  func testRejectedRapidSwitchRestoresPriorPendingGeneration() {
    var gate = CameraSwitchFrameGate()

    XCTAssertEqual(gate.prepare(), 1)
    gate.complete(stabilizationFrameCount: 3)
    XCTAssertEqual(gate.generation, 1)
    XCTAssertTrue(gate.shouldDropFrame())
    XCTAssertEqual(gate.stabilizationFramesRemaining, 2)

    XCTAssertEqual(gate.prepare(), 2)
    gate.cancel()

    XCTAssertEqual(gate.generation, 1)
    XCTAssertEqual(gate.stabilizationFramesRemaining, 2)
    XCTAssertTrue(gate.shouldDropFrame())
    XCTAssertTrue(gate.shouldDropFrame())
    XCTAssertFalse(gate.shouldDropFrame())
  }
}

final class CameraSwitchAudioGateTests: XCTestCase {

  func testGateMeasuresConfigurationHoldAndResetsOnCommit() {
    var gate = CameraSwitchAudioGate()

    gate.begin(at: 10.0)
    XCTAssertTrue(gate.isHolding)
    XCTAssertEqual(gate.release(at: 10.120), 120)
    XCTAssertFalse(gate.isHolding)
    XCTAssertNil(gate.release(at: 10.200))
  }

  func testRepeatedBeginDoesNotMoveTheOriginalBoundary() {
    var gate = CameraSwitchAudioGate()

    gate.begin(at: 20.0)
    gate.begin(at: 20.080)

    XCTAssertEqual(gate.release(at: 20.150), 150)
  }

  func testRejectedSwitchReleaseCannotStrandTheNextSwitch() {
    var gate = CameraSwitchAudioGate()

    gate.begin(at: 30.0)
    XCTAssertEqual(gate.release(at: 30.040), 40)
    gate.begin(at: 31.0)

    XCTAssertTrue(gate.isHolding)
    XCTAssertEqual(gate.release(at: 31.090), 90)
    XCTAssertFalse(gate.isHolding)
  }
}

final class CameraSwitchTimelineSynchronizationTests: XCTestCase {

  private func time(_ milliseconds: Int64) -> CMTime {
    CMTime(value: milliseconds, timescale: 1000)
  }

  private func appendedTime(
    _ decision: MediaTimelineAppendDecision,
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> CMTime {
    guard case .append(let adjustedTime) = decision else {
      XCTFail("Expected append, got \(decision)", file: file, line: line)
      return .invalid
    }
    return adjustedTime
  }

  private func floorToGrid(_ value: Int64, interval: Int64) -> Int64 {
    (value / interval) * interval
  }

  private func ceilToGrid(_ value: Int64, interval: Int64) -> Int64 {
    ((value + interval - 1) / interval) * interval
  }

  func testSharedVideoGapKeepsRepeatedFlipAlignmentBounded() throws {
    var video = MediaTimelineState()
    var audio = MediaTimelineState()
    let videoInterval: Int64 = 33
    let audioInterval: Int64 = 23

    for flipTime in stride(from: Int64(2_000), through: 20_000, by: 2_000) {
      let lastVideoSource = floorToGrid(flipTime - 1, interval: videoInterval)
      let lastAudioSource = floorToGrid(flipTime - 1, interval: audioInterval)
      _ = appendedTime(video.adjustedTime(for: time(lastVideoSource)))
      _ = appendedTime(audio.adjustedTime(for: time(lastAudioSource)))

      video.markDiscontinuity()
      audio.markDiscontinuity()

      let stableVideoSource = ceilToGrid(
        flipTime + 300,
        interval: videoInterval
      )
      let sharedGap = try XCTUnwrap(
        video.consumePendingDiscontinuityGap(at: time(stableVideoSource))
      )
      audio.applyPendingDiscontinuityGap(sharedGap)

      // Production drops the first released audio buffer after applying the
      // shared video gap, then resumes both tracks on their native sample grids.
      let releasedAudioSource = ceilToGrid(
        stableVideoSource,
        interval: audioInterval
      )
      audio.observeDroppedSample(at: time(releasedAudioSource))

      let nextVideo = appendedTime(
        video.adjustedTime(for: time(stableVideoSource + videoInterval))
      )
      let nextAudio = appendedTime(
        audio.adjustedTime(for: time(releasedAudioSource + audioInterval))
      )
      let alignmentMs = abs(
        CMTimeGetSeconds(CMTimeSubtract(nextAudio, nextVideo)) * 1000
      )

      XCTAssertLessThanOrEqual(alignmentMs, 40)
      XCTAssertEqual(CMTimeCompare(video.timeOffset, audio.timeOffset), 0)
    }
  }

  func testInvalidSourceTimeKeepsPendingBoundaryArmed() {
    var timeline = MediaTimelineState()
    _ = appendedTime(timeline.adjustedTime(for: time(1_000)))
    timeline.markDiscontinuity()

    XCTAssertTrue(timeline.consumePendingDiscontinuity(at: .invalid))
    XCTAssertTrue(timeline.discontinuityPending)
    XCTAssertTrue(timeline.consumePendingDiscontinuity(at: time(1_200)))
    XCTAssertFalse(timeline.discontinuityPending)
  }

  func testPauseResumeOffsetDoesNotGrowAcrossLaterCameraSwitches() throws {
    var video = MediaTimelineState()
    var audio = MediaTimelineState()
    let videoInterval: Int64 = 33
    let audioInterval: Int64 = 23

    let lastVideoBeforePause = floorToGrid(1_999, interval: videoInterval)
    let lastAudioBeforePause = floorToGrid(1_999, interval: audioInterval)
    _ = appendedTime(video.adjustedTime(for: time(lastVideoBeforePause)))
    _ = appendedTime(audio.adjustedTime(for: time(lastAudioBeforePause)))

    video.markDiscontinuity()
    audio.markDiscontinuity()
    let firstVideoAfterPause = ceilToGrid(2_600, interval: videoInterval)
    let firstAudioAfterPause = ceilToGrid(2_600, interval: audioInterval)
    XCTAssertTrue(
      video.consumePendingDiscontinuity(at: time(firstVideoAfterPause))
    )
    XCTAssertTrue(
      audio.consumePendingDiscontinuity(at: time(firstAudioAfterPause))
    )

    var nextVideoSource = firstVideoAfterPause + videoInterval
    var nextAudioSource = firstAudioAfterPause + audioInterval
    _ = appendedTime(video.adjustedTime(for: time(nextVideoSource)))
    _ = appendedTime(audio.adjustedTime(for: time(nextAudioSource)))

    let pauseOffsetDelta = CMTimeSubtract(
      audio.timeOffset,
      video.timeOffset
    )
    XCTAssertLessThanOrEqual(
      abs(CMTimeGetSeconds(pauseOffsetDelta) * 1_000),
      40
    )

    for flipTime in stride(from: Int64(4_000), through: 12_000, by: 2_000) {
      nextVideoSource = floorToGrid(flipTime - 1, interval: videoInterval)
      nextAudioSource = floorToGrid(flipTime - 1, interval: audioInterval)
      _ = appendedTime(video.adjustedTime(for: time(nextVideoSource)))
      _ = appendedTime(audio.adjustedTime(for: time(nextAudioSource)))

      video.markDiscontinuity()
      audio.markDiscontinuity()
      let stableVideoSource = ceilToGrid(
        flipTime + 300,
        interval: videoInterval
      )
      let sharedGap = try XCTUnwrap(
        video.consumePendingDiscontinuityGap(at: time(stableVideoSource))
      )
      audio.applyPendingDiscontinuityGap(sharedGap)

      let releasedAudioSource = ceilToGrid(
        stableVideoSource,
        interval: audioInterval
      )
      audio.observeDroppedSample(at: time(releasedAudioSource))

      let nextVideo = appendedTime(
        video.adjustedTime(for: time(stableVideoSource + videoInterval))
      )
      let nextAudio = appendedTime(
        audio.adjustedTime(for: time(releasedAudioSource + audioInterval))
      )
      let alignmentMs = abs(
        CMTimeGetSeconds(CMTimeSubtract(nextAudio, nextVideo)) * 1_000
      )

      XCTAssertLessThanOrEqual(alignmentMs, 60)
      XCTAssertEqual(
        CMTimeCompare(
          CMTimeSubtract(audio.timeOffset, video.timeOffset),
          pauseOffsetDelta
        ),
        0
      )
    }
  }
}

final class CameraSwitchAssetWriterSynchronizationTests: XCTestCase {

  private enum TrackKind: Equatable { case video, audio }

  private struct SourceEvent {
    let kind: TrackKind
    let sourceTime: CMTime

    var seconds: Double { CMTimeGetSeconds(sourceTime) }
  }

  func testRepeatedSymmetricSwitchesProduceAlignedWriterTracks() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("camera_switch_sync_\(UUID().uuidString).mov")
    try? FileManager.default.removeItem(at: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let writer = try AVAssetWriter(url: url, fileType: .mov)
    let videoInput = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: 64,
        AVVideoHeightKey: 64,
      ]
    )
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: videoInput,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: 64,
        kCVPixelBufferHeightKey as String: 64,
      ]
    )
    let audioInput = AVAssetWriterInput(
      mediaType: .audio,
      outputSettings: PrettyAwesomeCameraPlugin.recordingAudioSettings()
    )
    videoInput.expectsMediaDataInRealTime = false
    audioInput.expectsMediaDataInRealTime = false
    XCTAssertTrue(writer.canAdd(videoInput))
    XCTAssertTrue(writer.canAdd(audioInput))
    writer.add(videoInput)
    writer.add(audioInput)
    XCTAssertTrue(writer.startWriting())
    writer.startSession(atSourceTime: .zero)

    let timelines = try buildAdjustedTimelines()
    XCTAssertLessThanOrEqual(
      abs(CMTimeGetSeconds(CMTimeSubtract(
        try XCTUnwrap(timelines.audio.last),
        try XCTUnwrap(timelines.video.last)
      ))),
      0.040
    )

    let videoSamples = try timelines.video.map {
      (buffer: try makePixelBuffer(), presentationTime: $0)
    }
    let audioSamples = try timelines.audio.map {
      try makePCMSampleBuffer(startPTS: $0)
    }
    let videoFinished = expectation(description: "video input finishes")
    let audioFinished = expectation(description: "audio input finishes")
    var videoIndex = 0
    var audioIndex = 0
    videoInput.requestMediaDataWhenReady(
      on: DispatchQueue(label: "camera_switch_sync.video")
    ) {
      while videoInput.isReadyForMoreMediaData && videoIndex < videoSamples.count {
        let sample = videoSamples[videoIndex]
        guard adaptor.append(
          sample.buffer,
          withPresentationTime: sample.presentationTime
        ) else {
          XCTFail("video append failed: \(String(describing: writer.error))")
          videoInput.markAsFinished()
          videoFinished.fulfill()
          return
        }
        videoIndex += 1
      }
      if videoIndex == videoSamples.count {
        videoInput.markAsFinished()
        videoFinished.fulfill()
      }
    }
    audioInput.requestMediaDataWhenReady(
      on: DispatchQueue(label: "camera_switch_sync.audio")
    ) {
      while audioInput.isReadyForMoreMediaData && audioIndex < audioSamples.count {
        guard audioInput.append(audioSamples[audioIndex]) else {
          XCTFail("audio append failed: \(String(describing: writer.error))")
          audioInput.markAsFinished()
          audioFinished.fulfill()
          return
        }
        audioIndex += 1
      }
      if audioIndex == audioSamples.count {
        audioInput.markAsFinished()
        audioFinished.fulfill()
      }
    }
    wait(for: [videoFinished, audioFinished], timeout: 20)

    let finished = expectation(description: "writer finishes")
    writer.finishWriting { finished.fulfill() }
    wait(for: [finished], timeout: 20)
    XCTAssertEqual(
      writer.status,
      .completed,
      "writer failed: \(String(describing: writer.error))"
    )

    let asset = AVURLAsset(url: url)
    let videoTrack = try XCTUnwrap(asset.tracks(withMediaType: .video).first)
    let audioTrack = try XCTUnwrap(asset.tracks(withMediaType: .audio).first)
    let writerDelta = abs(
      CMTimeGetSeconds(CMTimeSubtract(
        audioTrack.timeRange.duration,
        videoTrack.timeRange.duration
      ))
    )
    XCTAssertLessThanOrEqual(writerDelta, 0.060)
  }

  private func buildAdjustedTimelines() throws -> (
    video: [CMTime],
    audio: [CMTime]
  ) {
    var events: [SourceEvent] = []
    for frame in 0...(8 * 30) {
      events.append(SourceEvent(
        kind: .video,
        sourceTime: CMTime(value: CMTimeValue(frame), timescale: 30)
      ))
    }
    let audioBufferCount = Int(8.0 * 44_100.0 / 1_024.0)
    for buffer in 0...audioBufferCount {
      events.append(SourceEvent(
        kind: .audio,
        sourceTime: CMTime(
          value: CMTimeValue(buffer * 1_024),
          timescale: 44_100
        )
      ))
    }
    events.sort {
      if $0.seconds == $1.seconds { return $0.kind == .video }
      return $0.seconds < $1.seconds
    }

    var videoTimeline = MediaTimelineState()
    var audioTimeline = MediaTimelineState()
    var adjustedVideo: [CMTime] = []
    var adjustedAudio: [CMTime] = []
    let switchStarts = [2.0, 4.0, 6.0]
    var nextSwitchIndex = 0
    var stableVideoAfter: Double?
    var audioReleasePending = false

    for event in events {
      if nextSwitchIndex < switchStarts.count,
         event.seconds >= switchStarts[nextSwitchIndex] {
        videoTimeline.markDiscontinuity()
        audioTimeline.markDiscontinuity()
        stableVideoAfter = switchStarts[nextSwitchIndex] + 0.300
        nextSwitchIndex += 1
      }

      if let requiredStableVideoTime = stableVideoAfter {
        if event.kind == .video, event.seconds >= requiredStableVideoTime {
          let sharedGap = try XCTUnwrap(
            videoTimeline.consumePendingDiscontinuityGap(
              at: event.sourceTime
            )
          )
          audioTimeline.applyPendingDiscontinuityGap(sharedGap)
          stableVideoAfter = nil
          audioReleasePending = true
        }
        continue
      }

      if event.kind == .audio, audioReleasePending {
        audioTimeline.observeDroppedSample(at: event.sourceTime)
        audioReleasePending = false
        continue
      }

      let decision = event.kind == .video
        ? videoTimeline.adjustedTime(for: event.sourceTime)
        : audioTimeline.adjustedTime(for: event.sourceTime)
      guard case .append(let adjustedTime) = decision else { continue }
      if event.kind == .video {
        adjustedVideo.append(adjustedTime)
      } else {
        adjustedAudio.append(adjustedTime)
      }
    }

    return (adjustedVideo, adjustedAudio)
  }

  private func makePixelBuffer() throws -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      64,
      64,
      kCVPixelFormatType_32BGRA,
      [
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
      ] as CFDictionary,
      &pixelBuffer
    )
    XCTAssertEqual(status, kCVReturnSuccess)
    let buffer = try XCTUnwrap(pixelBuffer)
    CVPixelBufferLockBaseAddress(buffer, [])
    if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
      memset(baseAddress, 0x22, CVPixelBufferGetDataSize(buffer))
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    return buffer
  }

  private func makePCMSampleBuffer(startPTS: CMTime) throws -> CMSampleBuffer {
    let sampleRate = 44_100.0
    let channels: UInt32 = 1
    let framesPerBuffer = 1_024
    var asbd = AudioStreamBasicDescription(
      mSampleRate: sampleRate,
      mFormatID: kAudioFormatLinearPCM,
      mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
      mBytesPerPacket: 2,
      mFramesPerPacket: 1,
      mBytesPerFrame: 2,
      mChannelsPerFrame: channels,
      mBitsPerChannel: 16,
      mReserved: 0
    )
    var formatDescription: CMAudioFormatDescription?
    XCTAssertEqual(
      CMAudioFormatDescriptionCreate(
        allocator: kCFAllocatorDefault,
        asbd: &asbd,
        layoutSize: 0,
        layout: nil,
        magicCookieSize: 0,
        magicCookie: nil,
        extensions: nil,
        formatDescriptionOut: &formatDescription
      ),
      noErr
    )

    let byteCount = framesPerBuffer * 2
    var blockBuffer: CMBlockBuffer?
    XCTAssertEqual(
      CMBlockBufferCreateWithMemoryBlock(
        allocator: kCFAllocatorDefault,
        memoryBlock: nil,
        blockLength: byteCount,
        blockAllocator: kCFAllocatorDefault,
        customBlockSource: nil,
        offsetToData: 0,
        dataLength: byteCount,
        flags: 0,
        blockBufferOut: &blockBuffer
      ),
      noErr
    )
    let silence = [UInt8](repeating: 0, count: byteCount)
    let unwrappedBlockBuffer = try XCTUnwrap(blockBuffer)
    XCTAssertEqual(
      silence.withUnsafeBytes {
        CMBlockBufferReplaceDataBytes(
          with: $0.baseAddress!,
          blockBuffer: unwrappedBlockBuffer,
          offsetIntoDestination: 0,
          dataLength: byteCount
        )
      },
      noErr
    )

    var sampleBuffer: CMSampleBuffer?
    XCTAssertEqual(
      CMAudioSampleBufferCreateReadyWithPacketDescriptions(
        allocator: kCFAllocatorDefault,
        dataBuffer: unwrappedBlockBuffer,
        formatDescription: try XCTUnwrap(formatDescription),
        sampleCount: framesPerBuffer,
        presentationTimeStamp: startPTS,
        packetDescriptions: nil,
        sampleBufferOut: &sampleBuffer
      ),
      noErr
    )
    return try XCTUnwrap(sampleBuffer)
  }
}

// MARK: - AVAssetWriter audio-gap behavior probe
//
// PURPOSE
// The audio route-switch A/V-sync review (diagnostics/audio-route-switch-sync-review-2026-06-07.md)
// proposes compressing the audio-only route gap by subtracting an accumulated `audioTimeOffset`
// from audio PTS. Whether that fix is correct or BACKWARDS depends entirely on one unverified
// fact: when you append audio sample buffers with a forward jump in PTS (a gap) to an
// AVAssetWriterInput, does the writer...
//
//   (A) HONOR the gap  -> the audio track keeps a silent hole and post-gap audio stays
//                         time-aligned with a continuous video track. If so, the current
//                         plugin code is ALREADY correct for sync, and subtracting
//                         `audioTimeOffset` would pull post-gap audio EARLIER and DESYNC it
//                         (audio leads video, accumulating per switch).
//
//   (B) SWALLOW the gap -> the writer concatenates audio back-to-back, so post-gap audio
//                          lands EARLIER than its true PTS (audio leads video). In that case
//                          the correct fix is to INSERT SILENCE for the gap, not subtract an
//                          offset.
//
// In neither case does the proposed subtract-offset fix help. This probe writes exactly that
// scenario and reads the file back to decide A vs B from real numbers instead of inference.
//
// HOW TO RUN
//   cd example/ios
//   xcodebuild test \
//     -workspace Runner.xcworkspace -scheme Runner \
//     -destination 'platform=iOS Simulator,name=iPhone 15' \
//     -only-testing:RunnerTests/AudioGapBehaviorTests
//   (or run from Xcode's Test navigator). Read the "[GAP-PROBE]" lines in the test log.

final class AudioGapBehaviorTests: XCTestCase {

  private struct GapProbeResult {
    let firstPTS: Double
    let lastSampleEnd: Double
    let totalSpan: Double
    let maxInternalGap: Double
    let sampleCount: Int
    let trackTimeRangeDuration: Double
    let writerError: String?
  }

  // Scenario geometry (kept identical for both codecs so verdicts compare cleanly).
  private let sampleRate = 44100.0
  private let channels: UInt32 = 1
  private let framesPerBuffer = 1024
  private let runSeconds = 0.5      // audio present for [0, 0.5) and [1.0, 1.5)
  private let gapStartSeconds = 1.0 // second run starts here -> ~0.5s silent gap

  func testAACWriterGapBehavior() throws {
    // Production-relevant: the plugin's audio AVAssetWriterInput uses kAudioFormatMPEG4AAC.
    let result = try runAudioGapProbe(formatID: kAudioFormatMPEG4AAC, label: "AAC")
    reportVerdict(result, label: "AAC (matches plugin's audio writer settings)")
  }

  func testLinearPCMWriterGapBehavior() throws {
    // Uncompressed baseline: isolates the writer's raw gap handling from any AAC
    // encoder priming/padding. If AAC and PCM disagree, the difference is the encoder.
    let result = try runAudioGapProbe(formatID: kAudioFormatLinearPCM, label: "LinearPCM")
    reportVerdict(result, label: "LinearPCM (uncompressed baseline)")
  }

  // MARK: - Probe

  private func runAudioGapProbe(formatID: AudioFormatID, label: String) throws -> GapProbeResult {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("gapprobe_\(label)_\(UUID().uuidString).mov")
    try? FileManager.default.removeItem(at: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let writer = try AVAssetWriter(url: url, fileType: .mov)

    let audioSettings: [String: Any]
    if formatID == kAudioFormatMPEG4AAC {
      audioSettings = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: Int(channels),
        AVEncoderBitRateKey: 128000,
      ]
    } else {
      audioSettings = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: Int(channels),
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsNonInterleaved: false,
      ]
    }

    let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
    input.expectsMediaDataInRealTime = false
    XCTAssertTrue(writer.canAdd(input), "[\(label)] cannot add audio input")
    writer.add(input)
    XCTAssertTrue(writer.startWriting(), "[\(label)] startWriting failed: \(String(describing: writer.error))")
    writer.startSession(atSourceTime: .zero)

    // Build run 1 [0, runSeconds), then run 2 [gapStartSeconds, gapStartSeconds + runSeconds).
    let buffersPerRun = Int((runSeconds * sampleRate) / Double(framesPerBuffer))
    var buffers: [CMSampleBuffer] = []
    for i in 0..<buffersPerRun {
      let pts = CMTime(value: CMTimeValue(i * framesPerBuffer), timescale: CMTimeScale(sampleRate))
      if let b = makePCMSampleBuffer(startPTS: pts) { buffers.append(b) }
    }
    let gapStartFrames = Int(gapStartSeconds * sampleRate)
    for i in 0..<buffersPerRun {
      let pts = CMTime(value: CMTimeValue(gapStartFrames + i * framesPerBuffer), timescale: CMTimeScale(sampleRate))
      if let b = makePCMSampleBuffer(startPTS: pts) { buffers.append(b) }
    }

    for b in buffers {
      var guardCounter = 0
      while !input.isReadyForMoreMediaData && guardCounter < 10000 {
        usleep(200)
        guardCounter += 1
      }
      XCTAssertTrue(input.append(b), "[\(label)] append failed: \(String(describing: writer.error))")
    }
    input.markAsFinished()

    let finishExp = expectation(description: "finishWriting \(label)")
    writer.finishWriting { finishExp.fulfill() }
    wait(for: [finishExp], timeout: 15)

    let writerError = writer.error?.localizedDescription
    XCTAssertEqual(writer.status, .completed, "[\(label)] writer not completed: \(String(describing: writerError))")

    // Read the produced file back and measure the real audio timeline.
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .audio).first else {
      throw NSError(domain: "gapprobe", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "[\(label)] no audio track in output"])
    }
    let trackDuration = CMTimeGetSeconds(track.timeRange.duration)

    let reader = try AVAssetReader(asset: asset)
    let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    reader.add(trackOutput)
    XCTAssertTrue(reader.startReading(), "[\(label)] reader failed: \(String(describing: reader.error))")

    var firstPTS = Double.nan
    var lastEnd = 0.0
    var prevEnd: Double? = nil
    var maxInternalGap = 0.0
    var sampleCount = 0

    while let sb = trackOutput.copyNextSampleBuffer() {
      let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
      var dur = CMTimeGetSeconds(CMSampleBufferGetDuration(sb))
      if dur.isNaN || dur <= 0 {
        dur = Double(CMSampleBufferGetNumSamples(sb)) / sampleRate
      }
      if firstPTS.isNaN { firstPTS = pts }
      if let pe = prevEnd {
        let internalGap = pts - pe
        if internalGap > maxInternalGap { maxInternalGap = internalGap }
      }
      prevEnd = pts + dur
      lastEnd = pts + dur
      sampleCount += 1
    }

    if firstPTS.isNaN { firstPTS = 0 }
    return GapProbeResult(
      firstPTS: firstPTS,
      lastSampleEnd: lastEnd,
      totalSpan: lastEnd - firstPTS,
      maxInternalGap: maxInternalGap,
      sampleCount: sampleCount,
      trackTimeRangeDuration: trackDuration,
      writerError: writerError
    )
  }

  // MARK: - Verdict

  private func reportVerdict(_ r: GapProbeResult, label: String) {
    // Honored: track spans ~1.5s with a ~0.5s internal gap.
    // Swallowed: track spans ~1.0s with no meaningful internal gap.
    let honorsGap = r.maxInternalGap > 0.25 || r.totalSpan > 1.25
    let verdict: String
    if honorsGap {
      verdict = """
      AVAssetWriter HONORS the PTS gap (silent hole preserved; post-gap audio stays aligned).
      => The CURRENT plugin code is already correct for A/V sync. Subtracting `audioTimeOffset`
         would shift post-gap audio EARLIER and CREATE an audio-leads-video desync that
         accumulates per route switch. DO NOT implement the proposed compression fix.
         If desync is still observed, the cause is elsewhere (resampler re-prime / shared
         _lastSampleTime / video offset), not an un-compressed audio gap.
      """
    } else {
      verdict = """
      AVAssetWriter SWALLOWS the PTS gap (audio concatenated; post-gap audio lands earlier).
      => The current code already makes audio LEAD video by the gap (accumulating per switch).
         The proposed subtract-offset fix is still wrong (it pulls audio earlier again / is a
         no-op on swallowed gaps). The correct fix is to INSERT SILENCE for the measured gap so
         audio stays aligned with the continuous video track.
      """
    }

    NSLog("%@", """

    ===================== [GAP-PROBE] \(label) =====================
    firstPTS=\(fmt(r.firstPTS))s  lastSampleEnd=\(fmt(r.lastSampleEnd))s  totalSpan=\(fmt(r.totalSpan))s
    maxInternalGap=\(fmt(r.maxInternalGap))s  trackTimeRange.duration=\(fmt(r.trackTimeRangeDuration))s  samplesRead=\(r.sampleCount)
    writerError=\(r.writerError ?? "none")
    Expected if HONORED:   totalSpan ~= 1.49s, maxInternalGap ~= 0.5s
    Expected if SWALLOWED: totalSpan ~= 0.98s, maxInternalGap ~= 0.0s
    VERDICT:
    \(verdict)
    ================================================================

    """)

    XCTAssertGreaterThan(r.sampleCount, 0, "[\(label)] no audio samples were read back")
    // Sanity: the timeline must resemble one of the two known shapes, not garbage.
    let looksHonored = r.totalSpan > 1.25
    let looksSwallowed = r.totalSpan > 0.75 && r.totalSpan <= 1.25
    XCTAssertTrue(looksHonored || looksSwallowed,
                  "[\(label)] unexpected totalSpan=\(r.totalSpan)s — neither honored (~1.5s) nor swallowed (~1.0s)")
  }

  private func fmt(_ v: Double) -> String { String(format: "%.4f", v) }

  // MARK: - Synthetic PCM buffer

  /// Builds a 16-bit signed-integer mono PCM CMSampleBuffer of `framesPerBuffer` frames,
  /// filled with a quiet 440Hz tone (so it isn't pure silence), stamped at `startPTS`.
  /// This mirrors the 16-bit PCM the plugin's resampled path feeds the AAC writer input.
  private func makePCMSampleBuffer(startPTS: CMTime) -> CMSampleBuffer? {
    var asbd = AudioStreamBasicDescription(
      mSampleRate: sampleRate,
      mFormatID: kAudioFormatLinearPCM,
      mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
      mBytesPerPacket: UInt32(2 * channels),
      mFramesPerPacket: 1,
      mBytesPerFrame: UInt32(2 * channels),
      mChannelsPerFrame: channels,
      mBitsPerChannel: 16,
      mReserved: 0
    )

    var formatDesc: CMAudioFormatDescription?
    guard CMAudioFormatDescriptionCreate(
      allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
      magicCookieSize: 0, magicCookie: nil, extensions: nil,
      formatDescriptionOut: &formatDesc) == noErr, let fmt = formatDesc
    else { return nil }

    let totalSamples = framesPerBuffer * Int(channels)
    let byteCount = totalSamples * 2
    let data = UnsafeMutablePointer<Int16>.allocate(capacity: totalSamples)
    defer { data.deallocate() }

    let omega = 2.0 * Double.pi * 440.0 / sampleRate
    for f in 0..<framesPerBuffer {
      let v = Int16(sin(Double(f) * omega) * 8000.0)
      for c in 0..<Int(channels) { data[f * Int(channels) + c] = v }
    }

    var blockBuffer: CMBlockBuffer?
    guard CMBlockBufferCreateWithMemoryBlock(
      allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: byteCount,
      blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
      offsetToData: 0, dataLength: byteCount, flags: 0,
      blockBufferOut: &blockBuffer) == noErr, let block = blockBuffer
    else { return nil }

    guard CMBlockBufferReplaceDataBytes(
      with: data, blockBuffer: block, offsetIntoDestination: 0,
      dataLength: byteCount) == noErr
    else { return nil }

    var sampleBuffer: CMSampleBuffer?
    guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
      allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: fmt,
      sampleCount: CMItemCount(framesPerBuffer), presentationTimeStamp: startPTS,
      packetDescriptions: nil, sampleBufferOut: &sampleBuffer) == noErr
    else { return nil }

    return sampleBuffer
  }
}
