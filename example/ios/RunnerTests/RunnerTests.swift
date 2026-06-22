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
