import Flutter
import UIKit
import AVFoundation

public class WaffleCameraPlugin: NSObject, FlutterPlugin {
    private var cameras: [Int: CameraInstance] = [:]
    private var nextCameraId = 0
    private var textureRegistry: FlutterTextureRegistry?
    private var eventChannels: [Int: FlutterEventChannel] = [:]
    private var registrar: FlutterPluginRegistrar?
    private let sessionQueue = DispatchQueue(label: "com.waffle.camera.session")
    
    struct CameraInstance {
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
        var isRecording: Bool = false
        var isPaused: Bool = false
        var videoIsDisconnected: Bool = false
        var audioIsDisconnected: Bool = false
        var videoTimeOffset: CMTime = .zero
        var audioTimeOffset: CMTime = .zero
        var lastVideoSampleTime: CMTime = .zero
        var lastAudioSampleTime: CMTime = .zero
        var isFirstVideoFrame: Bool = true
        var isFirstAudioFrame: Bool = true
        var sessionStartTime: CMTime = .zero
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
        
        cameras[cameraId] = CameraInstance(
            cameraId: cameraId,
            lensPosition: position
        )
        
        result(cameraId)
    }
    
    private func initializeCamera(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let cameraId = args["cameraId"] as? Int,
              var cameraInstance = cameras[cameraId] else {
            result(FlutterError(code: "INVALID_CAMERA", message: "Camera not found", details: nil))
            return
        }
        
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
                
                texture.onSampleBuffer = { [weak self] sampleBuffer in
                    self?.handleVideoSampleBuffer(sampleBuffer, for: cameraId)
                }
                
                let textureId = textureRegistry.register(texture)
                texture.textureId = textureId
                cameraInstance.textureId = textureId
                cameraInstance.previewTexture = texture
            }
            
            cameras[cameraId] = cameraInstance
            
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
              let cameraId = args["cameraId"] as? Int,
              var cameraInstance = cameras[cameraId] else {
            result(nil)
            return
        }
        
        if cameraInstance.isRecording, let assetWriter = cameraInstance.assetWriter {
            cameraInstance.isRecording = false
            assetWriter.finishWriting {}
        }
        
        cameraInstance.captureSession?.stopRunning()
        if let textureId = cameraInstance.textureId {
            textureRegistry?.unregisterTexture(textureId)
        }
        
        if let eventChannel = eventChannels[cameraId] {
            eventChannel.setStreamHandler(nil)
            eventChannels.removeValue(forKey: cameraId)
        }
        
        cameras.removeValue(forKey: cameraId)
        result(nil)
    }
    
    private func startRecording(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let cameraId = args["cameraId"] as? Int,
              var cameraInstance = cameras[cameraId],
              let captureSession = cameraInstance.captureSession else {
            result(FlutterError(code: "INVALID_CAMERA", message: "Camera not found or not initialized", details: nil))
            return
        }
        
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
            
            cameras[cameraId] = cameraInstance
            
            result(nil)
        } catch {
            result(FlutterError(code: "WRITER_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func pauseRecording(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let cameraId = args["cameraId"] as? Int,
              var cameraInstance = cameras[cameraId] else {
            result(FlutterError(code: "INVALID_CAMERA", message: "Camera not found", details: nil))
            return
        }
        
        if cameraInstance.isRecording && !cameraInstance.isPaused {
            cameraInstance.isPaused = true
            cameras[cameraId] = cameraInstance
        }
        
        result(nil)
    }
    
    private func resumeRecording(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let cameraId = args["cameraId"] as? Int,
              var cameraInstance = cameras[cameraId] else {
            result(FlutterError(code: "INVALID_CAMERA", message: "Camera not found", details: nil))
            return
        }
        
        if cameraInstance.isRecording && cameraInstance.isPaused {
            cameraInstance.isPaused = false
            cameras[cameraId] = cameraInstance
        }
        
        result(nil)
    }
    
    private func canSwitchCamera(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let cameraId = args["cameraId"] as? Int,
              let cameraInstance = cameras[cameraId] else {
            result(false)
            return
        }
        result(cameraInstance.isRecording)
    }
    
    private func canSwitchCurrentCamera(call: FlutterMethodCall, result: @escaping FlutterResult) {
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
              let cameraId = args["cameraId"] as? Int,
              var cameraInstance = cameras[cameraId],
              let captureSession = cameraInstance.captureSession else {
            result(FlutterError(code: "INVALID_CAMERA", message: "Camera not found or not initialized", details: nil))
            return
        }
        
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
            cameras[cameraId] = cameraInstance
            
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
              let cameraId = args["cameraId"] as? Int,
              var cameraInstance = cameras[cameraId] else {
            result(FlutterError(code: "INVALID_CAMERA", message: "Camera not found", details: nil))
            return
        }
        
        guard cameraInstance.isRecording else {
            result(FlutterError(code: "NOT_RECORDING", message: "No active recording", details: nil))
            return
        }
        
        cameraInstance.isRecording = false
        cameraInstance.isPaused = false
        cameras[cameraId] = cameraInstance
        
        guard let assetWriter = cameraInstance.assetWriter else {
            result(FlutterError(code: "WRITER_ERROR", message: "No asset writer available", details: nil))
            return
        }
        
        let recordingPath = cameraInstance.recordingURL?.path
        
        assetWriter.finishWriting {
            DispatchQueue.main.async {
                if assetWriter.status == .completed {
                    result(recordingPath)
                } else {
                    let error = assetWriter.error?.localizedDescription ?? "Unknown error"
                    result(FlutterError(code: "FINISH_ERROR", message: error, details: nil))
                }
            }
            
            if var inst = self.cameras[cameraId] {
                inst.assetWriter = nil
                inst.videoWriterInput = nil
                inst.audioWriterInput = nil
                inst.pixelBufferAdaptor = nil
                inst.recordingURL = nil
                self.cameras[cameraId] = inst
            }
        }
    }
    
    private func handleVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer, for cameraId: Int) {
        sessionQueue.sync {
            guard var inst = cameras[cameraId] else { return }
            
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                inst.previewTexture?.latestPixelBuffer = pixelBuffer
                if let textureId = inst.textureId {
                    textureRegistry?.textureFrameAvailable(textureId)
                }
            }
            
            guard inst.isRecording, let assetWriter = inst.assetWriter else {
                cameras[cameraId] = inst
                return
            }
            
            guard !inst.isPaused else {
                cameras[cameraId] = inst
                return
            }
            
            let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            
            if inst.isFirstVideoFrame {
                if assetWriter.status == .unknown {
                    assetWriter.startWriting()
                    assetWriter.startSession(atSourceTime: currentTime)
                    inst.sessionStartTime = currentTime
                }
                inst.isFirstVideoFrame = false
                inst.lastVideoSampleTime = currentTime
                cameras[cameraId] = inst
                return
            }
            
            if inst.videoIsDisconnected {
                inst.videoIsDisconnected = false
                let offset = CMTimeSubtract(currentTime, inst.lastVideoSampleTime)
                inst.videoTimeOffset = CMTimeAdd(inst.videoTimeOffset, offset)
                cameras[cameraId] = inst
                return
            }
            
            inst.lastVideoSampleTime = currentTime
            cameras[cameraId] = inst
            
            let adjustedTime = CMTimeSubtract(currentTime, inst.videoTimeOffset)
            
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
               let adaptor = inst.pixelBufferAdaptor,
               let videoInput = inst.videoWriterInput,
               videoInput.isReadyForMoreMediaData {
                adaptor.append(pixelBuffer, withPresentationTime: adjustedTime)
            }
        }
    }
}

extension WaffleCameraPlugin: AVCaptureAudioDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard output is AVCaptureAudioDataOutput else { return }
        
        var targetCameraId: Int?
        sessionQueue.sync {
            for (cameraId, inst) in cameras {
                if inst.audioDataOutput === output as? AVCaptureAudioDataOutput {
                    targetCameraId = cameraId
                    break
                }
            }
        }
        
        guard let cameraId = targetCameraId else { return }
        
        sessionQueue.sync {
            guard var inst = cameras[cameraId],
                  inst.isRecording,
                  !inst.isPaused,
                  let audioInput = inst.audioWriterInput,
                  audioInput.isReadyForMoreMediaData else {
                return
            }
            
            let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            
            if inst.isFirstAudioFrame {
                inst.isFirstAudioFrame = false
                inst.lastAudioSampleTime = currentTime
                cameras[cameraId] = inst
                return
            }
            
            if inst.audioIsDisconnected {
                inst.audioIsDisconnected = false
                let offset = CMTimeSubtract(currentTime, inst.lastAudioSampleTime)
                inst.audioTimeOffset = CMTimeAdd(inst.audioTimeOffset, offset)
                cameras[cameraId] = inst
                return
            }
            
            inst.lastAudioSampleTime = currentTime
            cameras[cameraId] = inst
            
            let adjustedTime = CMTimeSubtract(currentTime, inst.audioTimeOffset)
            
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
