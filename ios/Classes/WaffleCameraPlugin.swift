import Flutter
import UIKit
import AVFoundation
import os.lock

public class WaffleCameraPlugin: NSObject, FlutterPlugin {
    private var cameras: [Int: CameraInstance] = [:]
    private var nextCameraId = 0
    private var textureRegistry: FlutterTextureRegistry?
    private var eventChannels: [Int: FlutterEventChannel] = [:]
    private var registrar: FlutterPluginRegistrar?
    private let sessionQueue = DispatchQueue(label: "com.waffle.camera.session")
    private var stateLock = os_unfair_lock()
    
    class CameraInstance {
        let cameraId: Int
        var captureSession: AVCaptureSession?
        var previewTexture: CameraPreviewTexture?
        var textureId: Int64?
        var lensPosition: AVCaptureDevice.Position = .back
        var recordingURL: URL?
        var assetWriter: AVAssetWriter?
        var videoWriterInput: AVAssetWriterInput?
        var audioWriterInput: AVAssetWriterInput?
        var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
        var audioDataOutput: AVCaptureAudioDataOutput?
        private var recordingLock = os_unfair_lock()
        private var _isRecording: Bool = false
        private var _isPaused: Bool = false
        private var _videoIsDisconnected: Bool = false
        private var _audioIsDisconnected: Bool = false
        var videoTimeOffset: CMTime = .zero
        var audioTimeOffset: CMTime = .zero
        var lastVideoSampleTime: CMTime = .zero
        var lastAudioSampleTime: CMTime = .zero
        var isFirstVideoFrame: Bool = true
        var isFirstAudioFrame: Bool = true
        var sessionStartTime: CMTime = .zero
        
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
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "waffle_camera_plugin", binaryMessenger: registrar.messenger())
        let instance = WaffleCameraPlugin()
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
        guard let args = call.arguments as? [String: Any],
              let cameraDescription = args["camera"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Camera description required", details: nil))
            return
        }
        
        let cameraId = nextCameraId
        nextCameraId += 1
        
        let lensDirection = cameraDescription["lensDirection"] as? String ?? "back"
        let position: AVCaptureDevice.Position = lensDirection == "front" ? .front : .back
        
        let instance = CameraInstance(cameraId: cameraId)
        instance.lensPosition = position
        
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
        
        let captureSession = AVCaptureSession()
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraInstance.lensPosition) else {
            result(FlutterError(code: "NO_CAMERA", message: "Camera device not available", details: nil))
            return
        }
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            }
            
            if let audioDevice = AVCaptureDevice.default(for: .audio) {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if captureSession.canAddInput(audioInput) {
                    captureSession.addInput(audioInput)
                }
            }
            
            let audioDataOutput = AVCaptureAudioDataOutput()
            let audioQueue = DispatchQueue(label: "com.waffle.camera.audio")
            audioDataOutput.setSampleBufferDelegate(self, queue: audioQueue)
            if captureSession.canAddOutput(audioDataOutput) {
                captureSession.addOutput(audioDataOutput)
            }
            cameraInstance.audioDataOutput = audioDataOutput
            
            cameraInstance.captureSession = captureSession
            
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
                    name: "waffle_camera_plugin/recording_state_\(cameraId)",
                    binaryMessenger: registrar.messenger()
                )
                let streamHandler = RecordingStateStreamHandler()
                stateChannel.setStreamHandler(streamHandler)
                eventChannels[cameraId] = stateChannel
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                captureSession.startRunning()
            }
            
            if let textureId = cameraInstance.textureId {
                result(textureId)
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
        
        result(nil)
    }
    
    private func startRecording(call: FlutterMethodCall, result: @escaping FlutterResult) {
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
        
        let tempDir = FileManager.default.temporaryDirectory
        let recordingURL = tempDir.appendingPathComponent("recording_\(Int(Date().timeIntervalSince1970)).mov")
        
        do {
            let assetWriter = try AVAssetWriter(url: recordingURL, fileType: .mov)
            
            var videoWidth: Int = 1920
            var videoHeight: Int = 1080
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraInstance.lensPosition) {
                let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
                videoWidth = Int(dimensions.width)
                videoHeight = Int(dimensions.height)
            }
            
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: videoWidth,
                AVVideoHeightKey: videoHeight
            ]
            let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoWriterInput.expectsMediaDataInRealTime = true
            
            let sourcePixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: videoWidth,
                kCVPixelBufferHeightKey as String: videoHeight
            ]
            let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoWriterInput,
                sourcePixelBufferAttributes: sourcePixelBufferAttributes
            )
            
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128000
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
            cameraInstance.pixelBufferAdaptor = pixelBufferAdaptor
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
            
            result(nil)
        } catch {
            result(FlutterError(code: "WRITER_ERROR", message: error.localizedDescription, details: nil))
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
        
        if cameraInstance.isRecording && !cameraInstance.isPaused {
            cameraInstance.isPaused = true
        }
        
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
        
        if cameraInstance.isRecording && cameraInstance.isPaused {
            cameraInstance.isPaused = false
        }
        
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
        
        if cameraInstance.isRecording {
            cameraInstance.videoIsDisconnected = true
            cameraInstance.audioIsDisconnected = true
        }
        
        do {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else {
                result(FlutterError(code: "NO_CAMERA", message: "Camera device not available", details: nil))
                return
            }
            
            let videoInput = try AVCaptureDeviceInput(device: device)
            
            sessionQueue.async {
                captureSession.beginConfiguration()
                
                for input in captureSession.inputs.compactMap({ $0 as? AVCaptureDeviceInput }) where input.device.hasMediaType(.video) {
                    captureSession.removeInput(input)
                }
                
                if captureSession.canAddInput(videoInput) {
                    captureSession.addInput(videoInput)
                }
                
                captureSession.commitConfiguration()
            }
            
            cameraInstance.previewTexture?.updateForNewCamera(position: newPosition)
            cameraInstance.lensPosition = newPosition
            
            if let textureId = cameraInstance.textureId {
                result(textureId)
            } else {
                result(FlutterError(code: "TEXTURE_ERROR", message: "No texture ID available", details: nil))
            }
        } catch {
            result(FlutterError(code: "SWITCH_ERROR", message: error.localizedDescription, details: nil))
        }
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
              let assetWriter = cameraInstance.assetWriter else {
            return
        }
        
        guard !cameraInstance.isPaused else {
            return
        }
        
        let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        if cameraInstance.isFirstVideoFrame {
            if assetWriter.status == .unknown {
                assetWriter.startWriting()
                assetWriter.startSession(atSourceTime: currentTime)
            }
            cameraInstance.isFirstVideoFrame = false
            cameraInstance.lastVideoSampleTime = currentTime
            return
        }
        
        if cameraInstance.videoIsDisconnected {
            cameraInstance.videoIsDisconnected = false
            let offset = CMTimeSubtract(currentTime, cameraInstance.lastVideoSampleTime)
            cameraInstance.videoTimeOffset = CMTimeAdd(cameraInstance.videoTimeOffset, offset)
            return
        }
        
        cameraInstance.lastVideoSampleTime = currentTime
        
        let adjustedTime = CMTimeSubtract(currentTime, cameraInstance.videoTimeOffset)
        
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
           let adaptor = cameraInstance.pixelBufferAdaptor,
           let videoInput = cameraInstance.videoWriterInput,
           videoInput.isReadyForMoreMediaData {
            adaptor.append(pixelBuffer, withPresentationTime: adjustedTime)
        }
    }
}

extension WaffleCameraPlugin: AVCaptureAudioDataOutputSampleBufferDelegate {
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
        
        guard cameraInstance.isRecording,
              !cameraInstance.isPaused,
              let audioInput = cameraInstance.audioWriterInput,
              audioInput.isReadyForMoreMediaData else {
            return
        }
        
        let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        if cameraInstance.isFirstAudioFrame {
            cameraInstance.isFirstAudioFrame = false
            cameraInstance.lastAudioSampleTime = currentTime
            return
        }
        
        if cameraInstance.audioIsDisconnected {
            cameraInstance.audioIsDisconnected = false
            let offset = CMTimeSubtract(currentTime, cameraInstance.lastAudioSampleTime)
            cameraInstance.audioTimeOffset = CMTimeAdd(cameraInstance.audioTimeOffset, offset)
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
    var latestPixelBuffer: CVPixelBuffer?
    var textureId: Int64 = 0
    let captureSession: AVCaptureSession
    let videoDataOutput: AVCaptureVideoDataOutput
    let videoDataOutputQueue: DispatchQueue
    weak var textureRegistry: FlutterTextureRegistry?
    var lensPosition: AVCaptureDevice.Position = .back
    var onSampleBuffer: ((CMSampleBuffer) -> Void)?
    
    init?(session: AVCaptureSession, textureRegistry: FlutterTextureRegistry, lensPosition: AVCaptureDevice.Position) {
        self.captureSession = session
        self.textureRegistry = textureRegistry
        self.lensPosition = lensPosition
        self.videoDataOutput = AVCaptureVideoDataOutput()
        self.videoDataOutputQueue = DispatchQueue(label: "VideoDataOutputQueue")
        
        super.init()
        
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
            
            if let connection = videoDataOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                if connection.isVideoMirroringSupported && lensPosition == .front {
                    connection.isVideoMirrored = true
                }
            }
        } else {
            return nil
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            latestPixelBuffer = pixelBuffer
            textureRegistry?.textureFrameAvailable(textureId)
        }
        
        onSampleBuffer?(sampleBuffer)
    }
    
    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let pixelBuffer = latestPixelBuffer else {
            return nil
        }
        return Unmanaged.passRetained(pixelBuffer)
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
