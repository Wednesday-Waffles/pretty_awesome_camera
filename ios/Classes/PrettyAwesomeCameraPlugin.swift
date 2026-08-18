import Flutter
import UIKit
import AVFoundation
import os.lock

enum MediaTimelineAppendDecision {
    case append(CMTime)
    case dropInvalidSourceTime
    case dropNonMonotonic(candidate: CMTime, previous: CMTime)
}

/// Per-writer-input presentation-time state.
///
/// Audio and video are delivered on independent queues and their source PTS
/// values are not globally ordered. Keeping this state per media track prevents
/// one track from calculating or consuming the other track's discontinuity.
struct MediaTimelineState {
    private(set) var timeOffset: CMTime = .zero
    private(set) var lastSourceTime: CMTime?
    private(set) var lastAdjustedTime: CMTime?
    private(set) var discontinuityPending = false

    mutating func reset() {
        self = MediaTimelineState()
    }

    mutating func markDiscontinuity() {
        guard lastSourceTime != nil else { return }
        discontinuityPending = true
    }

    /// Consumes the first valid sample after a pause or camera switch, removes
    /// that track's source-time gap, and drops the transitional sample.
    mutating func consumePendingDiscontinuity(at sourceTime: CMTime) -> Bool {
        guard discontinuityPending else { return false }
        guard sourceTime.isNumeric else { return true }

        _ = consumePendingDiscontinuityGap(at: sourceTime)
        return true
    }

    /// Consumes a pending boundary and returns the positive gap applied to this
    /// timeline. Camera switching uses the video-derived gap for both tracks so
    /// their offsets cannot diverge by callback-grid quantization on each flip.
    mutating func consumePendingDiscontinuityGap(at sourceTime: CMTime) -> CMTime? {
        guard discontinuityPending, sourceTime.isNumeric else { return nil }

        var appliedGap = CMTime.zero
        if let lastSourceTime {
            let gap = CMTimeSubtract(sourceTime, lastSourceTime)
            if gap.isNumeric && CMTimeCompare(gap, .zero) > 0 {
                timeOffset = CMTimeAdd(timeOffset, gap)
                appliedGap = gap
            }
        }

        discontinuityPending = false
        lastSourceTime = sourceTime
        return appliedGap
    }

    /// Applies a camera-switch gap calculated by the video boundary. Unlike a
    /// track-local consume, this deliberately leaves `lastSourceTime` unchanged
    /// so the first released audio sample can be appended on the shared clock.
    mutating func applyPendingDiscontinuityGap(_ gap: CMTime) {
        guard discontinuityPending else { return }
        if gap.isNumeric && CMTimeCompare(gap, .zero) > 0 {
            timeOffset = CMTimeAdd(timeOffset, gap)
        }
        discontinuityPending = false
    }

    /// Records a deliberately dropped sample without compressing its gap. Used
    /// for audio-route transitions where video continues on the original clock.
    mutating func observeDroppedSample(at sourceTime: CMTime) {
        guard sourceTime.isNumeric else { return }
        lastSourceTime = sourceTime
    }

    /// Returns a track-local adjusted PTS, rejecting a timestamp that would
    /// violate AVAssetWriterInput's monotonic ordering requirement.
    mutating func adjustedTime(for sourceTime: CMTime) -> MediaTimelineAppendDecision {
        guard sourceTime.isNumeric else { return .dropInvalidSourceTime }

        let adjustedTime = CMTimeSubtract(sourceTime, timeOffset)
        guard adjustedTime.isNumeric else { return .dropInvalidSourceTime }

        if let previous = lastAdjustedTime,
           CMTimeCompare(adjustedTime, previous) <= 0 {
            return .dropNonMonotonic(candidate: adjustedTime, previous: previous)
        }

        lastSourceTime = sourceTime
        lastAdjustedTime = adjustedTime
        return .append(adjustedTime)
    }
}

/// Owns the video callback boundary around capture-session reconfiguration.
///
/// While a switch is being configured, every frame is dropped without
/// consuming the post-switch stabilization budget. A successful switch then
/// drops a fixed number of frames from the new camera; a rejected switch
/// releases the old camera immediately.
struct CameraSwitchFrameGate {
    private(set) var isSwitchInProgress = false
    private(set) var stabilizationFramesRemaining = 0
    private(set) var generation: UInt64 = 0
    private var generationBeforeSwitch: UInt64?
    private var stabilizationFramesBeforeSwitch: Int?

    mutating func prepare() -> UInt64 {
        generationBeforeSwitch = generation
        stabilizationFramesBeforeSwitch = stabilizationFramesRemaining
        generation &+= 1
        isSwitchInProgress = true
        stabilizationFramesRemaining = 0
        return generation
    }

    mutating func complete(stabilizationFrameCount: Int) {
        generationBeforeSwitch = nil
        stabilizationFramesBeforeSwitch = nil
        isSwitchInProgress = false
        stabilizationFramesRemaining = max(0, stabilizationFrameCount)
    }

    mutating func cancel() {
        if let generationBeforeSwitch {
            generation = generationBeforeSwitch
        }
        if let stabilizationFramesBeforeSwitch {
            stabilizationFramesRemaining = stabilizationFramesBeforeSwitch
        }
        generationBeforeSwitch = nil
        stabilizationFramesBeforeSwitch = nil
        isSwitchInProgress = false
    }

    mutating func shouldDropFrame() -> Bool {
        if isSwitchInProgress {
            return true
        }
        guard stabilizationFramesRemaining > 0 else {
            return false
        }
        stabilizationFramesRemaining -= 1
        return true
    }

    var isDroppingFrames: Bool {
        isSwitchInProgress || stabilizationFramesRemaining > 0
    }
}

/// Recording-lock-owned audio suppression for capture-session reconfiguration.
///
/// Video callbacks stop before `beginConfiguration()`. Audio must stop at the
/// same boundary or every successful switch advances audio relative to video by
/// the reconfiguration duration. The existing generation gate continues to
/// suppress audio after commit until the first stable new-camera video frame.
struct CameraSwitchAudioGate {
    private(set) var isHolding = false
    private var startedAtUptime: TimeInterval?

    mutating func begin(at uptime: TimeInterval) {
        guard !isHolding else { return }
        isHolding = true
        startedAtUptime = uptime
    }

    /// Releases the gate and returns the measured hold duration in milliseconds.
    @discardableResult
    mutating func release(at uptime: TimeInterval) -> Int? {
        guard isHolding else { return nil }
        defer { reset() }
        guard let startedAtUptime else { return nil }
        return max(0, Int(((uptime - startedAtUptime) * 1000).rounded()))
    }

    mutating func reset() {
        isHolding = false
        startedAtUptime = nil
    }
}

public class PrettyAwesomeCameraPlugin: NSObject, FlutterPlugin {
    static let targetVideoFrameRate: Int = 30
    // Sanity ceiling for caller-supplied encoder bitrates — AVAssetWriter fails
    // startWriting() on absurd values, which would otherwise surface only as a
    // silent no-output recording. Matches Android's MAX_VIDEO_BITRATE_BPS.
    static let maxVideoBitrateBps: Int = 100_000_000
    static let stableRecordingAudioSampleRate: Double = 44100
    static let stableRecordingAudioChannelCount: UInt32 = 1
    static let stableRecordingAudioBitRate: Int = 128000
    // Audio buffers arrive at ~43-48/s (1024-frame buffers at 44.1/48 kHz);
    // emitting every 11 buffers throttles the level stream to ~4 Hz without
    // needing a timer.
    static let audioLevelEmitEveryNBuffers: Int = 11

    private var cameras: [Int: CameraInstance] = [:]
    private var nextCameraId = 0
    private var textureRegistry: FlutterTextureRegistry?
    private var eventChannels: [Int: FlutterEventChannel] = [:]
    private var streamHandlers: [Int: RecordingStateStreamHandler] = [:]
    private var audioEventChannels: [Int: FlutterEventChannel] = [:]
    private var audioStreamHandlers: [Int: AudioDeviceStreamHandler] = [:]
    private var audioLevelEventChannels: [Int: FlutterEventChannel] = [:]
    private var audioLevelStreamHandlers: [Int: AudioLevelStreamHandler] = [:]
    private var registrar: FlutterPluginRegistrar?
    private let sessionQueue = DispatchQueue(label: "com.prettyawesome.camera.session")
    private var stateLock = os_unfair_lock()
    private var isAudioSessionConfigured = false
    
    class CameraInstance {
        let cameraId: Int
        var captureSession: AVCaptureSession?
        var previewTexture: CameraPreviewTexture?
        var textureId: Int64?
        var lensPosition: AVCaptureDevice.Position = .back
        var videoInput: AVCaptureDeviceInput?
        var requestedPresetName: String = "high"
        var videoBitrate: Int?
        var capturePreset: AVCaptureSession.Preset = .hd1280x720
        var captureDimensions: CMVideoDimensions = CMVideoDimensions(width: 1280, height: 720)
        var zoomFactor: CGFloat = 1.0
        var recordingURL: URL?
        var assetWriter: AVAssetWriter?
        var videoWriterInput: AVAssetWriterInput?
        var audioWriterInput: AVAssetWriterInput?
        var audioDataOutput: AVCaptureAudioDataOutput?
        // Audio-level metering accumulators. Confined to the audio delegate's
        // serial queue — do NOT touch from other threads and do NOT take
        // recordingLock for them.
        fileprivate var meteringBufferCount: Int = 0
        fileprivate var meteringWindowPeak: Float = 0
        fileprivate var meteringSumSquares: Double = 0
        fileprivate var meteringSampleCount: Int = 0
        fileprivate var recordingLock = os_unfair_lock()
        fileprivate var _isRecording: Bool = false
        fileprivate var _isPaused: Bool = false
        fileprivate var _recordingWarmupFramesRemaining: Int = 0
        fileprivate var _hasPrewarmedRecordingPipeline: Bool = false
        fileprivate var _videoTimeline = MediaTimelineState()
        fileprivate var _audioTimeline = MediaTimelineState()
        fileprivate var _cameraSwitchAudioGate = CameraSwitchAudioGate()
        fileprivate var _cameraSwitchAudioReleasePending = false
        // Keeps audio from consuming its post-switch discontinuity before the
        // video pipeline has delivered a stable frame from the new camera.
        fileprivate var _cameraSwitchGenerationPending: UInt64?
        // Low-cardinality recording diagnostics. These counters never
        // participate in capture or timestamp decisions.
        fileprivate var _cameraSwitchCommittedCount = 0
        fileprivate var _cameraSwitchRejectedCount = 0
        fileprivate var _cameraSwitchConfigurationTotalMs = 0
        fileprivate var _cameraSwitchConfigurationMaxMs = 0
        fileprivate var _cameraSwitchAudioHoldTotalMs = 0
        fileprivate var _cameraSwitchAudioHoldMaxMs = 0
        fileprivate var _cameraSwitchHeldAudioSampleCount = 0
        // Wall-clock time removed from the media timeline by camera-switch
        // boundaries (the shared video-derived gap applied to both tracks).
        // Pause compression is excluded on purpose: the client's recording
        // timer already stops during pauses, so expected-duration math only
        // needs the switch-attributed portion.
        fileprivate var _cameraSwitchTimelineCompressionMs = 0
        fileprivate var _videoNonMonotonicDropCount = 0
        fileprivate var _audioNonMonotonicDropCount = 0
        fileprivate var _videoAppendFailureCount = 0
        fileprivate var _audioAppendFailureCount = 0
        fileprivate var _isFirstVideoFrame: Bool = true
        fileprivate var _isFirstAudioFrame: Bool = true
        fileprivate var _sessionStartTime: CMTime = .zero
        fileprivate var _audioRouteDiscontinuityPending: Bool = false
        // Diagnostics-only (NOT used in timestamp math). Tracks the PTS of the last
        // processed audio sample and how many audio route switches occurred so we can
        // log the real audio-only gap size and converter re-prime cadence per switch.
        // Removing these has no effect on recording behavior.
        fileprivate var _lastAcceptedAudioSampleTime: CMTime = .zero
        fileprivate var _audioRouteSwitchCount: Int = 0
        var activeFrameRateMin: CMTime?
        var activeFrameRateMax: CMTime?
        var actualAudioSampleRate: Double = 44100
        var recordingAudioSampleRate: Double = 0
        var recordingAudioChannelCount: UInt32 = 1
        var audioConverter: AVAudioConverter?
        var audioConverterInputFormat: AVAudioFormat?

        func resetAudioConverterLocked() {
            audioConverter = nil
            audioConverterInputFormat = nil
        }
        
        func resetAudioConverter() {
            os_unfair_lock_lock(&recordingLock)
            resetAudioConverterLocked()
            os_unfair_lock_unlock(&recordingLock)
        }

        init(cameraId: Int) {
            self.cameraId = cameraId
        }
        
        var isRecording: Bool {
            get {
                os_unfair_lock_lock(&recordingLock)
                defer { os_unfair_lock_unlock(&recordingLock) }
                return _isRecording
            }
            set {
                os_unfair_lock_lock(&recordingLock)
                _isRecording = newValue
                os_unfair_lock_unlock(&recordingLock)
            }
        }
        
        var isPaused: Bool {
            get {
                os_unfair_lock_lock(&recordingLock)
                defer { os_unfair_lock_unlock(&recordingLock) }
                return _isPaused
            }
            set {
                os_unfair_lock_lock(&recordingLock)
                _isPaused = newValue
                os_unfair_lock_unlock(&recordingLock)
            }
        }
        
        var recordingWarmupFramesRemaining: Int {
            get {
                os_unfair_lock_lock(&recordingLock)
                defer { os_unfair_lock_unlock(&recordingLock) }
                return _recordingWarmupFramesRemaining
            }
            set {
                os_unfair_lock_lock(&recordingLock)
                _recordingWarmupFramesRemaining = newValue
                os_unfair_lock_unlock(&recordingLock)
            }
        }

        var hasPrewarmedRecordingPipeline: Bool {
            get {
                os_unfair_lock_lock(&recordingLock)
                defer { os_unfair_lock_unlock(&recordingLock) }
                return _hasPrewarmedRecordingPipeline
            }
            set {
                os_unfair_lock_lock(&recordingLock)
                _hasPrewarmedRecordingPipeline = newValue
                os_unfair_lock_unlock(&recordingLock)
            }
        }

        var isFirstVideoFrame: Bool {
            get {
                os_unfair_lock_lock(&recordingLock)
                defer { os_unfair_lock_unlock(&recordingLock) }
                return _isFirstVideoFrame
            }
            set {
                os_unfair_lock_lock(&recordingLock)
                _isFirstVideoFrame = newValue
                os_unfair_lock_unlock(&recordingLock)
            }
        }

        var isFirstAudioFrame: Bool {
            get {
                os_unfair_lock_lock(&recordingLock)
                defer { os_unfair_lock_unlock(&recordingLock) }
                return _isFirstAudioFrame
            }
            set {
                os_unfair_lock_lock(&recordingLock)
                _isFirstAudioFrame = newValue
                os_unfair_lock_unlock(&recordingLock)
            }
        }

        var sessionStartTime: CMTime {
            get {
                os_unfair_lock_lock(&recordingLock)
                defer { os_unfair_lock_unlock(&recordingLock) }
                return _sessionStartTime
            }
            set {
                os_unfair_lock_lock(&recordingLock)
                _sessionStartTime = newValue
                os_unfair_lock_unlock(&recordingLock)
            }
        }

    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "pretty_awesome_camera", binaryMessenger: registrar.messenger())
        let instance = PrettyAwesomeCameraPlugin()
        instance.textureRegistry = registrar.textures()
        instance.registrar = registrar
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getAvailableCameras":
            getAvailableCameras(result: result)
        case "createCamera":
            createCamera(call: call, result: result)
        case "initializeCamera":
            initializeCamera(call: call, result: result)
        case "disposeCamera":
            disposeCamera(call: call, result: result)
        case "startRecording":
            startRecording(call: call, result: result)
        case "getRecordingSettings":
            getRecordingSettings(call: call, result: result)
        case "pauseRecording":
            pauseRecording(call: call, result: result)
        case "resumeRecording":
            resumeRecording(call: call, result: result)
        case "setZoom":
            setZoom(call: call, result: result)
        case "stopRecording":
            stopRecording(call: call, result: result)
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        case "isMultiCamSupported":
            result(AVCaptureMultiCamSession.isMultiCamSupported)
        case "canSwitchCamera":
            canSwitchCamera(call: call, result: result)
        case "switchCamera":
            switchCamera(call: call, result: result)
        case "canSwitchCurrentCamera":
            canSwitchCurrentCamera(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func getAvailableCameras(result: @escaping FlutterResult) {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        
        let devices = discoverySession.devices.map { device -> [String: Any] in
            let lensDirection: String
            switch device.position {
            case .front:
                lensDirection = "front"
            case .back:
                lensDirection = "back"
            default:
                lensDirection = "external"
            }
            
            return [
                "name": device.localizedName,
                "lensDirection": lensDirection,
                "sensorOrientation": 90
            ]
        }
        
        result(devices)
    }
    
    private func createCamera(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        let cameraDescription = args?["camera"] as? [String: Any]
        
        let lensDirection = cameraDescription?["lensDirection"] as? String ?? "front"
        let position: AVCaptureDevice.Position = lensDirection == "front" ? .front : .back
        let presetName = (args?["preset"] as? String) ?? "high"
        let videoBitrate: Int?
        if let videoBitrateValue = args?["videoBitrate"] {
            guard let videoBitrateNumber = videoBitrateValue as? NSNumber,
                  CFGetTypeID(videoBitrateNumber) != CFBooleanGetTypeID(),
                  !CFNumberIsFloatType(videoBitrateNumber) else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "videoBitrate must be an integer", details: nil))
                return
            }
            let parsedVideoBitrate = videoBitrateNumber.intValue
            guard parsedVideoBitrate > 0 else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "videoBitrate must be greater than zero", details: nil))
                return
            }
            guard parsedVideoBitrate <= Self.maxVideoBitrateBps else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "videoBitrate must be at most \(Self.maxVideoBitrateBps)", details: nil))
                return
            }
            videoBitrate = parsedVideoBitrate
        } else {
            videoBitrate = nil
        }

        let cameraId = nextCameraId
        nextCameraId += 1
        
        let instance = CameraInstance(cameraId: cameraId)
        instance.lensPosition = position
        instance.requestedPresetName = presetName
        instance.videoBitrate = videoBitrate
        
        os_unfair_lock_lock(&stateLock)
        cameras[cameraId] = instance
        os_unfair_lock_unlock(&stateLock)
        
        result(cameraId)
    }

    private func getRecordingSettings(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let cameraId = args["cameraId"] as? Int else {
            result(FlutterError(code: "INVALID_CAMERA", message: "Camera not found or not initialized", details: nil))
            return
        }

        os_unfair_lock_lock(&stateLock)
        guard let cameraInstance = cameras[cameraId] else {
            os_unfair_lock_unlock(&stateLock)
            result(FlutterError(code: "INVALID_CAMERA", message: "Camera not found or not initialized", details: nil))
            return
        }
        let requestedBitrate = cameraInstance.videoBitrate.map { $0 as Any } ?? NSNull()
        let resolvedResolution = "\(cameraInstance.captureDimensions.width)x\(cameraInstance.captureDimensions.height)"
        let capturePreset = cameraInstance.capturePreset.rawValue
        os_unfair_lock_unlock(&stateLock)

        result([
            "requested_bitrate": requestedBitrate,
            "resolved_resolution": resolvedResolution,
            "capture_preset": capturePreset
        ])
    }
    
    private func initializeCamera(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let cameraId = args["cameraId"] as? Int else {
            result(FlutterError(code: "INVALID_CAMERA", message: "Camera not found", details: nil))
            return
        }
        
        os_unfair_lock_lock(&stateLock)
        guard let cameraInstance = cameras[cameraId] else {
            os_unfair_lock_unlock(&stateLock)
            result(FlutterError(code: "INVALID_CAMERA", message: "Camera not found", details: nil))
            return
        }
        os_unfair_lock_unlock(&stateLock)
        
        if !isAudioSessionConfigured {
            do {
                try activateAudioSessionForRecording()
                isAudioSessionConfigured = true
            } catch {
                result(FlutterError(code: "AUDIO_SESSION_ERROR", message: "Failed to configure audio session: \(error.localizedDescription)", details: nil))
                return
            }
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAudioRouteChange(_:)),
                name: AVAudioSession.routeChangeNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAudioSessionInterruption(_:)),
                name: AVAudioSession.interruptionNotification,
                object: nil
            )
        }
        
        let captureSession = AVCaptureSession()
        captureSession.automaticallyConfiguresApplicationAudioSession = false
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraInstance.lensPosition) else {
            result(FlutterError(code: "NO_CAMERA", message: "Camera device not available", details: nil))
            return
        }
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
                cameraInstance.videoInput = videoInput
            }
            
            guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
                result(FlutterError(code: "NO_AUDIO_DEVICE", message: "No audio input device available", details: nil))
                return
            }
            
            let audioInput = try AVCaptureDeviceInput(device: audioDevice)
            if captureSession.canAddInput(audioInput) {
                captureSession.addInput(audioInput)
            } else {
                result(FlutterError(code: "AUDIO_INPUT_ERROR", message: "Cannot add audio input to capture session", details: nil))
                return
            }
            
            let audioDataOutput = AVCaptureAudioDataOutput()
            
            let audioQueue = DispatchQueue(label: "com.prettyawesome.camera.audio")
            audioDataOutput.setSampleBufferDelegate(self, queue: audioQueue)
            if captureSession.canAddOutput(audioDataOutput) {
                captureSession.addOutput(audioDataOutput)
            }
            cameraInstance.audioDataOutput = audioDataOutput
            
            cameraInstance.captureSession = captureSession

            let resolvedPreset = resolveCapturePreset(for: cameraInstance.requestedPresetName, session: captureSession)
            captureSession.sessionPreset = resolvedPreset
            // getRecordingSettings reads this preset/dimensions pair under
            // stateLock; take the same lock here so it never observes a torn
            // pair (new preset with old dimensions).
            os_unfair_lock_lock(&stateLock)
            cameraInstance.capturePreset = resolvedPreset
            cameraInstance.captureDimensions = dimensions(for: resolvedPreset)
            os_unfair_lock_unlock(&stateLock)
            
            if let textureRegistry = textureRegistry {
                guard let texture = CameraPreviewTexture(
                    session: captureSession,
                    textureRegistry: textureRegistry,
                    lensPosition: cameraInstance.lensPosition
                ) else {
                    result(FlutterError(code: "TEXTURE_ERROR", message: "Failed to create preview texture", details: nil))
                    return
                }

                texture.onSampleBuffer = { [weak self, weak cameraInstance] sampleBuffer, switchGeneration in
                    guard let self = self, let cameraInstance = cameraInstance else { return }
                    self.handleVideoSampleBuffer(
                        sampleBuffer,
                        switchGeneration: switchGeneration,
                        for: cameraInstance
                    )
                }

                let textureId = textureRegistry.register(texture)
                texture.textureId = textureId
                cameraInstance.textureId = textureId
                cameraInstance.previewTexture = texture
            }
            
            if let registrar = registrar {
                let stateChannel = FlutterEventChannel(
                    name: "pretty_awesome_camera/recording_state_\(cameraId)",
                    binaryMessenger: registrar.messenger()
                )
                let streamHandler = RecordingStateStreamHandler()
                stateChannel.setStreamHandler(streamHandler)
                eventChannels[cameraId] = stateChannel
                streamHandlers[cameraId] = streamHandler

                let audioChannel = FlutterEventChannel(
                    name: "pretty_awesome_camera/audio_device_\(cameraId)",
                    binaryMessenger: registrar.messenger()
                )
                let audioStreamHandler = AudioDeviceStreamHandler()
                audioChannel.setStreamHandler(audioStreamHandler)
                audioEventChannels[cameraId] = audioChannel
                audioStreamHandlers[cameraId] = audioStreamHandler

                let audioLevelChannel = FlutterEventChannel(
                    name: "pretty_awesome_camera/audio_level_\(cameraId)",
                    binaryMessenger: registrar.messenger()
                )
                let audioLevelStreamHandler = AudioLevelStreamHandler()
                audioLevelChannel.setStreamHandler(audioLevelStreamHandler)
                os_unfair_lock_lock(&stateLock)
                audioLevelEventChannels[cameraId] = audioLevelChannel
                audioLevelStreamHandlers[cameraId] = audioLevelStreamHandler
                os_unfair_lock_unlock(&stateLock)
            }

            // Session-level failures (hardware loss, media-services reset) were
            // previously invisible mid-recording. Surface them on the audio
            // event channel so Dart can recover instead of hanging.
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleCaptureSessionRuntimeError(_:)),
                name: .AVCaptureSessionRuntimeError,
                object: captureSession
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleCaptureSessionWasInterrupted(_:)),
                name: .AVCaptureSessionWasInterrupted,
                object: captureSession
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleCaptureSessionInterruptionEnded(_:)),
                name: .AVCaptureSessionInterruptionEnded,
                object: captureSession
            )
            
            sessionQueue.async { [weak self, weak cameraInstance] in
                guard let self = self, let cameraInstance = cameraInstance else { return }
                cameraInstance.previewTexture?.updateForNewCamera(position: cameraInstance.lensPosition)
                cameraInstance.captureSession?.startRunning()
                cameraInstance.previewTexture?.updateForNewCamera(position: cameraInstance.lensPosition)

                self.prewarmRecordingPipeline(for: cameraInstance)
            }
            
            if let textureId = cameraInstance.textureId {
                result(cameraInitializationResult(textureId: textureId, captureDimensions: cameraInstance.captureDimensions))
            } else {
                result(FlutterError(code: "TEXTURE_ERROR", message: "Failed to create texture", details: nil))
            }
        } catch {
            result(FlutterError(code: "INIT_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func disposeCamera(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let cameraId = args["cameraId"] as? Int else {
            result(nil)
            return
        }
        
        os_unfair_lock_lock(&stateLock)
        guard let cameraInstance = cameras[cameraId] else {
            os_unfair_lock_unlock(&stateLock)
            result(nil)
            return
        }
        cameras.removeValue(forKey: cameraId)
        os_unfair_lock_unlock(&stateLock)
        
        if cameraInstance.isRecording, let assetWriter = cameraInstance.assetWriter {
            // Dispose mid-recording is terminal: nobody will ever consume this
            // file, so finish the writer and delete the orphan instead of
            // leaving it in tmp.
            cameraInstance.isRecording = false
            let abandonedURL = cameraInstance.recordingURL
            NSLog("%@", "PrettyAwesomeCameraPlugin: disposeCamera called mid-recording; abandoning and deleting \(abandonedURL?.lastPathComponent ?? "<no file>")")
            if assetWriter.status == .writing {
                assetWriter.finishWriting {
                    if let abandonedURL {
                        try? FileManager.default.removeItem(at: abandonedURL)
                    }
                }
            } else if let abandonedURL {
                try? FileManager.default.removeItem(at: abandonedURL)
            }
            cameraInstance.recordingURL = nil
        }

        if let captureSession = cameraInstance.captureSession {
            NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionRuntimeError, object: captureSession)
            NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionWasInterrupted, object: captureSession)
            NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionInterruptionEnded, object: captureSession)
        }

        cameraInstance.captureSession?.stopRunning()
        cameraInstance.videoInput = nil
        if let textureId = cameraInstance.textureId {
            textureRegistry?.unregisterTexture(textureId)
            cameraInstance.previewTexture?.textureRegistry = nil
        }
        
        if let eventChannel = eventChannels[cameraId] {
            eventChannel.setStreamHandler(nil)
            eventChannels.removeValue(forKey: cameraId)
        }
        streamHandlers.removeValue(forKey: cameraId)
        
        if let audioChannel = audioEventChannels[cameraId] {
            audioChannel.setStreamHandler(nil)
            audioEventChannels.removeValue(forKey: cameraId)
        }
        audioStreamHandlers.removeValue(forKey: cameraId)

        os_unfair_lock_lock(&stateLock)
        let audioLevelChannel = audioLevelEventChannels.removeValue(forKey: cameraId)
        audioLevelStreamHandlers.removeValue(forKey: cameraId)
        os_unfair_lock_unlock(&stateLock)
        audioLevelChannel?.setStreamHandler(nil)

        os_unfair_lock_lock(&stateLock)
        let remainingCameras = cameras.count
        let hasActiveRecording = cameras.values.contains { $0.isRecording }
        os_unfair_lock_unlock(&stateLock)
        
        if remainingCameras == 0 && !hasActiveRecording {
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                isAudioSessionConfigured = false
            } catch {
            }
            
            NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        }

        result(nil)
    }

    private func activateAudioSessionForRecording() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
            .playAndRecord,
            mode: .videoRecording,
            options: [.allowBluetooth, .allowBluetoothA2DP]
        )
        try audioSession.setActive(true)
        isAudioSessionConfigured = true
    }

    static func recordingAudioSettings() -> [String: Any] {
        return [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: stableRecordingAudioSampleRate,
            AVNumberOfChannelsKey: Int(stableRecordingAudioChannelCount),
            AVEncoderBitRateKey: stableRecordingAudioBitRate
        ]
    }

    private func currentAudioRouteEvent(event: String) -> [String: Any] {
        let audioSession = AVAudioSession.sharedInstance()
        let currentRoute = audioSession.currentRoute
        let activeInput = currentRoute.inputs.first
        let deviceName = activeInput?.portName ?? "iPhone Microphone"
        let portType = activeInput?.portType.rawValue ?? "MicrophoneBuiltIn"
        let hasBluetoothInput = currentRoute.inputs.contains { port in
            Self.isBluetoothPort(port.portType)
        }

        return [
            "event": event,
            "deviceName": deviceName,
            "portType": portType,
            "isBluetooth": hasBluetoothInput
        ]
    }

    static func isBluetoothPort(_ portType: AVAudioSession.Port) -> Bool {
        return portType == .bluetoothHFP ||
            portType == .bluetoothA2DP ||
            portType == .bluetoothLE
    }

    private func assetWriterStatusName(_ status: AVAssetWriter.Status) -> String {
        switch status {
        case .unknown:
            return "unknown"
        case .writing:
            return "writing"
        case .completed:
            return "completed"
        case .failed:
            return "failed"
        case .cancelled:
            return "cancelled"
        @unknown default:
            return "unknown_\(status.rawValue)"
        }
    }

    private static func timeMilliseconds(_ time: CMTime?) -> Int? {
        guard let time, time.isNumeric else { return nil }
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite else { return nil }
        return Int((seconds * 1000).rounded())
    }

    /// Caller holds `recordingLock`. Values are diagnostics-only and use
    /// low-cardinality numeric/boolean fields suitable for operational telemetry.
    private func recordingTimelineDiagnosticsLocked(
        _ cameraInstance: CameraInstance
    ) -> [String: Any] {
        let videoOffsetMs = Self.timeMilliseconds(
            cameraInstance._videoTimeline.timeOffset
        ) ?? 0
        let audioOffsetMs = Self.timeMilliseconds(
            cameraInstance._audioTimeline.timeOffset
        ) ?? 0
        let videoLastPtsMs = Self.timeMilliseconds(
            cameraInstance._videoTimeline.lastAdjustedTime
        )
        let audioLastPtsMs = Self.timeMilliseconds(
            cameraInstance._audioTimeline.lastAdjustedTime
        )

        var diagnostics: [String: Any] = [
            "native_timeline_schema_version": 2,
            "native_camera_switch_committed_count": cameraInstance._cameraSwitchCommittedCount,
            "native_camera_switch_rejected_count": cameraInstance._cameraSwitchRejectedCount,
            "native_camera_switch_configuration_total_ms": cameraInstance._cameraSwitchConfigurationTotalMs,
            "native_camera_switch_configuration_max_ms": cameraInstance._cameraSwitchConfigurationMaxMs,
            "native_camera_switch_audio_hold_total_ms": cameraInstance._cameraSwitchAudioHoldTotalMs,
            "native_camera_switch_audio_hold_max_ms": cameraInstance._cameraSwitchAudioHoldMaxMs,
            "native_camera_switch_held_audio_sample_count": cameraInstance._cameraSwitchHeldAudioSampleCount,
            "native_camera_switch_timeline_compression_ms": cameraInstance._cameraSwitchTimelineCompressionMs,
            "native_camera_switch_audio_gate_active_at_stop": cameraInstance._cameraSwitchAudioGate.isHolding,
            "native_camera_switch_audio_release_pending_at_stop": cameraInstance._cameraSwitchAudioReleasePending,
            "native_camera_switch_generation_pending_at_stop": cameraInstance._cameraSwitchGenerationPending != nil,
            "native_video_timeline_offset_ms": videoOffsetMs,
            "native_audio_timeline_offset_ms": audioOffsetMs,
            "native_timeline_offset_delta_ms": audioOffsetMs - videoOffsetMs,
            "native_video_non_monotonic_drop_count": cameraInstance._videoNonMonotonicDropCount,
            "native_audio_non_monotonic_drop_count": cameraInstance._audioNonMonotonicDropCount,
            "native_video_append_failure_count": cameraInstance._videoAppendFailureCount,
            "native_audio_append_failure_count": cameraInstance._audioAppendFailureCount
        ]
        if let videoLastPtsMs {
            diagnostics["native_video_last_adjusted_pts_ms"] = videoLastPtsMs
        }
        if let audioLastPtsMs {
            diagnostics["native_audio_last_adjusted_pts_ms"] = audioLastPtsMs
        }
        if let videoLastPtsMs, let audioLastPtsMs {
            let deltaMs = audioLastPtsMs - videoLastPtsMs
            diagnostics["native_av_last_pts_delta_ms"] = deltaMs
            diagnostics["native_av_last_pts_delta_abs_ms"] = abs(deltaMs)
        }
        return diagnostics
    }

    private func recordingStopErrorDetails(
        cameraInstance: CameraInstance,
        stage: String,
        assetWriter: AVAssetWriter? = nil,
        error: Error? = nil,
        hasAudioConverter: Bool? = nil,
        audioConverterInputFormat: AVAudioFormat? = nil,
        wasPaused: Bool? = nil,
        sessionStarted: Bool? = nil,
        warmupFramesRemaining: Int? = nil,
        isFirstVideoFrame: Bool? = nil,
        isFirstAudioFrame: Bool? = nil
    ) -> [String: Any] {
        let audioSession = AVAudioSession.sharedInstance()
        let currentRoute = audioSession.currentRoute
        let activeInput = currentRoute.inputs.first
        let hasBluetoothInput = currentRoute.inputs.contains { port in
            Self.isBluetoothPort(port.portType)
        }

        os_unfair_lock_lock(&cameraInstance.recordingLock)
        let lockedWasPaused = cameraInstance._isPaused
        let lockedSessionStarted = cameraInstance._sessionStartTime != .zero
        let lockedWarmupFramesRemaining = cameraInstance._recordingWarmupFramesRemaining
        let lockedIsFirstVideoFrame = cameraInstance._isFirstVideoFrame
        let lockedIsFirstAudioFrame = cameraInstance._isFirstAudioFrame
        let audioRouteSwitchCount = cameraInstance._audioRouteSwitchCount
        let hasPrewarmedRecordingPipeline = cameraInstance._hasPrewarmedRecordingPipeline
        let lockedHasAudioConverter = cameraInstance.audioConverter != nil
        let lockedAudioConverterInputFormat = cameraInstance.audioConverterInputFormat
        let actualAudioSampleRate = cameraInstance.actualAudioSampleRate
        let recordingAudioSampleRate = cameraInstance.recordingAudioSampleRate
        let recordingAudioChannelCount = cameraInstance.recordingAudioChannelCount
        let timelineDiagnostics = recordingTimelineDiagnosticsLocked(cameraInstance)
        os_unfair_lock_unlock(&cameraInstance.recordingLock)

        let effectiveHasAudioConverter = hasAudioConverter ?? lockedHasAudioConverter
        let effectiveAudioConverterInputFormat = audioConverterInputFormat ?? lockedAudioConverterInputFormat

        var details: [String: Any] = [
            "native_stop_stage": stage,
            "native_audio_port_type": activeInput?.portType.rawValue ?? "none",
            "native_is_bluetooth_input": hasBluetoothInput,
            "native_actual_audio_sample_rate": actualAudioSampleRate,
            "native_recording_audio_sample_rate": recordingAudioSampleRate,
            "native_recording_audio_channel_count": Int(recordingAudioChannelCount),
            "native_recording_audio_bit_rate": Self.stableRecordingAudioBitRate,
            "native_audio_route_switch_count": audioRouteSwitchCount,
            "native_has_audio_converter": effectiveHasAudioConverter,
            "native_was_paused": wasPaused ?? lockedWasPaused,
            "native_session_started": sessionStarted ?? lockedSessionStarted,
            "native_warmup_frames_remaining": warmupFramesRemaining ?? lockedWarmupFramesRemaining,
            "native_is_first_video_frame": isFirstVideoFrame ?? lockedIsFirstVideoFrame,
            "native_is_first_audio_frame": isFirstAudioFrame ?? lockedIsFirstAudioFrame,
            "native_has_prewarmed_recording_pipeline": hasPrewarmedRecordingPipeline,
            "native_capture_preset": cameraInstance.capturePreset.rawValue,
            "native_capture_width": Int(cameraInstance.captureDimensions.width),
            "native_capture_height": Int(cameraInstance.captureDimensions.height)
        ]
        for (key, value) in timelineDiagnostics {
            details[key] = value
        }

        if let assetWriter {
            details["native_writer_status"] = assetWriterStatusName(assetWriter.status)
            details["native_writer_status_code"] = assetWriter.status.rawValue
        }

        if let effectiveAudioConverterInputFormat {
            let inputSampleRate = effectiveAudioConverterInputFormat.sampleRate
            let inputChannelCount = Int(effectiveAudioConverterInputFormat.channelCount)
            details["native_audio_converter_input_sample_rate"] = inputSampleRate
            details["native_audio_converter_input_channel_count"] = inputChannelCount
            details["native_audio_conv_rate"] = inputSampleRate
            details["native_audio_conv_chans"] = inputChannelCount
        }

        if let nsError = error as NSError? {
            details["native_error_domain"] = nsError.domain
            details["native_error_code"] = nsError.code
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                details["native_underlying_error_domain"] = underlying.domain
                details["native_underlying_error_code"] = underlying.code
                details["native_under_err_domain"] = underlying.domain
                details["native_under_err_code"] = underlying.code
            }
        }

        return details
    }

    private func stopRecordingFlutterError(
        code: String,
        message: String,
        cameraInstance: CameraInstance,
        stage: String,
        assetWriter: AVAssetWriter? = nil,
        error: Error? = nil,
        hasAudioConverter: Bool? = nil,
        audioConverterInputFormat: AVAudioFormat? = nil,
        wasPaused: Bool? = nil,
        sessionStarted: Bool? = nil,
        warmupFramesRemaining: Int? = nil,
        isFirstVideoFrame: Bool? = nil,
        isFirstAudioFrame: Bool? = nil
    ) -> FlutterError {
        return FlutterError(
            code: code,
            message: message,
            details: recordingStopErrorDetails(
                cameraInstance: cameraInstance,
                stage: stage,
                assetWriter: assetWriter,
                error: error,
                hasAudioConverter: hasAudioConverter,
                audioConverterInputFormat: audioConverterInputFormat,
                wasPaused: wasPaused,
                sessionStarted: sessionStarted,
                warmupFramesRemaining: warmupFramesRemaining,
                isFirstVideoFrame: isFirstVideoFrame,
                isFirstAudioFrame: isFirstAudioFrame
            )
        )
    }

    private func sendAudioEvent(_ eventData: [String: Any]) {
        os_unfair_lock_lock(&stateLock)
        let handlers = Array(audioStreamHandlers.values)
        os_unfair_lock_unlock(&stateLock)

        for streamHandler in handlers {
            DispatchQueue.main.async {
                streamHandler.sendEvent(eventData)
            }
        }
    }

    private func routeChangeReasonName(_ reason: AVAudioSession.RouteChangeReason) -> String {
        switch reason {
        case .unknown:
            return "unknown"
        case .newDeviceAvailable:
            return "newDeviceAvailable"
        case .oldDeviceUnavailable:
            return "oldDeviceUnavailable"
        case .categoryChange:
            return "categoryChange"
        case .override:
            return "override"
        case .wakeFromSleep:
            return "wakeFromSleep"
        case .noSuitableRouteForCategory:
            return "noSuitableRouteForCategory"
        case .routeConfigurationChange:
            return "routeConfigurationChange"
        @unknown default:
            return "unknown_\(reason.rawValue)"
        }
    }
    
    @objc private func handleAudioRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        os_unfair_lock_lock(&stateLock)
        let activeCameras = Array(cameras.values)
        os_unfair_lock_unlock(&stateLock)
        
        switch reason {
        case .oldDeviceUnavailable, .newDeviceAvailable, .categoryChange, .routeConfigurationChange:
            let eventData = currentAudioRouteEvent(event: "audioRouteChanged")
            let deviceName = eventData["deviceName"] as? String ?? "iPhone Microphone"
            let portType = eventData["portType"] as? String ?? "MicrophoneBuiltIn"
            
            for cameraInstance in activeCameras {
                os_unfair_lock_lock(&cameraInstance.recordingLock)
                let isRecording = cameraInstance._isRecording
                var switchCount = 0
                if isRecording {
                    // Audio route changes only affect audio. Video continues
                    // uninterrupted, so this transition must not retime either
                    // track's media timeline.
                    cameraInstance._audioRouteDiscontinuityPending = true
                    cameraInstance._audioRouteSwitchCount += 1
                    switchCount = cameraInstance._audioRouteSwitchCount
                    cameraInstance.resetAudioConverterLocked()
                }
                os_unfair_lock_unlock(&cameraInstance.recordingLock)

                if isRecording {
                    NSLog("%@", "PrettyAwesomeCameraPlugin: [AUDIO-ROUTE] Audio route changed during recording. switch#=\(switchCount) reason=\(routeChangeReasonName(reason)) newActiveMicrophone=\(deviceName) (Type: \(portType))")
                }
            }

            sendAudioEvent(eventData)
        default:
            break
        }
    }

    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        os_unfair_lock_lock(&stateLock)
        let activeCameras = Array(cameras.values)
        os_unfair_lock_unlock(&stateLock)

        switch type {
        case .began:
            var affectedRecordingCount = 0
            for cameraInstance in activeCameras {
                os_unfair_lock_lock(&cameraInstance.recordingLock)
                let isRecording = cameraInstance._isRecording
                if isRecording {
                    affectedRecordingCount += 1
                    cameraInstance._audioRouteDiscontinuityPending = true
                    cameraInstance.resetAudioConverterLocked()
                }
                os_unfair_lock_unlock(&cameraInstance.recordingLock)
            }

            if affectedRecordingCount > 0 {
                NSLog("%@", "PrettyAwesomeCameraPlugin: Audio session interruption began during recording. Emitted interruption event for Dart stop. affectedRecordings=\(affectedRecordingCount)")
                sendAudioEvent(currentAudioRouteEvent(event: "audioInterruptionBegan"))
            }
        case .ended:
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            for cameraInstance in activeCameras {
                os_unfair_lock_lock(&cameraInstance.recordingLock)
                let isRecording = cameraInstance._isRecording
                if isRecording {
                    cameraInstance._audioRouteDiscontinuityPending = true
                    cameraInstance.resetAudioConverterLocked()
                }
                os_unfair_lock_unlock(&cameraInstance.recordingLock)
            }

            NSLog("%@", "PrettyAwesomeCameraPlugin: Audio session interruption ended. shouldResume=\(options.contains(.shouldResume))")
            // No native auto-restart here by design: Dart-driven recovery (via
            // resumeRecording's session-recovery path) stays authoritative.
            var endedEvent = currentAudioRouteEvent(event: "audioInterruptionEnded")
            endedEvent["shouldResume"] = options.contains(.shouldResume)
            sendAudioEvent(endedEvent)
        @unknown default:
            NSLog("%@", "PrettyAwesomeCameraPlugin: Unknown audio session interruption type: \(type.rawValue)")
        }
    }
    
    @objc private func handleCaptureSessionRuntimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
        NSLog("%@", "PrettyAwesomeCameraPlugin: [SESSION-ERROR] AVCaptureSession runtime error: \(error?.localizedDescription ?? "unknown") code=\(error?.code ?? 0)")
        var eventData = currentAudioRouteEvent(event: "sessionRuntimeError")
        eventData["errorDescription"] = error?.localizedDescription ?? "unknown"
        eventData["errorCode"] = error?.code ?? 0
        sendAudioEvent(eventData)
    }

    @objc private func handleCaptureSessionWasInterrupted(_ notification: Notification) {
        let reasonValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int ?? -1
        NSLog("%@", "PrettyAwesomeCameraPlugin: [SESSION-ERROR] AVCaptureSession interrupted. reason=\(reasonValue)")
        var eventData = currentAudioRouteEvent(event: "sessionInterrupted")
        eventData["interruptionReason"] = reasonValue
        sendAudioEvent(eventData)
    }

    @objc private func handleCaptureSessionInterruptionEnded(_ notification: Notification) {
        NSLog("%@", "PrettyAwesomeCameraPlugin: [SESSION-ERROR] AVCaptureSession interruption ended.")
        sendAudioEvent(currentAudioRouteEvent(event: "sessionInterruptionEnded"))
    }

    private func startRecording(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let cameraId = args["cameraId"] as? Int else {
            result(FlutterError(code: "INVALID_CAMERA", message: "Camera not found or not initialized", details: nil))
            return
        }
        
        os_unfair_lock_lock(&stateLock)
        guard let cameraInstance = cameras[cameraId],
              cameraInstance.captureSession != nil else {
            os_unfair_lock_unlock(&stateLock)
            result(FlutterError(code: "INVALID_CAMERA", message: "Camera not found or not initialized", details: nil))
            return
        }
        os_unfair_lock_unlock(&stateLock)

        sessionQueue.async {
            // Native re-entrancy guard: a duplicate startRecording would build a
            // second AVAssetWriter and orphan the first. Checked on sessionQueue,
            // where isRecording is set, so racing calls serialize here.
            if cameraInstance.isRecording {
                DispatchQueue.main.async {
                    result(FlutterError(code: "ALREADY_RECORDING", message: "A recording is already in progress", details: nil))
                }
                return
            }

            let audioSession = AVAudioSession.sharedInstance()
            let currentRoute = audioSession.currentRoute
            let isBluetoothInput = currentRoute.inputs.contains { port in
                Self.isBluetoothPort(port.portType)
            }

            if let audioOutput = cameraInstance.audioDataOutput,
               let connection = audioOutput.connection(with: .audio) {
                for port in connection.inputPorts {
                    if let deviceInput = port.input as? AVCaptureDeviceInput {
                        let format = deviceInput.device.activeFormat.formatDescription
                        let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(format)
                        if let asbd = audioStreamBasicDescription {
                            let detectedSampleRate = asbd.pointee.mSampleRate
                            cameraInstance.actualAudioSampleRate = detectedSampleRate
                            break
                        }
                    }
                }
            }
            
            let tempDir = FileManager.default.temporaryDirectory
            // UUID, not epoch seconds: two recordings started within the same
            // second must never overwrite each other.
            let recordingURL = tempDir.appendingPathComponent("recording_\(UUID().uuidString).mov")
            
            do {
                let assetWriter = try AVAssetWriter(url: recordingURL, fileType: .mov)

                let videoWidth = Int(cameraInstance.captureDimensions.width)
                let videoHeight = Int(cameraInstance.captureDimensions.height)
                
                let outputWidth = videoHeight
                let outputHeight = videoWidth

                var videoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: outputWidth,
                    AVVideoHeightKey: outputHeight
                ]
                if let videoBitrate = cameraInstance.videoBitrate {
                    videoSettings[AVVideoCompressionPropertiesKey] = [
                        AVVideoAverageBitRateKey: videoBitrate,
                        AVVideoExpectedSourceFrameRateKey: Self.targetVideoFrameRate,
                        AVVideoMaxKeyFrameIntervalKey: Self.targetVideoFrameRate * 2
                    ]
                }
                let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                videoWriterInput.expectsMediaDataInRealTime = true
                
                let audioSettings = Self.recordingAudioSettings()
                let audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                audioWriterInput.expectsMediaDataInRealTime = true
                
                if assetWriter.canAdd(videoWriterInput) {
                    assetWriter.add(videoWriterInput)
                }
                if assetWriter.canAdd(audioWriterInput) {
                    assetWriter.add(audioWriterInput)
                }
                
                cameraInstance.recordingURL = recordingURL
                cameraInstance.assetWriter = assetWriter
                cameraInstance.videoWriterInput = videoWriterInput
                cameraInstance.audioWriterInput = audioWriterInput

                // Capture frame rate configuration for preservation during camera switches
                if let captureSession = cameraInstance.captureSession {
                    let videoInputs = captureSession.inputs.compactMap { $0 as? AVCaptureDeviceInput }.filter { $0.device.hasMediaType(.video) }
                    if let videoDevice = videoInputs.first?.device {
                        cameraInstance.activeFrameRateMin = videoDevice.activeVideoMinFrameDuration
                        cameraInstance.activeFrameRateMax = videoDevice.activeVideoMaxFrameDuration
                    }
                }

                cameraInstance.isRecording = true

                // Log active microphone when starting the recording
                let activeInput = currentRoute.inputs.first
                let deviceName = activeInput?.portName ?? "iPhone Microphone"
                let portType = activeInput?.portType.rawValue ?? "MicrophoneBuiltIn"
                NSLog("%@", "PrettyAwesomeCameraPlugin: Started recording. Active microphone: \(deviceName) (Type: \(portType))")

                cameraInstance.isPaused = false
                cameraInstance.isFirstVideoFrame = true
                cameraInstance.isFirstAudioFrame = true
                cameraInstance.sessionStartTime = .zero
                cameraInstance.recordingWarmupFramesRemaining = 3
                // Keep the AAC writer on a stable, broadly supported shape.
                // Bluetooth HFP may deliver 8/16 kHz PCM; those buffers are
                // resampled into this target instead of reconfiguring the
                // writer around a fragile route-specific format.
                cameraInstance.recordingAudioSampleRate = Self.stableRecordingAudioSampleRate
                cameraInstance.recordingAudioChannelCount = Self.stableRecordingAudioChannelCount

                // Diagnostics-only counters reset for the new recording.
                os_unfair_lock_lock(&cameraInstance.recordingLock)
                cameraInstance._videoTimeline.reset()
                cameraInstance._audioTimeline.reset()
                cameraInstance._cameraSwitchAudioGate.reset()
                cameraInstance._cameraSwitchAudioReleasePending = false
                cameraInstance._cameraSwitchGenerationPending = nil
                cameraInstance._cameraSwitchCommittedCount = 0
                cameraInstance._cameraSwitchRejectedCount = 0
                cameraInstance._cameraSwitchConfigurationTotalMs = 0
                cameraInstance._cameraSwitchConfigurationMaxMs = 0
                cameraInstance._cameraSwitchAudioHoldTotalMs = 0
                cameraInstance._cameraSwitchAudioHoldMaxMs = 0
                cameraInstance._cameraSwitchHeldAudioSampleCount = 0
                cameraInstance._cameraSwitchTimelineCompressionMs = 0
                cameraInstance._videoNonMonotonicDropCount = 0
                cameraInstance._audioNonMonotonicDropCount = 0
                cameraInstance._videoAppendFailureCount = 0
                cameraInstance._audioAppendFailureCount = 0
                cameraInstance._audioRouteDiscontinuityPending = false
                cameraInstance._lastAcceptedAudioSampleTime = .zero
                cameraInstance._audioRouteSwitchCount = 0
                os_unfair_lock_unlock(&cameraInstance.recordingLock)

                // Route stamp for the caller's start telemetry: which input the
                // recording began on. Mirrors Android's start-info payload shape.
                let startInfo: [String: Any] = [
                    "audioPortType": portType,
                    "audioDeviceName": deviceName,
                    "isBluetoothInput": isBluetoothInput
                ]
                DispatchQueue.main.async {
                    result(startInfo)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "WRITER_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func pauseRecording(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let cameraId = args["cameraId"] as? Int else {
            result(FlutterError(code: "INVALID_CAMERA", message: "Camera not found", details: nil))
            return
        }
        
        os_unfair_lock_lock(&stateLock)
        guard let cameraInstance = cameras[cameraId] else {
            os_unfair_lock_unlock(&stateLock)
            result(FlutterError(code: "INVALID_CAMERA", message: "Camera not found", details: nil))
            return
        }
        os_unfair_lock_unlock(&stateLock)
        
        guard cameraInstance.isRecording else {
            result(FlutterError(code: "NOT_RECORDING", message: "No active recording", details: nil))
            return
        }

        os_unfair_lock_lock(&cameraInstance.recordingLock)
        if !cameraInstance._isPaused {
            cameraInstance._isPaused = true
        }
        os_unfair_lock_unlock(&cameraInstance.recordingLock)
        
        result(nil)
    }
    
    private func resumeRecording(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let cameraId = args["cameraId"] as? Int else {
            result(FlutterError(code: "INVALID_CAMERA", message: "Camera not found", details: nil))
            return
        }
        
        os_unfair_lock_lock(&stateLock)
        guard let cameraInstance = cameras[cameraId] else {
            os_unfair_lock_unlock(&stateLock)
            result(FlutterError(code: "INVALID_CAMERA", message: "Camera not found", details: nil))
            return
        }
        os_unfair_lock_unlock(&stateLock)
        
        guard cameraInstance.isRecording else {
            result(FlutterError(code: "NOT_RECORDING", message: "No active recording", details: nil))
            return
        }

        os_unfair_lock_lock(&cameraInstance.recordingLock)
        let isPaused = cameraInstance._isPaused
        let needsSessionRecovery = !(cameraInstance.captureSession?.isRunning ?? false)
        if isPaused && !needsSessionRecovery {
            if !cameraInstance._isFirstVideoFrame {
                cameraInstance._videoTimeline.markDiscontinuity()
            }
            if !cameraInstance._isFirstAudioFrame {
                cameraInstance._audioTimeline.markDiscontinuity()
            }
            cameraInstance._isPaused = false
        }
        os_unfair_lock_unlock(&cameraInstance.recordingLock)

        if !isPaused || !needsSessionRecovery {
            result(nil)
            return
        }

        sessionQueue.async { [weak self, weak cameraInstance] in
            guard let self = self, let cameraInstance = cameraInstance else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "INVALID_CAMERA", message: "Camera no longer available", details: nil))
                }
                return
            }

            do {
                try self.activateAudioSessionForRecording()
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "AUDIO_SESSION_ERROR", message: "Failed to reactivate audio session: \(error.localizedDescription)", details: nil))
                }
                return
            }

            if let captureSession = cameraInstance.captureSession, !captureSession.isRunning {
                NSLog("%@", "PrettyAwesomeCameraPlugin: Restarting capture session before resumeRecording.")
                captureSession.startRunning()
            }

            os_unfair_lock_lock(&cameraInstance.recordingLock)
            if cameraInstance._isPaused {
                if !cameraInstance._isFirstVideoFrame {
                    cameraInstance._videoTimeline.markDiscontinuity()
                }
                if !cameraInstance._isFirstAudioFrame {
                    cameraInstance._audioTimeline.markDiscontinuity()
                }
                cameraInstance._audioRouteDiscontinuityPending = true
                cameraInstance.resetAudioConverterLocked()
                cameraInstance._isPaused = false
            }
            os_unfair_lock_unlock(&cameraInstance.recordingLock)

            DispatchQueue.main.async {
                result(nil)
            }
        }
    }

    private func setZoom(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let cameraId = args["cameraId"] as? Int,
              let requestedZoom = args["zoom"] as? Double else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Camera ID and zoom are required", details: nil))
            return
        }

        os_unfair_lock_lock(&stateLock)
        guard let cameraInstance = cameras[cameraId] else {
            os_unfair_lock_unlock(&stateLock)
            result(FlutterError(code: "INVALID_CAMERA", message: "Camera not found or not initialized", details: nil))
            return
        }
        os_unfair_lock_unlock(&stateLock)

        sessionQueue.async { [weak self, weak cameraInstance] in
            guard let self = self, let cameraInstance = cameraInstance else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "INVALID_CAMERA", message: "Camera no longer available", details: nil))
                }
                return
            }

            guard let device = self.currentVideoDevice(for: cameraInstance) else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "INVALID_CAMERA", message: "Camera not found or not initialized", details: nil))
                }
                return
            }

            do {
                let appliedZoom = try self.applyZoomFactor(CGFloat(requestedZoom), to: device)
                cameraInstance.zoomFactor = appliedZoom
                DispatchQueue.main.async {
                    result(Double(appliedZoom))
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "ZOOM_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    private func currentVideoDevice(for cameraInstance: CameraInstance) -> AVCaptureDevice? {
        if let device = cameraInstance.videoInput?.device {
            return device
        }

        return cameraInstance.captureSession?.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .first { $0.device.hasMediaType(.video) }?
            .device
    }

    private func applyZoomFactor(_ requestedZoom: CGFloat, to device: AVCaptureDevice) throws -> CGFloat {
        let maximumZoomFactor = min(device.activeFormat.videoMaxZoomFactor, 8.0)
        let safeZoomFactor = requestedZoom.isFinite ? requestedZoom : 1.0
        let clampedZoomFactor = min(max(safeZoomFactor, 1.0), maximumZoomFactor)

        try device.lockForConfiguration()
        defer {
            device.unlockForConfiguration()
        }
        device.videoZoomFactor = clampedZoomFactor
        return clampedZoomFactor
    }
    
    private func canSwitchCamera(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let cameraId = args["cameraId"] as? Int else {
            result(false)
            return
        }
        
        os_unfair_lock_lock(&stateLock)
        guard let cameraInstance = cameras[cameraId] else {
            os_unfair_lock_unlock(&stateLock)
            result(false)
            return
        }
        os_unfair_lock_unlock(&stateLock)
        
        result(cameraInstance.isRecording)
    }
    
    private func canSwitchCurrentCamera(call: FlutterMethodCall, result: @escaping FlutterResult) {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        for (_, cameraInstance) in cameras {
            if cameraInstance.isRecording {
                result(true)
                return
            }
        }
        result(false)
    }
    
    private func switchCamera(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let cameraId = args["cameraId"] as? Int else {
            result(FlutterError(code: "INVALID_CAMERA", message: "Camera not found or not initialized", details: nil))
            return
        }
        
        os_unfair_lock_lock(&stateLock)
        guard let cameraInstance = cameras[cameraId],
              let captureSession = cameraInstance.captureSession else {
            os_unfair_lock_unlock(&stateLock)
            result(FlutterError(code: "INVALID_CAMERA", message: "Camera not found or not initialized", details: nil))
            return
        }
        os_unfair_lock_unlock(&stateLock)
        
        let newPosition: AVCaptureDevice.Position = cameraInstance.lensPosition == .back ? .front : .back
        
        do {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else {
                result(FlutterError(code: "NO_CAMERA", message: "Camera device not available", details: nil))
                return
            }
            
            let videoInput = try AVCaptureDeviceInput(device: device)
            var switchError: FlutterError?
            var switchDiagnostics: [String: Any]?
            
            // Apply frame rate preservation during recording
            if cameraInstance.isRecording,
               let minFrameDuration = cameraInstance.activeFrameRateMin,
               let maxFrameDuration = cameraInstance.activeFrameRateMax {
                do {
                    try device.lockForConfiguration()
                    device.activeVideoMinFrameDuration = minFrameDuration
                    device.activeVideoMaxFrameDuration = maxFrameDuration
                    device.unlockForConfiguration()
                } catch {
                    // Log error but continue with switch (graceful degradation)
                    NSLog("%@", "Warning: Failed to apply frame rate during camera switch: \(error.localizedDescription)")
                }
            }
            
            sessionQueue.sync {
                let configurationStartedAt = ProcessInfo.processInfo.systemUptime

                // Hold audio before closing the video callback gate. This
                // makes both tracks stop at the same reconfiguration boundary;
                // the recording lock also keeps a callback that already passed
                // its queue guard from slipping between these operations.
                os_unfair_lock_lock(&cameraInstance.recordingLock)
                let wasRecordingAtSwitchStart = cameraInstance._isRecording
                if wasRecordingAtSwitchStart {
                    cameraInstance._cameraSwitchAudioGate.begin(
                        at: configurationStartedAt
                    )
                }
                os_unfair_lock_unlock(&cameraInstance.recordingLock)

                // Close the video callback gate before reconfiguration. It
                // stays closed until this switch commits or is cancelled.
                let switchGeneration = cameraInstance.previewTexture?.prepareForCameraSwitch(position: newPosition)
                captureSession.beginConfiguration()

                let existingVideoInputs = captureSession.inputs.compactMap { $0 as? AVCaptureDeviceInput }.filter { $0.device.hasMediaType(.video) }

                for input in existingVideoInputs {
                    captureSession.removeInput(input)
                }
                
                guard captureSession.canAddInput(videoInput) else {
                    for input in existingVideoInputs where captureSession.canAddInput(input) {
                        captureSession.addInput(input)
                    }
                    captureSession.commitConfiguration()
                    let completedAt = ProcessInfo.processInfo.systemUptime
                    let configurationDurationMs = Self.elapsedMilliseconds(
                        from: configurationStartedAt,
                        to: completedAt
                    )
                    os_unfair_lock_lock(&cameraInstance.recordingLock)
                    cameraInstance.previewTexture?.cancelCameraSwitchStabilization()
                    let audioHoldDurationMs = cameraInstance._cameraSwitchAudioGate.release(
                        at: completedAt
                    )
                    self.recordCameraSwitchMetricsLocked(
                        cameraInstance,
                        committed: false,
                        wasRecording: wasRecordingAtSwitchStart,
                        configurationDurationMs: configurationDurationMs,
                        audioHoldDurationMs: audioHoldDurationMs
                    )
                    os_unfair_lock_unlock(&cameraInstance.recordingLock)
                    switchError = self.cameraSwitchFlutterError(
                        code: "SWITCH_ERROR",
                        message: "Unable to add new camera input",
                        stage: "can_add_input_rejected",
                        wasRecording: wasRecordingAtSwitchStart,
                        configurationDurationMs: configurationDurationMs,
                        audioHoldDurationMs: audioHoldDurationMs
                    )
                    return
                }
                captureSession.addInput(videoInput)
                let previousZoomFactor = cameraInstance.zoomFactor
                do {
                    cameraInstance.zoomFactor = try applyZoomFactor(cameraInstance.zoomFactor, to: device)
                } catch {
                    NSLog("%@", "Warning: Failed to apply zoom during camera switch: \(error.localizedDescription)")
                }

                let targetPreset: AVCaptureSession.Preset
                if cameraInstance.isRecording {
                    targetPreset = cameraInstance.capturePreset
                } else {
                    targetPreset = resolveCapturePreset(for: cameraInstance.requestedPresetName, session: captureSession)
                }

                guard captureSession.canSetSessionPreset(targetPreset) else {
                    captureSession.removeInput(videoInput)
                    for input in existingVideoInputs where captureSession.canAddInput(input) {
                        captureSession.addInput(input)
                    }
                    cameraInstance.zoomFactor = previousZoomFactor
                    captureSession.commitConfiguration()
                    let completedAt = ProcessInfo.processInfo.systemUptime
                    let configurationDurationMs = Self.elapsedMilliseconds(
                        from: configurationStartedAt,
                        to: completedAt
                    )
                    os_unfair_lock_lock(&cameraInstance.recordingLock)
                    cameraInstance.previewTexture?.cancelCameraSwitchStabilization()
                    let audioHoldDurationMs = cameraInstance._cameraSwitchAudioGate.release(
                        at: completedAt
                    )
                    self.recordCameraSwitchMetricsLocked(
                        cameraInstance,
                        committed: false,
                        wasRecording: wasRecordingAtSwitchStart,
                        configurationDurationMs: configurationDurationMs,
                        audioHoldDurationMs: audioHoldDurationMs
                    )
                    os_unfair_lock_unlock(&cameraInstance.recordingLock)
                    switchError = self.cameraSwitchFlutterError(
                        code: "SWITCH_UNSUPPORTED",
                        message: "New camera does not support the active recording configuration",
                        stage: "session_preset_rejected",
                        wasRecording: wasRecordingAtSwitchStart,
                        configurationDurationMs: configurationDurationMs,
                        audioHoldDurationMs: audioHoldDurationMs
                    )
                    return
                }

                captureSession.sessionPreset = targetPreset

                if !cameraInstance.isRecording {
                    // Same locked write pair as initializeCamera — keeps the
                    // getRecordingSettings snapshot consistent mid-switch.
                    os_unfair_lock_lock(&self.stateLock)
                    cameraInstance.capturePreset = targetPreset
                    cameraInstance.captureDimensions = dimensions(for: targetPreset)
                    os_unfair_lock_unlock(&self.stateLock)
                }

                // Set orientation/mirroring BEFORE committing, so the very first
                // frame from the new camera has the correct orientation.
                cameraInstance.previewTexture?.updateForNewCamera(position: newPosition)
                
                captureSession.commitConfiguration()
                let completedAt = ProcessInfo.processInfo.systemUptime
                let configurationDurationMs = Self.elapsedMilliseconds(
                    from: configurationStartedAt,
                    to: completedAt
                )

                os_unfair_lock_lock(&cameraInstance.recordingLock)
                if cameraInstance._isRecording, let switchGeneration {
                    // Arm both track-local timelines only after the capture
                    // switch has committed. Keep the video gate closed until
                    // all timeline state is ready, then release the fixed
                    // new-camera stabilization budget atomically with respect
                    // to the writer callbacks' recording lock.
                    cameraInstance._videoTimeline.markDiscontinuity()
                    cameraInstance._audioTimeline.markDiscontinuity()
                    cameraInstance._cameraSwitchGenerationPending = switchGeneration
                }
                // Release the pre-commit hold only after the generation gate is
                // armed. Audio therefore remains suppressed until matching
                // stable video arrives, with no observable gap between gates.
                let audioHoldDurationMs = cameraInstance._cameraSwitchAudioGate.release(
                    at: completedAt
                )
                self.recordCameraSwitchMetricsLocked(
                    cameraInstance,
                    committed: true,
                    wasRecording: wasRecordingAtSwitchStart,
                    configurationDurationMs: configurationDurationMs,
                    audioHoldDurationMs: audioHoldDurationMs
                )
                cameraInstance.previewTexture?.completeCameraSwitchStabilization()
                os_unfair_lock_unlock(&cameraInstance.recordingLock)

                switchDiagnostics = self.cameraSwitchDiagnostics(
                    stage: "committed",
                    wasRecording: wasRecordingAtSwitchStart,
                    configurationDurationMs: configurationDurationMs,
                    audioHoldDurationMs: audioHoldDurationMs
                )
            }

            if let switchError {
                result(switchError)
                return
            }

            cameraInstance.lensPosition = newPosition
            cameraInstance.videoInput = videoInput
            
            if let textureId = cameraInstance.textureId {
                result(cameraInitializationResult(
                    textureId: textureId,
                    captureDimensions: cameraInstance.captureDimensions,
                    switchDiagnostics: switchDiagnostics
                ))
            } else {
                result(FlutterError(code: "TEXTURE_ERROR", message: "No texture ID available", details: nil))
            }
        } catch {
            result(FlutterError(code: "SWITCH_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    private static func elapsedMilliseconds(
        from startedAt: TimeInterval,
        to completedAt: TimeInterval
    ) -> Int {
        max(0, Int(((completedAt - startedAt) * 1000).rounded()))
    }

    private func cameraSwitchDiagnostics(
        stage: String,
        wasRecording: Bool,
        configurationDurationMs: Int,
        audioHoldDurationMs: Int?
    ) -> [String: Any] {
        var diagnostics: [String: Any] = [
            "native_switch_timeline_schema_version": 2,
            "native_switch_stage": stage,
            "native_switch_was_recording": wasRecording,
            "native_switch_configuration_duration_ms": configurationDurationMs,
            "native_switch_audio_hold_applied": audioHoldDurationMs != nil
        ]
        if let audioHoldDurationMs {
            diagnostics["native_switch_audio_hold_duration_ms"] = audioHoldDurationMs
        }
        return diagnostics
    }

    private func cameraSwitchFlutterError(
        code: String,
        message: String,
        stage: String,
        wasRecording: Bool,
        configurationDurationMs: Int,
        audioHoldDurationMs: Int?
    ) -> FlutterError {
        FlutterError(
            code: code,
            message: message,
            details: cameraSwitchDiagnostics(
                stage: stage,
                wasRecording: wasRecording,
                configurationDurationMs: configurationDurationMs,
                audioHoldDurationMs: audioHoldDurationMs
            )
        )
    }

    /// Caller holds `recordingLock`. Diagnostics never influence capture state.
    private func recordCameraSwitchMetricsLocked(
        _ cameraInstance: CameraInstance,
        committed: Bool,
        wasRecording: Bool,
        configurationDurationMs: Int,
        audioHoldDurationMs: Int?
    ) {
        guard wasRecording else { return }
        if committed {
            cameraInstance._cameraSwitchCommittedCount += 1
        } else {
            cameraInstance._cameraSwitchRejectedCount += 1
        }
        cameraInstance._cameraSwitchConfigurationTotalMs += configurationDurationMs
        cameraInstance._cameraSwitchConfigurationMaxMs = max(
            cameraInstance._cameraSwitchConfigurationMaxMs,
            configurationDurationMs
        )
        if let audioHoldDurationMs {
            cameraInstance._cameraSwitchAudioHoldTotalMs += audioHoldDurationMs
            cameraInstance._cameraSwitchAudioHoldMaxMs = max(
                cameraInstance._cameraSwitchAudioHoldMaxMs,
                audioHoldDurationMs
            )
        }
    }

    private func cameraInitializationResult(
        textureId: Int64,
        captureDimensions: CMVideoDimensions,
        switchDiagnostics: [String: Any]? = nil
    ) -> [String: Any] {
        var initializationResult: [String: Any] = [
            "textureId": Int(textureId),
            "previewSize": [
                "width": Int(captureDimensions.width),
                "height": Int(captureDimensions.height)
            ]
        ]
        if let switchDiagnostics {
            initializationResult["switchDiagnostics"] = switchDiagnostics
        }
        return initializationResult
    }
    
    private func stopRecording(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let cameraId = args["cameraId"] as? Int else {
            result(FlutterError(code: "INVALID_CAMERA", message: "Camera not found", details: nil))
            return
        }
        
        os_unfair_lock_lock(&stateLock)
        guard let cameraInstance = cameras[cameraId] else {
            os_unfair_lock_unlock(&stateLock)
            result(FlutterError(code: "INVALID_CAMERA", message: "Camera not found", details: nil))
            return
        }
        os_unfair_lock_unlock(&stateLock)
        guard cameraInstance.isRecording else {
            result(stopRecordingFlutterError(
                code: "NOT_RECORDING",
                message: "No active recording",
                cameraInstance: cameraInstance,
                stage: "not_recording"
            ))
            return
        }
        
        // Log active microphone when stopping the recording
        let audioSession = AVAudioSession.sharedInstance()
        let currentRoute = audioSession.currentRoute
        let activeInput = currentRoute.inputs.first
        let deviceName = activeInput?.portName ?? "iPhone Microphone"
        let portType = activeInput?.portType.rawValue ?? "MicrophoneBuiltIn"
        NSLog("%@", "PrettyAwesomeCameraPlugin: Stopped recording. Final active microphone: \(deviceName) (Type: \(portType))")
        
        guard let assetWriter = cameraInstance.assetWriter else {
            result(stopRecordingFlutterError(
                code: "WRITER_ERROR",
                message: "No asset writer available",
                cameraInstance: cameraInstance,
                stage: "no_asset_writer"
            ))
            return
        }
        
        let recordingPath = cameraInstance.recordingURL?.path

        let finishStop: () -> Void = {
            os_unfair_lock_lock(&cameraInstance.recordingLock)
            let wasPaused = cameraInstance._isPaused
            let sessionStarted = cameraInstance._sessionStartTime != .zero
            let warmupFramesRemaining = cameraInstance._recordingWarmupFramesRemaining
            let isFirstVideoFrame = cameraInstance._isFirstVideoFrame
            let isFirstAudioFrame = cameraInstance._isFirstAudioFrame
            let hadAudioConverter = cameraInstance.audioConverter != nil
            let audioConverterInputFormat = cameraInstance.audioConverterInputFormat
            let recordingDiagnostics = self.recordingTimelineDiagnosticsLocked(
                cameraInstance
            )
            cameraInstance._isRecording = false
            cameraInstance._isPaused = false
            cameraInstance.videoWriterInput = nil
            cameraInstance.audioWriterInput = nil
            os_unfair_lock_unlock(&cameraInstance.recordingLock)

            // Clear frame rate storage when recording stops
            cameraInstance.activeFrameRateMin = nil
            cameraInstance.activeFrameRateMax = nil
            cameraInstance.resetAudioConverter()

            switch assetWriter.status {
            case .writing:
                assetWriter.finishWriting {
                    DispatchQueue.main.async {
                        if assetWriter.status == .completed {
                            if let recordingPath {
                                result([
                                    "filePath": recordingPath,
                                    "diagnostics": recordingDiagnostics
                                ])
                            } else {
                                result(nil)
                            }
                        } else {
                            let writerError = assetWriter.error
                            let message = writerError?.localizedDescription ?? "Unknown error"
                            result(self.stopRecordingFlutterError(
                                code: "FINISH_ERROR",
                                message: message,
                                cameraInstance: cameraInstance,
                                stage: "finish_writing",
                                assetWriter: assetWriter,
                                error: writerError,
                                hasAudioConverter: hadAudioConverter,
                                audioConverterInputFormat: audioConverterInputFormat,
                                wasPaused: wasPaused,
                                sessionStarted: sessionStarted,
                                warmupFramesRemaining: warmupFramesRemaining,
                                isFirstVideoFrame: isFirstVideoFrame,
                                isFirstAudioFrame: isFirstAudioFrame
                            ))
                        }
                    }
                }
            case .unknown:
                // Recording was requested but the asset writer never received frames
                // (e.g. user stopped too quickly, before warmup frames arrived).
                // Clean up and return nil to signal an empty recording.
                NSLog("%@", "PrettyAwesomeCameraPlugin: Stop produced empty recording. wasPaused=\(wasPaused) sessionStarted=\(sessionStarted) warmupFramesRemaining=\(warmupFramesRemaining) isFirstVideoFrame=\(isFirstVideoFrame) isFirstAudioFrame=\(isFirstAudioFrame)")
                if let url = cameraInstance.recordingURL {
                    try? FileManager.default.removeItem(at: url)
                }
                cameraInstance.assetWriter = nil
                cameraInstance.videoWriterInput = nil
                cameraInstance.audioWriterInput = nil
                cameraInstance.recordingURL = nil
                DispatchQueue.main.async {
                    result(nil)
                }
            case .failed:
                let writerError = assetWriter.error
                let message = writerError?.localizedDescription ?? "Unknown error"
                if let url = cameraInstance.recordingURL {
                    try? FileManager.default.removeItem(at: url)
                }
                cameraInstance.assetWriter = nil
                cameraInstance.videoWriterInput = nil
                cameraInstance.audioWriterInput = nil
                cameraInstance.recordingURL = nil
                DispatchQueue.main.async {
                    result(self.stopRecordingFlutterError(
                        code: "WRITER_ERROR",
                        message: message,
                        cameraInstance: cameraInstance,
                        stage: "writer_failed",
                        assetWriter: assetWriter,
                        error: writerError,
                        hasAudioConverter: hadAudioConverter,
                        audioConverterInputFormat: audioConverterInputFormat,
                        wasPaused: wasPaused,
                        sessionStarted: sessionStarted,
                        warmupFramesRemaining: warmupFramesRemaining,
                        isFirstVideoFrame: isFirstVideoFrame,
                        isFirstAudioFrame: isFirstAudioFrame
                    ))
                }
            default:
                DispatchQueue.main.async {
                    result(self.stopRecordingFlutterError(
                        code: "WRITER_ERROR",
                        message: "Asset writer in unexpected state: \(assetWriter.status.rawValue)",
                        cameraInstance: cameraInstance,
                        stage: "unexpected_writer_status",
                        assetWriter: assetWriter,
                        error: assetWriter.error,
                        hasAudioConverter: hadAudioConverter,
                        audioConverterInputFormat: audioConverterInputFormat,
                        wasPaused: wasPaused,
                        sessionStarted: sessionStarted,
                        warmupFramesRemaining: warmupFramesRemaining,
                        isFirstVideoFrame: isFirstVideoFrame,
                        isFirstAudioFrame: isFirstAudioFrame
                    ))
                }
            }
        }

        os_unfair_lock_lock(&cameraInstance.recordingLock)
        let shouldWaitForFirstFrame = cameraInstance._isPaused &&
                                      cameraInstance._sessionStartTime == .zero &&
                                      assetWriter.status == .unknown
        if shouldWaitForFirstFrame {
            cameraInstance._isPaused = false
        }
        os_unfair_lock_unlock(&cameraInstance.recordingLock)

        if shouldWaitForFirstFrame {
            NSLog("%@", "PrettyAwesomeCameraPlugin: Stop requested while paused before writer started; waiting briefly for first frame.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                finishStop()
            }
        } else {
            finishStop()
        }
    }
    
    private func handleVideoSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        switchGeneration: UInt64,
        for cameraInstance: CameraInstance
    ) {
        let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        os_unfair_lock_lock(&cameraInstance.recordingLock)

        guard cameraInstance._isRecording,
              let assetWriter = cameraInstance.assetWriter,
              let videoInput = cameraInstance.videoWriterInput else {
            os_unfair_lock_unlock(&cameraInstance.recordingLock)
            return
        }

        if cameraInstance._isPaused {
            os_unfair_lock_unlock(&cameraInstance.recordingLock)
            return
        }

        var consumedCameraSwitchBoundary = false
        if let pendingGeneration = cameraInstance._cameraSwitchGenerationPending {
            guard switchGeneration == pendingGeneration else {
                // This callback passed the preview gate immediately before a
                // switch began. It belongs to the prior camera generation and
                // must not consume the newly armed timeline boundary.
                os_unfair_lock_unlock(&cameraInstance.recordingLock)
                return
            }
            if cameraInstance._videoTimeline.discontinuityPending {
                // An invalid timestamp cannot define a shared boundary. Keep
                // the generation armed so the next valid stable frame does.
                guard let sharedGap = cameraInstance._videoTimeline
                    .consumePendingDiscontinuityGap(at: currentTime) else {
                    os_unfair_lock_unlock(&cameraInstance.recordingLock)
                    return
                }
                cameraInstance._audioTimeline.applyPendingDiscontinuityGap(
                    sharedGap
                )
                cameraInstance._cameraSwitchTimelineCompressionMs +=
                    Self.timeMilliseconds(sharedGap) ?? 0
                cameraInstance._cameraSwitchAudioReleasePending = true
                consumedCameraSwitchBoundary = true
            }
            // CameraPreviewTexture drops the configured stabilization frames
            // before forwarding this callback. Reaching this point with a
            // valid boundary (or before either track has started) establishes
            // the release point for both tracks.
            cameraInstance._cameraSwitchGenerationPending = nil
        }

        if cameraInstance._isFirstVideoFrame {
            if cameraInstance._recordingWarmupFramesRemaining > 0 {
                cameraInstance._recordingWarmupFramesRemaining -= 1
                os_unfair_lock_unlock(&cameraInstance.recordingLock)
                return
            }

            if assetWriter.status == .unknown {
                assetWriter.startWriting()
                if assetWriter.status == .failed {
                    NSLog("%@", "Asset writer failed to start: \(assetWriter.error?.localizedDescription ?? "unknown error")")
                }
                assetWriter.startSession(atSourceTime: currentTime)
                cameraInstance._sessionStartTime = currentTime
            }
            cameraInstance._isFirstVideoFrame = false
        }

        if consumedCameraSwitchBoundary ||
           cameraInstance._videoTimeline.consumePendingDiscontinuity(at: currentTime) {
            os_unfair_lock_unlock(&cameraInstance.recordingLock)
            return
        }

        guard videoInput.isReadyForMoreMediaData else {
            NSLog("%@", "PrettyAwesomeCameraPlugin: Video input not ready for media data.")
            os_unfair_lock_unlock(&cameraInstance.recordingLock)
            return
        }

        let adjustedTime: CMTime
        switch cameraInstance._videoTimeline.adjustedTime(for: currentTime) {
        case .append(let time):
            adjustedTime = time
        case .dropInvalidSourceTime:
            NSLog("%@", "PrettyAwesomeCameraPlugin: Dropping video sample with invalid PTS.")
            os_unfair_lock_unlock(&cameraInstance.recordingLock)
            return
        case .dropNonMonotonic(let candidate, let previous):
            cameraInstance._videoNonMonotonicDropCount += 1
            NSLog("%@", "PrettyAwesomeCameraPlugin: Dropping non-monotonic video PTS. candidate=\(CMTimeGetSeconds(candidate)) previous=\(CMTimeGetSeconds(previous))")
            os_unfair_lock_unlock(&cameraInstance.recordingLock)
            return
        }

        var adjustedBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: adjustedTime,
            decodeTimeStamp: .invalid
        )

        CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleBufferOut: &adjustedBuffer
        )

        if let adjustedBuffer = adjustedBuffer {
            if !videoInput.append(adjustedBuffer) {
                cameraInstance._videoAppendFailureCount += 1
                if let error = cameraInstance.assetWriter?.error {
                    NSLog("%@", "PrettyAwesomeCameraPlugin: Video append failed. Error: \(error.localizedDescription)")
                } else {
                    NSLog("%@", "PrettyAwesomeCameraPlugin: Video append failed without asset writer error.")
                }
            }
        }
        os_unfair_lock_unlock(&cameraInstance.recordingLock)
    }

    private func resolveCapturePreset(for presetName: String, session: AVCaptureSession) -> AVCaptureSession.Preset {
        let candidates: [AVCaptureSession.Preset]

        switch presetName {
        case "low":
            candidates = [.cif352x288, .vga640x480]
        case "medium":
            candidates = [.vga640x480, .cif352x288]
        case "veryHigh":
            candidates = [.hd1920x1080, .hd1280x720, .vga640x480, .cif352x288]
        case "max":
            candidates = [.hd4K3840x2160, .hd1920x1080, .hd1280x720, .vga640x480, .cif352x288]
        case "high":
            fallthrough
        default:
            candidates = [.hd1280x720, .vga640x480, .cif352x288]
        }

        for preset in candidates where session.canSetSessionPreset(preset) {
            return preset
        }

        return .high
    }

    private func dimensions(for preset: AVCaptureSession.Preset) -> CMVideoDimensions {
        switch preset {
        case .cif352x288:
            return CMVideoDimensions(width: 352, height: 288)
        case .vga640x480:
            return CMVideoDimensions(width: 640, height: 480)
        case .hd1920x1080:
            return CMVideoDimensions(width: 1920, height: 1080)
        case .hd4K3840x2160:
            return CMVideoDimensions(width: 3840, height: 2160)
        case .hd1280x720:
            fallthrough
        default:
            return CMVideoDimensions(width: 1280, height: 720)
        }
    }

    private func prewarmRecordingPipeline(for cameraInstance: CameraInstance) {
        guard !cameraInstance.hasPrewarmedRecordingPipeline else {
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
        let warmupURL = tempDir.appendingPathComponent("warmup_\(cameraInstance.cameraId).mov")

        do {
            if FileManager.default.fileExists(atPath: warmupURL.path) {
                try FileManager.default.removeItem(at: warmupURL)
            }

            let assetWriter = try AVAssetWriter(url: warmupURL, fileType: .mov)

            let videoWidth = Int(cameraInstance.captureDimensions.width)
            let videoHeight = Int(cameraInstance.captureDimensions.height)
            let outputWidth = videoHeight
            let outputHeight = videoWidth

            var videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: outputWidth,
                AVVideoHeightKey: outputHeight
            ]
            if let videoBitrate = cameraInstance.videoBitrate {
                videoSettings[AVVideoCompressionPropertiesKey] = [
                    AVVideoAverageBitRateKey: videoBitrate,
                    AVVideoExpectedSourceFrameRateKey: Self.targetVideoFrameRate,
                    AVVideoMaxKeyFrameIntervalKey: Self.targetVideoFrameRate * 2
                ]
            }
            let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoWriterInput.expectsMediaDataInRealTime = true

            let audioSettings = Self.recordingAudioSettings()
            let audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioWriterInput.expectsMediaDataInRealTime = true

            if assetWriter.canAdd(videoWriterInput) {
                assetWriter.add(videoWriterInput)
            }
            if assetWriter.canAdd(audioWriterInput) {
                assetWriter.add(audioWriterInput)
            }

            assetWriter.startWriting()
            assetWriter.startSession(atSourceTime: .zero)
            videoWriterInput.markAsFinished()
            audioWriterInput.markAsFinished()
            assetWriter.finishWriting {
                try? FileManager.default.removeItem(at: warmupURL)
            }
            cameraInstance.hasPrewarmedRecordingPipeline = true
        } catch {
        }
    }
}

extension PrettyAwesomeCameraPlugin: AVCaptureAudioDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard output is AVCaptureAudioDataOutput else { return }
        os_unfair_lock_lock(&stateLock)
        var targetCameraInstance: CameraInstance?
        for (_, cameraInstance) in cameras {
            if cameraInstance.audioDataOutput === output as? AVCaptureAudioDataOutput {
                targetCameraInstance = cameraInstance
                break
            }
        }
        os_unfair_lock_unlock(&stateLock)
        
        guard let cameraInstance = targetCameraInstance else { return }

        // Metering runs BEFORE any recording-state guards so levels flow during
        // preview and pause as well; it deliberately reads PCM directly instead
        // of AVCaptureAudioChannel.averagePowerLevel (stuck at -120 dB on
        // iOS 26.4-26.5, Apple FB22272504).
        processAudioLevelMetering(sampleBuffer, for: cameraInstance)

        var detectedChannels: UInt32 = 1
        if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
            let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
            if let asbd = audioStreamBasicDescription {
                let detectedSampleRate = asbd.pointee.mSampleRate
                detectedChannels = asbd.pointee.mChannelsPerFrame
                if cameraInstance.actualAudioSampleRate != detectedSampleRate {
                    if cameraInstance.isRecording {
                        NSLog("%@", "PrettyAwesomeCameraPlugin: [AUDIO-RATE] input sample rate changed \(cameraInstance.actualAudioSampleRate) -> \(detectedSampleRate) (recording targetRate=\(cameraInstance.recordingAudioSampleRate))")
                    }
                    cameraInstance.actualAudioSampleRate = detectedSampleRate
                }
            }
        }
        
        // If the incoming sample rate or channel count doesn't match the recording format,
        // resample the audio so recording continues seamlessly (e.g. when
        // AirPods disconnect/connect and the audio format changes).
        let targetSampleRate = cameraInstance.recordingAudioSampleRate
        let targetChannels = cameraInstance.recordingAudioChannelCount
        
        let needsConversion = cameraInstance.isRecording &&
                              targetSampleRate > 0 &&
                              targetChannels > 0 &&
                              (abs(cameraInstance.actualAudioSampleRate - targetSampleRate) > 100 ||
                               detectedChannels != targetChannels)
        
        if needsConversion {
            let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            
            os_unfair_lock_lock(&cameraInstance.recordingLock)
            
            guard cameraInstance._isRecording,
                  let audioInput = cameraInstance.audioWriterInput else {
                os_unfair_lock_unlock(&cameraInstance.recordingLock)
                return
            }

            if cameraInstance._isPaused {
                os_unfair_lock_unlock(&cameraInstance.recordingLock)
                return
            }

            guard cameraInstance._sessionStartTime != .zero else {
                os_unfair_lock_unlock(&cameraInstance.recordingLock)
                return
            }

            // Stop audio at the same pre-configuration boundary as video, then
            // keep it stopped until stable matching video releases the switch.
            if cameraInstance._cameraSwitchAudioGate.isHolding ||
               cameraInstance._cameraSwitchGenerationPending != nil {
                cameraInstance._cameraSwitchHeldAudioSampleCount += 1
                os_unfair_lock_unlock(&cameraInstance.recordingLock)
                return
            }

            if cameraInstance._cameraSwitchAudioReleasePending {
                cameraInstance._cameraSwitchAudioReleasePending = false
                cameraInstance._audioTimeline.observeDroppedSample(at: currentTime)
                os_unfair_lock_unlock(&cameraInstance.recordingLock)
                return
            }

            if cameraInstance._isFirstAudioFrame {
                cameraInstance._isFirstAudioFrame = false
                cameraInstance._lastAcceptedAudioSampleTime = currentTime
            }

            if cameraInstance._audioTimeline.consumePendingDiscontinuity(at: currentTime) {
                os_unfair_lock_unlock(&cameraInstance.recordingLock)
                return
            }

            // Audio-only discontinuity (route change: AirPods connect/disconnect).
            // Drop this first transitional sample without retiming audio; the
            // video timeline is unaffected and AVAssetWriter preserves the gap.
            if cameraInstance._audioRouteDiscontinuityPending {
                // Diagnostics: measure the true audio-only gap (last accepted audio
                // sample -> first post-route sample). This is the number the proposed
                // "audioTimeOffset compression" fix would act on. Logging only.
                let hadPriorAudio = cameraInstance._lastAcceptedAudioSampleTime != .zero
                let gapSeconds = hadPriorAudio
                    ? CMTimeGetSeconds(CMTimeSubtract(currentTime, cameraInstance._lastAcceptedAudioSampleTime))
                    : -1
                NSLog("%@", "PrettyAwesomeCameraPlugin: [AUDIO-GAP] path=resampled switch#=\(cameraInstance._audioRouteSwitchCount) gapSeconds=\(gapSeconds) inRate=\(cameraInstance.actualAudioSampleRate) targetRate=\(cameraInstance.recordingAudioSampleRate)")
                cameraInstance._audioRouteDiscontinuityPending = false
                cameraInstance._audioTimeline.observeDroppedSample(at: currentTime)
                cameraInstance._lastAcceptedAudioSampleTime = currentTime
                os_unfair_lock_unlock(&cameraInstance.recordingLock)
                return
            }

            guard audioInput.isReadyForMoreMediaData else {
                NSLog("%@", "PrettyAwesomeCameraPlugin: Resampled audio input not ready for media data.")
                os_unfair_lock_unlock(&cameraInstance.recordingLock)
                return
            }

            let adjustedTime: CMTime
            switch cameraInstance._audioTimeline.adjustedTime(for: currentTime) {
            case .append(let time):
                adjustedTime = time
            case .dropInvalidSourceTime:
                NSLog("%@", "PrettyAwesomeCameraPlugin: Dropping resampled audio sample with invalid PTS.")
                os_unfair_lock_unlock(&cameraInstance.recordingLock)
                return
            case .dropNonMonotonic(let candidate, let previous):
                cameraInstance._audioNonMonotonicDropCount += 1
                NSLog("%@", "PrettyAwesomeCameraPlugin: Dropping non-monotonic resampled audio PTS. candidate=\(CMTimeGetSeconds(candidate)) previous=\(CMTimeGetSeconds(previous))")
                os_unfair_lock_unlock(&cameraInstance.recordingLock)
                return
            }
            cameraInstance._lastAcceptedAudioSampleTime = currentTime
            
            if let resampled = self.resampleAudioBuffer(
                sampleBuffer,
                to: targetSampleRate,
                targetChannels: targetChannels,
                presentationTime: adjustedTime,
                cameraInstance: cameraInstance
            ) {
                if !audioInput.append(resampled) {
                    cameraInstance._audioAppendFailureCount += 1
                    if let error = cameraInstance.assetWriter?.error {
                        NSLog("%@", "PrettyAwesomeCameraPlugin: Resampled audio append failed. Error: \(error.localizedDescription)")
                    }
                }
            } else {
                // Resampling failed — drop this sample, reset converter, and log warning without flagging a recording-wide discontinuity
                cameraInstance.resetAudioConverterLocked()
            }
            os_unfair_lock_unlock(&cameraInstance.recordingLock)
            return
        } else {
            // Rate matches — clear the converter if it was set from a prior mismatch
            os_unfair_lock_lock(&cameraInstance.recordingLock)
            if cameraInstance.audioConverter != nil {
                cameraInstance.resetAudioConverterLocked()
            }
            os_unfair_lock_unlock(&cameraInstance.recordingLock)
        }
        
        let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        os_unfair_lock_lock(&cameraInstance.recordingLock)

        guard cameraInstance._isRecording,
              let audioInput = cameraInstance.audioWriterInput else {
            os_unfair_lock_unlock(&cameraInstance.recordingLock)
            return
        }

        if cameraInstance._isPaused {
            os_unfair_lock_unlock(&cameraInstance.recordingLock)
            return
        }

        guard cameraInstance._sessionStartTime != .zero else {
            os_unfair_lock_unlock(&cameraInstance.recordingLock)
            return
        }

        // Stop audio at the same pre-configuration boundary as video, then
        // keep it stopped until stable matching video releases the switch.
        if cameraInstance._cameraSwitchAudioGate.isHolding ||
           cameraInstance._cameraSwitchGenerationPending != nil {
            cameraInstance._cameraSwitchHeldAudioSampleCount += 1
            os_unfair_lock_unlock(&cameraInstance.recordingLock)
            return
        }

        if cameraInstance._cameraSwitchAudioReleasePending {
            cameraInstance._cameraSwitchAudioReleasePending = false
            cameraInstance._audioTimeline.observeDroppedSample(at: currentTime)
            os_unfair_lock_unlock(&cameraInstance.recordingLock)
            return
        }

        if cameraInstance._isFirstAudioFrame {
            cameraInstance._isFirstAudioFrame = false
            cameraInstance._lastAcceptedAudioSampleTime = currentTime
        }

        if cameraInstance._audioTimeline.consumePendingDiscontinuity(at: currentTime) {
            os_unfair_lock_unlock(&cameraInstance.recordingLock)
            return
        }

        // Audio-only discontinuity can also occur when the route changes but
        // the sample format stays compatible with the writer. Drop the first
        // transitional sample here too, not just in the resampling branch.
        if cameraInstance._audioRouteDiscontinuityPending {
            // Diagnostics: measure the true audio-only gap (logging only).
            let hadPriorAudio = cameraInstance._lastAcceptedAudioSampleTime != .zero
            let gapSeconds = hadPriorAudio
                ? CMTimeGetSeconds(CMTimeSubtract(currentTime, cameraInstance._lastAcceptedAudioSampleTime))
                : -1
            NSLog("%@", "PrettyAwesomeCameraPlugin: [AUDIO-GAP] path=direct switch#=\(cameraInstance._audioRouteSwitchCount) gapSeconds=\(gapSeconds) inRate=\(cameraInstance.actualAudioSampleRate) targetRate=\(cameraInstance.recordingAudioSampleRate)")
            cameraInstance._audioRouteDiscontinuityPending = false
            cameraInstance._audioTimeline.observeDroppedSample(at: currentTime)
            cameraInstance._lastAcceptedAudioSampleTime = currentTime
            os_unfair_lock_unlock(&cameraInstance.recordingLock)
            return
        }

        guard audioInput.isReadyForMoreMediaData else {
            NSLog("%@", "PrettyAwesomeCameraPlugin: Direct audio input not ready for media data.")
            os_unfair_lock_unlock(&cameraInstance.recordingLock)
            return
        }

        let adjustedTime: CMTime
        switch cameraInstance._audioTimeline.adjustedTime(for: currentTime) {
        case .append(let time):
            adjustedTime = time
        case .dropInvalidSourceTime:
            NSLog("%@", "PrettyAwesomeCameraPlugin: Dropping direct audio sample with invalid PTS.")
            os_unfair_lock_unlock(&cameraInstance.recordingLock)
            return
        case .dropNonMonotonic(let candidate, let previous):
            cameraInstance._audioNonMonotonicDropCount += 1
            NSLog("%@", "PrettyAwesomeCameraPlugin: Dropping non-monotonic direct audio PTS. candidate=\(CMTimeGetSeconds(candidate)) previous=\(CMTimeGetSeconds(previous))")
            os_unfair_lock_unlock(&cameraInstance.recordingLock)
            return
        }
        cameraInstance._lastAcceptedAudioSampleTime = currentTime

        var adjustedBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: adjustedTime,
            decodeTimeStamp: .invalid
        )

        CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleBufferOut: &adjustedBuffer
        )

        if let adjustedBuffer = adjustedBuffer {
            if !audioInput.append(adjustedBuffer) {
                cameraInstance._audioAppendFailureCount += 1
                if let error = cameraInstance.assetWriter?.error {
                    NSLog("%@", "PrettyAwesomeCameraPlugin: Direct audio append failed. Error: \(error.localizedDescription)")
                }
            }
        }
        os_unfair_lock_unlock(&cameraInstance.recordingLock)
    }
    
    /// Resamples an audio CMSampleBuffer to the target sample rate and channel layout using AVAudioConverter.
    /// The converter is lazily created and cached on the CameraInstance.
    private func resampleAudioBuffer(
        _ sampleBuffer: CMSampleBuffer,
        to targetSampleRate: Double,
        targetChannels: UInt32,
        presentationTime: CMTime,
        cameraInstance: CameraInstance
    ) -> CMSampleBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return nil
        }
        
        let inputSampleRate = asbd.pointee.mSampleRate
        let inputChannels = asbd.pointee.mChannelsPerFrame
        let formatID = asbd.pointee.mFormatID
        let formatFlags = asbd.pointee.mFormatFlags
        let bitsPerChannel = asbd.pointee.mBitsPerChannel
        
        let isFloat = (formatFlags & kLinearPCMFormatFlagIsFloat) != 0
        let isSignedInteger = (formatFlags & kLinearPCMFormatFlagIsSignedInteger) != 0
        
        // AVCaptureAudioDataOutput should deliver PCM. Keep this guard narrow so
        // unsupported route-change layouts fail loudly instead of producing silence.
        guard formatID == kAudioFormatLinearPCM,
              (bitsPerChannel == 16 && isSignedInteger) ||
              (bitsPerChannel == 32 && (isFloat || isSignedInteger)) else {
            NSLog("%@", "PrettyAwesomeCameraPlugin: Unsupported audio format. Expected 16-bit signed integer, 32-bit float, or 32-bit signed integer PCM.")
            return nil
        }
        
        guard inputChannels > 0,
              let inputFormat = AVAudioFormat(streamDescription: asbd) else {
            return nil
        }
        
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: AVAudioChannelCount(targetChannels),
            interleaved: false
        ) else {
            return nil
        }
        
        // Create or update the converter if the input format changed
        if cameraInstance.audioConverter == nil ||
           cameraInstance.audioConverterInputFormat != inputFormat {
            guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
                return nil
            }
            cameraInstance.audioConverter = converter
            cameraInstance.audioConverterInputFormat = inputFormat
            // Diagnostics: a (re)created converter re-primes (latency/priming frames).
            // Frequent re-primes across route switches are a candidate cumulative-drift
            // source independent of the gap hypothesis. Logging only.
            NSLog("%@", "PrettyAwesomeCameraPlugin: [AUDIO-CONVERTER] (re)created converter inRate=\(inputSampleRate) inCh=\(inputChannels) outRate=\(targetSampleRate) outCh=\(targetChannels)")
        }
        
        guard let converter = cameraInstance.audioConverter else {
            return nil
        }
        
        // Extract sample count and create input PCM buffer
        let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard sampleCount > 0 else { return nil }
        
        guard let inputPCMBuffer = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: AVAudioFrameCount(sampleCount)
        ) else {
            return nil
        }
        inputPCMBuffer.frameLength = AVAudioFrameCount(sampleCount)
        
        let copyStatus = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(sampleCount),
            into: inputPCMBuffer.mutableAudioBufferList
        )
        guard copyStatus == noErr else {
            NSLog("%@", "PrettyAwesomeCameraPlugin: Failed to copy PCM data for resampling. Status: \(copyStatus)")
            return nil
        }
        
        // Calculate output frame count based on sample rate ratio
        let ratio = targetSampleRate / inputSampleRate
        let outputFrameCount = AVAudioFrameCount(ceil(Double(sampleCount) * ratio))
        
        guard let outputPCMBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputFrameCount
        ) else {
            return nil
        }
        
        // Perform the conversion
        var conversionError: NSError?
        var inputBufferConsumed = false
        let conversionStatus: AVAudioConverterOutputStatus = converter.convert(to: outputPCMBuffer, error: &conversionError) { inNumPackets, outStatus in
            if inputBufferConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputBufferConsumed = true
            outStatus.pointee = .haveData
            return inputPCMBuffer
        }
        
        guard conversionStatus != .error, conversionError == nil else {
            if let err = conversionError {
                NSLog("%@", "PrettyAwesomeCameraPlugin: AVAudioConverter failed. Error: \(err.localizedDescription), Code: \(err.code)")
            }
            return nil
        }
        
        let outputFrameLength = outputPCMBuffer.frameLength
        guard outputFrameLength > 0 else { return nil }
        
        // Create an AudioStreamBasicDescription for Int16 output (what the asset writer expects)
        var outputASBD = AudioStreamBasicDescription(
            mSampleRate: targetSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: UInt32(2 * targetChannels),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(2 * targetChannels),
            mChannelsPerFrame: targetChannels,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        
        // Convert Float32 back to Int16 for the output CMSampleBuffer
        let outputByteCount = Int(outputFrameLength) * Int(targetChannels) * 2
        let outputData = UnsafeMutablePointer<Int16>.allocate(capacity: Int(outputFrameLength) * Int(targetChannels))
        defer { outputData.deallocate() }
        
        if let floatChannelData = outputPCMBuffer.floatChannelData {
            for frame in 0..<Int(outputFrameLength) {
                for ch in 0..<Int(targetChannels) {
                    let floatSample = max(-1.0, min(1.0, floatChannelData[ch][frame]))
                    outputData[frame * Int(targetChannels) + ch] = Int16(floatSample * 32767.0)
                }
            }
        }
        
        // Create output CMSampleBuffer
        var outputFormatDescription: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &outputASBD,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &outputFormatDescription
        )
        
        guard let outFormatDesc = outputFormatDescription else { return nil }
        
        var outputBlockBuffer: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: outputByteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: outputByteCount,
            flags: 0,
            blockBufferOut: &outputBlockBuffer
        )
        
        guard let blockBuf = outputBlockBuffer else { return nil }
        
        CMBlockBufferReplaceDataBytes(
            with: outputData,
            blockBuffer: blockBuf,
            offsetIntoDestination: 0,
            dataLength: outputByteCount
        )
        
        var outputSampleBuffer: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuf,
            formatDescription: outFormatDesc,
            sampleCount: CMItemCount(outputFrameLength),
            presentationTimeStamp: presentationTime,
            packetDescriptions: nil,
            sampleBufferOut: &outputSampleBuffer
        )
        
        return outputSampleBuffer
    }
}

// MARK: - Audio level metering

extension PrettyAwesomeCameraPlugin {
    /// Accumulates per-buffer peak/RMS and emits a throttled level event
    /// (~4 Hz at typical mic buffer cadence — no timer needed). Runs on the
    /// audio delegate's serial queue; the metering accumulators are confined
    /// to that queue, so no lock is taken (and recordingLock deliberately
    /// stays untouched here to avoid contending with the writer paths).
    fileprivate func processAudioLevelMetering(_ sampleBuffer: CMSampleBuffer, for cameraInstance: CameraInstance) {
        os_unfair_lock_lock(&stateLock)
        let handler = audioLevelStreamHandlers[cameraInstance.cameraId]
        os_unfair_lock_unlock(&stateLock)
        guard let handler, handler.hasListener else { return }

        guard let levels = Self.computeAudioLevels(from: sampleBuffer) else { return }

        cameraInstance.meteringBufferCount += 1
        cameraInstance.meteringWindowPeak = max(cameraInstance.meteringWindowPeak, levels.peak)
        cameraInstance.meteringSumSquares += levels.sumSquares
        cameraInstance.meteringSampleCount += levels.sampleCount

        guard cameraInstance.meteringBufferCount >= Self.audioLevelEmitEveryNBuffers else { return }

        let windowPeak = cameraInstance.meteringWindowPeak
        let windowRms = cameraInstance.meteringSampleCount > 0
            ? Float((cameraInstance.meteringSumSquares / Double(cameraInstance.meteringSampleCount)).squareRoot())
            : 0
        cameraInstance.meteringBufferCount = 0
        cameraInstance.meteringWindowPeak = 0
        cameraInstance.meteringSumSquares = 0
        cameraInstance.meteringSampleCount = 0

        // amplitude is the normalized window RMS [0,1] per the plan contract:
        // the silence threshold must not be reset by a single brief spike
        // inside a ~250 ms window, and the per-platform RC thresholds exist
        // precisely because iOS RMS runs lower than Android's peak-based
        // AudioStats.audioAmplitude. Peak is still exposed via peakDbfs.
        let event: [String: Any] = [
            "amplitude": Double(windowRms),
            "peakDbfs": 20 * log10(Double(max(windowPeak, 1e-6))),
            "averageDbfs": 20 * log10(Double(max(windowRms, 1e-6))),
            "audioState": "unknown",
            // Monotonic clock (never wall-time) — the Dart side uses this for
            // staleness detection across the stream.
            "timestampMs": Int(ProcessInfo.processInfo.systemUptime * 1000)
        ]
        DispatchQueue.main.async {
            handler.sendEvent(event)
        }
    }

    /// Reads Linear PCM samples (16-bit int, 32-bit int, or 32-bit float —
    /// the same formats the recording resampler accepts) and returns the
    /// buffer's normalized peak plus RMS accumulators. Returns nil for
    /// non-PCM or empty buffers.
    static func computeAudioLevels(from sampleBuffer: CMSampleBuffer) -> (peak: Float, sumSquares: Double, sampleCount: Int)? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
              asbd.pointee.mFormatID == kAudioFormatLinearPCM else {
            return nil
        }

        let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard sampleCount > 0,
              let inputFormat = AVAudioFormat(streamDescription: asbd),
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(sampleCount)) else {
            return nil
        }
        pcmBuffer.frameLength = AVAudioFrameCount(sampleCount)

        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(sampleCount),
            into: pcmBuffer.mutableAudioBufferList
        ) == noErr else {
            return nil
        }

        let channelCount = Int(inputFormat.channelCount)
        let frameLength = Int(pcmBuffer.frameLength)
        // Interleaved layouts pack every channel's samples into channelData[0];
        // deinterleaved layouts expose one pointer per channel.
        let pointerCount = inputFormat.isInterleaved ? 1 : channelCount
        let samplesPerPointer = inputFormat.isInterleaved ? frameLength * channelCount : frameLength
        guard pointerCount > 0, samplesPerPointer > 0 else { return nil }

        var peak: Float = 0
        var sumSquares: Double = 0

        if let floatData = pcmBuffer.floatChannelData {
            for pointerIndex in 0..<pointerCount {
                let samples = floatData[pointerIndex]
                for sampleIndex in 0..<samplesPerPointer {
                    let sample = samples[sampleIndex]
                    peak = max(peak, abs(sample))
                    sumSquares += Double(sample * sample)
                }
            }
        } else if let int16Data = pcmBuffer.int16ChannelData {
            for pointerIndex in 0..<pointerCount {
                let samples = int16Data[pointerIndex]
                for sampleIndex in 0..<samplesPerPointer {
                    let sample = Float(samples[sampleIndex]) / 32768.0
                    peak = max(peak, abs(sample))
                    sumSquares += Double(sample * sample)
                }
            }
        } else if let int32Data = pcmBuffer.int32ChannelData {
            for pointerIndex in 0..<pointerCount {
                let samples = int32Data[pointerIndex]
                for sampleIndex in 0..<samplesPerPointer {
                    let sample = Float(Double(samples[sampleIndex]) / 2147483648.0)
                    peak = max(peak, abs(sample))
                    sumSquares += Double(sample * sample)
                }
            }
        } else {
            return nil
        }

        return (peak, sumSquares, pointerCount * samplesPerPointer)
    }
}

class CameraPreviewTexture: NSObject, FlutterTexture, AVCaptureVideoDataOutputSampleBufferDelegate {
    private static let switchStabilizationFrameCount = 3
    var latestPixelBuffer: CVPixelBuffer?
    var textureId: Int64 = 0
    let captureSession: AVCaptureSession
    let videoDataOutput: AVCaptureVideoDataOutput
    let videoDataOutputQueue: DispatchQueue
    weak var textureRegistry: FlutterTextureRegistry?
    var lensPosition: AVCaptureDevice.Position = .back
    var onSampleBuffer: ((CMSampleBuffer, UInt64) -> Void)?
    private var stateLock = os_unfair_lock()
    private var cameraSwitchFrameGate = CameraSwitchFrameGate()
    
    init?(session: AVCaptureSession, textureRegistry: FlutterTextureRegistry, lensPosition: AVCaptureDevice.Position) {
        self.captureSession = session
        self.textureRegistry = textureRegistry
        self.lensPosition = lensPosition
        self.videoDataOutput = AVCaptureVideoDataOutput()
        self.videoDataOutputQueue = DispatchQueue(label: "VideoDataOutputQueue")
        
        super.init()
        
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
        } else {
            return nil
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        os_unfair_lock_lock(&stateLock)
        let shouldDropFrame = cameraSwitchFrameGate.shouldDropFrame()
        let switchGeneration = cameraSwitchFrameGate.generation
        os_unfair_lock_unlock(&stateLock)

        if shouldDropFrame {
            return
        }

        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            os_unfair_lock_lock(&stateLock)
            latestPixelBuffer = pixelBuffer
            os_unfair_lock_unlock(&stateLock)
            let tid = textureId
            DispatchQueue.main.async { [weak self] in
                self?.textureRegistry?.textureFrameAvailable(tid)
            }
        }
        
        onSampleBuffer?(sampleBuffer, switchGeneration)
    }
    
    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        os_unfair_lock_lock(&stateLock)
        guard let pixelBuffer = latestPixelBuffer else {
            os_unfair_lock_unlock(&stateLock)
            return nil
        }
        os_unfair_lock_unlock(&stateLock)
        return Unmanaged.passRetained(pixelBuffer)
    }

    func prepareForCameraSwitch(position: AVCaptureDevice.Position) -> UInt64 {
        os_unfair_lock_lock(&stateLock)
        latestPixelBuffer = nil
        let generation = cameraSwitchFrameGate.prepare()
        os_unfair_lock_unlock(&stateLock)
        let tid = textureId
        DispatchQueue.main.async { [weak self] in
            self?.textureRegistry?.textureFrameAvailable(tid)
        }
        return generation
    }

    func completeCameraSwitchStabilization() {
        os_unfair_lock_lock(&stateLock)
        cameraSwitchFrameGate.complete(
            stabilizationFrameCount: Self.switchStabilizationFrameCount
        )
        os_unfair_lock_unlock(&stateLock)
    }

    func cancelCameraSwitchStabilization() {
        os_unfair_lock_lock(&stateLock)
        cameraSwitchFrameGate.cancel()
        os_unfair_lock_unlock(&stateLock)
    }

    func updateForNewCamera(position: AVCaptureDevice.Position) {
        lensPosition = position
        if let connection = videoDataOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = (position == .front)
            }
        }
    }
}

class RecordingStateStreamHandler: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        events("idle")
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}

/// Stream handler for the per-camera audio-level EventChannel.
///
/// The sink is written from the platform thread (onListen/onCancel) and read
/// from the audio delegate queue (hasListener) and main queue (sendEvent), so
/// access is serialized with an internal lock.
class AudioLevelStreamHandler: NSObject, FlutterStreamHandler {
    private var lock = os_unfair_lock()
    private var eventSink: FlutterEventSink?

    var hasListener: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return eventSink != nil
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        os_unfair_lock_lock(&lock)
        eventSink = events
        os_unfair_lock_unlock(&lock)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        os_unfair_lock_lock(&lock)
        eventSink = nil
        os_unfair_lock_unlock(&lock)
        return nil
    }

    func sendEvent(_ event: [String: Any]) {
        os_unfair_lock_lock(&lock)
        let sink = eventSink
        os_unfair_lock_unlock(&lock)
        sink?(event)
    }
}

class AudioDeviceStreamHandler: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        
        let audioSession = AVAudioSession.sharedInstance()
        let currentRoute = audioSession.currentRoute
        let activeInput = currentRoute.inputs.first
        let deviceName = activeInput?.portName ?? "iPhone Microphone"
        let portType = activeInput?.portType.rawValue ?? "MicrophoneBuiltIn"
        let hasBluetoothInput = currentRoute.inputs.contains { port in
            PrettyAwesomeCameraPlugin.isBluetoothPort(port.portType)
        }
        
        events([
            "event": "initial",
            "deviceName": deviceName,
            "portType": portType,
            "isBluetooth": hasBluetoothInput
        ])
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
    
    func sendEvent(_ event: [String: Any]) {
        eventSink?(event)
    }
}
