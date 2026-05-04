import Flutter
import UIKit
import AVFoundation
import os.lock

public class PrettyAwesomeCameraPlugin: NSObject, FlutterPlugin {
    private var cameras: [Int: CameraInstance] = [:]
    private var nextCameraId = 0
    private var textureRegistry: FlutterTextureRegistry?
    private var eventChannels: [Int: FlutterEventChannel] = [:]
    private var streamHandlers: [Int: RecordingStateStreamHandler] = [:]
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
        var requestedPresetName: String = "high"
        var capturePreset: AVCaptureSession.Preset = .hd1280x720
        var captureDimensions: CMVideoDimensions = CMVideoDimensions(width: 1280, height: 720)
        var recordingURL: URL?
        var assetWriter: AVAssetWriter?
        var videoWriterInput: AVAssetWriterInput?
        var audioWriterInput: AVAssetWriterInput?
        var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
        var audioDataOutput: AVCaptureAudioDataOutput?
        fileprivate var recordingLock = os_unfair_lock()
        fileprivate var _isRecording: Bool = false
        fileprivate var _isPaused: Bool = false
        fileprivate var _videoIsDisconnected: Bool = false
        fileprivate var _audioIsDisconnected: Bool = false
        fileprivate var _recordingWarmupFramesRemaining: Int = 0
        fileprivate var _hasPrewarmedRecordingPipeline: Bool = false
        fileprivate var _videoTimeOffset: CMTime = .zero
        fileprivate var _audioTimeOffset: CMTime = .zero
        fileprivate var _lastVideoSampleTime: CMTime = .zero
        fileprivate var _lastAudioSampleTime: CMTime = .zero
        fileprivate var _isFirstVideoFrame: Bool = true
        fileprivate var _isFirstAudioFrame: Bool = true
        fileprivate var _sessionStartTime: CMTime = .zero
        var activeFrameRateMin: CMTime?
        var activeFrameRateMax: CMTime?
        var isUsingBluetoothInput: Bool = false
        var actualAudioSampleRate: Double = 44100
        
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
        
        var videoIsDisconnected: Bool {
            get {
                os_unfair_lock_lock(&recordingLock)
                defer { os_unfair_lock_unlock(&recordingLock) }
                return _videoIsDisconnected
            }
            set {
                os_unfair_lock_lock(&recordingLock)
                _videoIsDisconnected = newValue
                os_unfair_lock_unlock(&recordingLock)
            }
        }
        
        var audioIsDisconnected: Bool {
            get {
                os_unfair_lock_lock(&recordingLock)
                defer { os_unfair_lock_unlock(&recordingLock) }
                return _audioIsDisconnected
            }
            set {
                os_unfair_lock_lock(&recordingLock)
                _audioIsDisconnected = newValue
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

        var videoTimeOffset: CMTime {
            get {
                os_unfair_lock_lock(&recordingLock)
                defer { os_unfair_lock_unlock(&recordingLock) }
                return _videoTimeOffset
            }
            set {
                os_unfair_lock_lock(&recordingLock)
                _videoTimeOffset = newValue
                os_unfair_lock_unlock(&recordingLock)
            }
        }

        var audioTimeOffset: CMTime {
            get {
                os_unfair_lock_lock(&recordingLock)
                defer { os_unfair_lock_unlock(&recordingLock) }
                return _audioTimeOffset
            }
            set {
                os_unfair_lock_lock(&recordingLock)
                _audioTimeOffset = newValue
                os_unfair_lock_unlock(&recordingLock)
            }
        }

        var lastVideoSampleTime: CMTime {
            get {
                os_unfair_lock_lock(&recordingLock)
                defer { os_unfair_lock_unlock(&recordingLock) }
                return _lastVideoSampleTime
            }
            set {
                os_unfair_lock_lock(&recordingLock)
                _lastVideoSampleTime = newValue
                os_unfair_lock_unlock(&recordingLock)
            }
        }

        var lastAudioSampleTime: CMTime {
            get {
                os_unfair_lock_lock(&recordingLock)
                defer { os_unfair_lock_unlock(&recordingLock) }
                return _lastAudioSampleTime
            }
            set {
                os_unfair_lock_lock(&recordingLock)
                _lastAudioSampleTime = newValue
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
        case "pauseRecording":
            pauseRecording(call: call, result: result)
        case "resumeRecording":
            resumeRecording(call: call, result: result)
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
        
        let cameraId = nextCameraId
        nextCameraId += 1
        
        let lensDirection = cameraDescription?["lensDirection"] as? String ?? "front"
        let position: AVCaptureDevice.Position = lensDirection == "front" ? .front : .back
        let presetName = (args?["preset"] as? String) ?? "high"
        
        let instance = CameraInstance(cameraId: cameraId)
        instance.lensPosition = position
        instance.requestedPresetName = presetName
        
        os_unfair_lock_lock(&stateLock)
        cameras[cameraId] = instance
        os_unfair_lock_unlock(&stateLock)
        
        result(cameraId)
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
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.allowBluetooth, .allowBluetoothA2DP])
                try audioSession.setActive(true)
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
            cameraInstance.capturePreset = resolvedPreset
            cameraInstance.captureDimensions = dimensions(for: resolvedPreset)
            
            if let textureRegistry = textureRegistry {
                guard let texture = CameraPreviewTexture(
                    session: captureSession,
                    textureRegistry: textureRegistry,
                    lensPosition: cameraInstance.lensPosition
                ) else {
                    result(FlutterError(code: "TEXTURE_ERROR", message: "Failed to create preview texture", details: nil))
                    return
                }
                
                texture.onSampleBuffer = { [weak self, weak cameraInstance] sampleBuffer in
                    guard let self = self, let cameraInstance = cameraInstance else { return }
                    self.handleVideoSampleBuffer(sampleBuffer, for: cameraInstance)
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
            }
            
            sessionQueue.sync {
                cameraInstance.previewTexture?.updateForNewCamera(position: cameraInstance.lensPosition)
                captureSession.startRunning()
                cameraInstance.previewTexture?.updateForNewCamera(position: cameraInstance.lensPosition)
            }

            sessionQueue.async { [weak self, weak cameraInstance] in
                guard let self = self, let cameraInstance = cameraInstance else { return }
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
            cameraInstance.isRecording = false
            if assetWriter.status == .writing {
                assetWriter.finishWriting {}
            }
        }
        
        cameraInstance.captureSession?.stopRunning()
        if let textureId = cameraInstance.textureId {
            textureRegistry?.unregisterTexture(textureId)
        }
        
        if let eventChannel = eventChannels[cameraId] {
            eventChannel.setStreamHandler(nil)
            eventChannels.removeValue(forKey: cameraId)
        }
        streamHandlers.removeValue(forKey: cameraId)
        
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
        }

        result(nil)
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
        case .oldDeviceUnavailable:
            for cameraInstance in activeCameras where cameraInstance.isRecording {
                cameraInstance.audioIsDisconnected = true
            }
        case .newDeviceAvailable:
            for cameraInstance in activeCameras where cameraInstance.isRecording {
                cameraInstance.audioIsDisconnected = true
            }
        default:
            break
        }
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
            let audioSession = AVAudioSession.sharedInstance()
            let currentRoute = audioSession.currentRoute
            let isBluetoothInput = currentRoute.inputs.contains { port in
                port.portType == .bluetoothHFP || port.portType == .bluetoothA2DP
            }
            cameraInstance.isUsingBluetoothInput = isBluetoothInput
            
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
            let recordingURL = tempDir.appendingPathComponent("recording_\(Int(Date().timeIntervalSince1970)).mov")
            
            do {
                let assetWriter = try AVAssetWriter(url: recordingURL, fileType: .mov)
                
                let videoWidth = Int(cameraInstance.captureDimensions.width)
                let videoHeight = Int(cameraInstance.captureDimensions.height)
                
                let outputWidth = videoHeight
                let outputHeight = videoWidth

                let videoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: outputWidth,
                    AVVideoHeightKey: outputHeight
                ]
                let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                videoWriterInput.expectsMediaDataInRealTime = true
                
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: cameraInstance.actualAudioSampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: cameraInstance.actualAudioSampleRate >= 44100 ? 128000 : 64000
            ]
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
            cameraInstance.pixelBufferAdaptor = nil
            
            // Capture frame rate configuration for preservation during camera switches
            if let captureSession = cameraInstance.captureSession {
                let videoInputs = captureSession.inputs.compactMap { $0 as? AVCaptureDeviceInput }.filter { $0.device.hasMediaType(.video) }
                if let videoDevice = videoInputs.first?.device {
                    cameraInstance.activeFrameRateMin = videoDevice.activeVideoMinFrameDuration
                    cameraInstance.activeFrameRateMax = videoDevice.activeVideoMaxFrameDuration
                }
            }
            
            cameraInstance.isRecording = true
            cameraInstance.isPaused = false
            cameraInstance.videoIsDisconnected = false
            cameraInstance.audioIsDisconnected = false
                cameraInstance.videoTimeOffset = .zero
                cameraInstance.audioTimeOffset = .zero
                cameraInstance.lastVideoSampleTime = .zero
                cameraInstance.lastAudioSampleTime = .zero
                cameraInstance.isFirstVideoFrame = true
                cameraInstance.isFirstAudioFrame = true
                cameraInstance.sessionStartTime = .zero
                cameraInstance.recordingWarmupFramesRemaining = 3
                
                DispatchQueue.main.async {
                    result(nil)
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
        if cameraInstance._isPaused {
            if !cameraInstance._isFirstVideoFrame {
                cameraInstance._videoIsDisconnected = true
            }
            if !cameraInstance._isFirstAudioFrame {
                cameraInstance._audioIsDisconnected = true
            }
            cameraInstance._isPaused = false
        }
        os_unfair_lock_unlock(&cameraInstance.recordingLock)
        
        result(nil)
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
                    print("Warning: Failed to apply frame rate during camera switch: \(error.localizedDescription)")
                }
            }
            
            sessionQueue.sync {
                if cameraInstance.isRecording {
                    if !cameraInstance.isFirstVideoFrame {
                        cameraInstance.videoIsDisconnected = true
                    }
                    if !cameraInstance.isFirstAudioFrame {
                        cameraInstance.audioIsDisconnected = true
                    }
                }
                
                cameraInstance.previewTexture?.prepareForCameraSwitch(position: newPosition)
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
                    switchError = FlutterError(code: "SWITCH_ERROR", message: "Unable to add new camera input", details: nil)
                    return
                }
                captureSession.addInput(videoInput)

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
                    captureSession.commitConfiguration()
                    switchError = FlutterError(code: "SWITCH_UNSUPPORTED", message: "New camera does not support the active recording configuration", details: nil)
                    return
                }

                captureSession.sessionPreset = targetPreset

                if !cameraInstance.isRecording {
                    cameraInstance.capturePreset = targetPreset
                    cameraInstance.captureDimensions = dimensions(for: targetPreset)
                }
                
                captureSession.commitConfiguration()
                cameraInstance.previewTexture?.updateForNewCamera(position: newPosition)
                cameraInstance.previewTexture?.beginPostSwitchStabilization()
            }

            if let switchError {
                result(switchError)
                return
            }

            DispatchQueue.main.async {
                cameraInstance.previewTexture?.updateForNewCamera(position: newPosition)
            }

            cameraInstance.lensPosition = newPosition
            
            if let textureId = cameraInstance.textureId {
                result(cameraInitializationResult(textureId: textureId, captureDimensions: cameraInstance.captureDimensions))
            } else {
                result(FlutterError(code: "TEXTURE_ERROR", message: "No texture ID available", details: nil))
            }
        } catch {
            result(FlutterError(code: "SWITCH_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    private func cameraInitializationResult(textureId: Int64, captureDimensions: CMVideoDimensions) -> [String: Any] {
        return [
            "textureId": Int(textureId),
            "previewSize": [
                "width": Int(captureDimensions.width),
                "height": Int(captureDimensions.height)
            ]
        ]
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
            result(FlutterError(code: "NOT_RECORDING", message: "No active recording", details: nil))
            return
        }
        
        cameraInstance.isRecording = false
        cameraInstance.isPaused = false

        // Clear frame rate storage when recording stops
        cameraInstance.activeFrameRateMin = nil
        cameraInstance.activeFrameRateMax = nil

        guard let assetWriter = cameraInstance.assetWriter else {
            result(FlutterError(code: "WRITER_ERROR", message: "No asset writer available", details: nil))
            return
        }
        
        let recordingPath = cameraInstance.recordingURL?.path
        
        if assetWriter.status == .writing {
            assetWriter.finishWriting {
                DispatchQueue.main.async {
                    if assetWriter.status == .completed {
                        result(recordingPath)
                    } else {
                        let error = assetWriter.error?.localizedDescription ?? "Unknown error"
                        result(FlutterError(code: "FINISH_ERROR", message: error, details: nil))
                    }
                }
            }
        } else {
            result(FlutterError(code: "NOT_RECORDING", message: "Recording was not started", details: nil))
        }
    }
    
    private func handleVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer, for cameraInstance: CameraInstance) {
        guard cameraInstance.isRecording,
              let assetWriter = cameraInstance.assetWriter,
              let videoInput = cameraInstance.videoWriterInput else {
            return
        }
        
        let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        if cameraInstance.isPaused {
            return
        }
        
        if cameraInstance.isFirstVideoFrame {
            if cameraInstance.recordingWarmupFramesRemaining > 0 {
                cameraInstance.recordingWarmupFramesRemaining -= 1
                cameraInstance.lastVideoSampleTime = currentTime
                return
            }

            if assetWriter.status == .unknown {
                assetWriter.startWriting()
                if assetWriter.status == .failed {
                    print("Asset writer failed to start: \(assetWriter.error?.localizedDescription ?? "unknown error")")
                }
                assetWriter.startSession(atSourceTime: currentTime)
                cameraInstance.sessionStartTime = currentTime
            }
            cameraInstance.isFirstVideoFrame = false
            cameraInstance.lastVideoSampleTime = currentTime
        } else {
            if cameraInstance.videoIsDisconnected {
                cameraInstance.videoIsDisconnected = false
                let offset = CMTimeSubtract(currentTime, cameraInstance.lastVideoSampleTime)
                cameraInstance.videoTimeOffset = CMTimeAdd(cameraInstance.videoTimeOffset, offset)
                cameraInstance.lastVideoSampleTime = currentTime
                return
            }

            if !videoInput.isReadyForMoreMediaData {
                let droppedDuration = CMTimeSubtract(currentTime, cameraInstance.lastVideoSampleTime)
                cameraInstance.videoTimeOffset = CMTimeAdd(cameraInstance.videoTimeOffset, droppedDuration)
                cameraInstance.lastVideoSampleTime = currentTime
                return
            }

            cameraInstance.lastVideoSampleTime = currentTime
        }
        
        let adjustedTime = CMTimeSubtract(currentTime, cameraInstance.videoTimeOffset)

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
            videoInput.append(adjustedBuffer)
        }
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

        let audioSession = AVAudioSession.sharedInstance()
        let currentRoute = audioSession.currentRoute
        let isBluetoothInput = currentRoute.inputs.contains { port in
            port.portType == .bluetoothHFP || port.portType == .bluetoothA2DP
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

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: outputWidth,
                AVVideoHeightKey: outputHeight
            ]
            let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoWriterInput.expectsMediaDataInRealTime = true

            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: cameraInstance.actualAudioSampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: cameraInstance.actualAudioSampleRate >= 44100 ? 128000 : 64000
            ]
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
        
        if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
            let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
            if let asbd = audioStreamBasicDescription {
                let detectedSampleRate = asbd.pointee.mSampleRate
                if cameraInstance.actualAudioSampleRate != detectedSampleRate {
                    cameraInstance.actualAudioSampleRate = detectedSampleRate
                }
            }
        }
        
        let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        guard cameraInstance.isRecording,
              let audioInput = cameraInstance.audioWriterInput else {
            return
        }
        
        if cameraInstance.isPaused {
            return
        }

        guard cameraInstance.sessionStartTime != .zero else {
            cameraInstance.lastAudioSampleTime = currentTime
            return
        }
        
        if cameraInstance.isFirstAudioFrame {
            cameraInstance.isFirstAudioFrame = false
            cameraInstance.lastAudioSampleTime = currentTime
            cameraInstance.audioTimeOffset = CMTimeSubtract(currentTime, cameraInstance.sessionStartTime)
        }
        
        if cameraInstance.audioIsDisconnected {
            if cameraInstance.previewTexture?.isDroppingFramesAfterSwitch ?? false {
                return
            }
            cameraInstance.audioIsDisconnected = false
            let offset = CMTimeSubtract(currentTime, cameraInstance.lastAudioSampleTime)
            cameraInstance.audioTimeOffset = CMTimeAdd(cameraInstance.audioTimeOffset, offset)
            cameraInstance.lastAudioSampleTime = currentTime
            return
        }

        if !audioInput.isReadyForMoreMediaData {
            let droppedDuration = CMTimeSubtract(currentTime, cameraInstance.lastAudioSampleTime)
            cameraInstance.audioTimeOffset = CMTimeAdd(cameraInstance.audioTimeOffset, droppedDuration)
            cameraInstance.lastAudioSampleTime = currentTime
            return
        }
        
        cameraInstance.lastAudioSampleTime = currentTime
        
        let adjustedTime = CMTimeSubtract(currentTime, cameraInstance.audioTimeOffset)
        
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
            audioInput.append(adjustedBuffer)
        }
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
    var onSampleBuffer: ((CMSampleBuffer) -> Void)?
    private var stateLock = os_unfair_lock()
    private var framesToDropAfterSwitch = 0
    
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
        var shouldDropFrame = false
        os_unfair_lock_lock(&stateLock)
        if framesToDropAfterSwitch > 0 {
            framesToDropAfterSwitch -= 1
            shouldDropFrame = true
        }
        os_unfair_lock_unlock(&stateLock)

        if shouldDropFrame {
            return
        }

        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            os_unfair_lock_lock(&stateLock)
            latestPixelBuffer = pixelBuffer
            os_unfair_lock_unlock(&stateLock)
            textureRegistry?.textureFrameAvailable(textureId)
        }
        
        onSampleBuffer?(sampleBuffer)
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

    func prepareForCameraSwitch(position: AVCaptureDevice.Position) {
        os_unfair_lock_lock(&stateLock)
        latestPixelBuffer = nil
        framesToDropAfterSwitch = Self.switchStabilizationFrameCount
        os_unfair_lock_unlock(&stateLock)
        textureRegistry?.textureFrameAvailable(textureId)
    }

    func beginPostSwitchStabilization() {
        os_unfair_lock_lock(&stateLock)
        framesToDropAfterSwitch = Self.switchStabilizationFrameCount
        os_unfair_lock_unlock(&stateLock)
    }

    var isDroppingFramesAfterSwitch: Bool {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        return framesToDropAfterSwitch > 0
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
