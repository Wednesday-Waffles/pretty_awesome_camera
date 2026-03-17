import Flutter
import UIKit
import AVFoundation

public class WaffleCameraPlugin: NSObject, FlutterPlugin {
    private var cameras: [Int: CameraInstance] = [:]
    private var nextCameraId = 0
    private var textureRegistry: FlutterTextureRegistry?
    private var eventChannels: [Int: FlutterEventChannel] = [:]
    private var eventSinks: [Int: FlutterEventSink] = [:]
    private var registrar: FlutterPluginRegistrar?
    
    struct CameraInstance {
        let cameraId: Int
        var captureSession: AVCaptureSession?
        var videoOutput: AVCaptureMovieFileOutput?
        var textureId: Int64?
        var lensPosition: AVCaptureDevice.Position = .back
        var recordingURL: URL?
        var segmentURLs: [URL] = []
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
            
            let videoOutput = AVCaptureMovieFileOutput()
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
                
                if let connection = videoOutput.connection(with: .video) {
                    if connection.isVideoOrientationSupported {
                        connection.videoOrientation = .portrait
                    }
                }
            }
            
            cameraInstance.captureSession = captureSession
            cameraInstance.videoOutput = videoOutput
            
            if let textureRegistry = textureRegistry {
                guard let texture = CameraPreviewTexture(
                    session: captureSession,
                    textureRegistry: textureRegistry,
                    lensPosition: cameraInstance.lensPosition
                ) else {
                    result(FlutterError(code: "TEXTURE_ERROR", message: "Failed to create preview texture", details: nil))
                    return
                }
                let textureId = textureRegistry.register(texture)
                texture.textureId = textureId
                cameraInstance.textureId = textureId
            }
            
            cameras[cameraId] = cameraInstance
            
            if let registrar = registrar {
                let eventChannel = FlutterEventChannel(
                    name: "waffle_camera_plugin/recording_state_\(cameraId)",
                    binaryMessenger: registrar.messenger()
                )
                let streamHandler = RecordingStateStreamHandler()
                eventChannel.setStreamHandler(streamHandler)
                eventChannels[cameraId] = eventChannel
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
              let cameraInstance = cameras[cameraId] else {
            result(nil)
            return
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
              let videoOutput = cameraInstance.videoOutput else {
            result(FlutterError(code: "INVALID_CAMERA", message: "Camera not found or not initialized", details: nil))
            return
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let recordingURL = tempDir.appendingPathComponent("recording_\(Int(Date().timeIntervalSince1970)).mov")
        
        videoOutput.startRecording(to: recordingURL, recordingDelegate: self)
        cameraInstance.recordingURL = recordingURL
        cameras[cameraId] = cameraInstance
        result(nil)
    }
    
    private func pauseRecording(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let cameraId = args["cameraId"] as? Int,
              let cameraInstance = cameras[cameraId],
              let videoOutput = cameraInstance.videoOutput else {
            result(FlutterError(code: "INVALID_CAMERA", message: "Camera not found", details: nil))
            return
        }
        
        if #available(iOS 18.0, *) {
            videoOutput.pauseRecording()
            result(nil)
        } else {
            result(FlutterError(code: "UNSUPPORTED", message: "Pause requires iOS 18+", details: nil))
        }
    }
    
    private func resumeRecording(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let cameraId = args["cameraId"] as? Int,
              let cameraInstance = cameras[cameraId],
              let videoOutput = cameraInstance.videoOutput else {
            result(FlutterError(code: "INVALID_CAMERA", message: "Camera not found", details: nil))
            return
        }
        
        if #available(iOS 18.0, *) {
            videoOutput.resumeRecording()
            result(nil)
        } else {
            result(FlutterError(code: "UNSUPPORTED", message: "Resume requires iOS 18+", details: nil))
        }
    }
    
    private func canSwitchCamera(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let cameraId = args["cameraId"] as? Int,
              let cameraInstance = cameras[cameraId],
              let videoOutput = cameraInstance.videoOutput else {
            result(false)
            return
        }
        result(videoOutput.isRecording)
    }
    
    private func canSwitchCurrentCamera(call: FlutterMethodCall, result: @escaping FlutterResult) {
        for (_, cameraInstance) in cameras {
            if let videoOutput = cameraInstance.videoOutput, videoOutput.isRecording {
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
              let videoOutput = cameraInstance.videoOutput,
              let captureSession = cameraInstance.captureSession else {
            result(FlutterError(code: "INVALID_CAMERA", message: "Camera not found or not initialized", details: nil))
            return
        }
        
        // Check if recording
        guard videoOutput.isRecording else {
            result(FlutterError(code: "NOT_RECORDING", message: "No active recording to segment", details: nil))
            return
        }
        
        // 1. Stop current recording and save URL to segments
        videoOutput.stopRecording()
        if let url = cameraInstance.recordingURL {
            cameraInstance.segmentURLs.append(url)
            cameraInstance.recordingURL = nil
        }
        
        // 2. Remove current video input
        if let inputs = captureSession.inputs as? [AVCaptureDeviceInput] {
            for input in inputs {
                if input.device.hasMediaType(.video) {
                    captureSession.removeInput(input)
                }
            }
        }
        
        // 3. Switch lens position
        let newPosition: AVCaptureDevice.Position = cameraInstance.lensPosition == .back ? .front : .back
        cameraInstance.lensPosition = newPosition
        
        // 4. Add new video input with new camera
        do {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else {
                result(FlutterError(code: "NO_CAMERA", message: "Camera device not available", details: nil))
                return
            }
            
            let videoInput = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            }
            
            // 5. Start new recording segment
            let tempDir = FileManager.default.temporaryDirectory
            let recordingURL = tempDir.appendingPathComponent("recording_\(Int(Date().timeIntervalSince1970))_segment_\(cameraInstance.segmentURLs.count).mov")
            
            videoOutput.startRecording(to: recordingURL, recordingDelegate: self)
            cameraInstance.recordingURL = recordingURL
            cameras[cameraId] = cameraInstance
            
            result(nil)
        } catch {
            result(FlutterError(code: "SWITCH_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func stopRecording(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let cameraId = args["cameraId"] as? Int,
              var cameraInstance = cameras[cameraId],
              let videoOutput = cameraInstance.videoOutput else {
            result(FlutterError(code: "INVALID_CAMERA", message: "Camera not found", details: nil))
            return
        }
        
        videoOutput.stopRecording()
        if let url = cameraInstance.recordingURL {
            cameraInstance.segmentURLs.append(url)
            cameras[cameraId] = cameraInstance
            
            // Merge segments if multiple, otherwise return single segment
            if cameraInstance.segmentURLs.count == 1 {
                result(cameraInstance.segmentURLs[0].path)
            } else {
                // Run merge on background thread to avoid blocking UI
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.mergeSegments(segmentURLs: cameraInstance.segmentURLs, cameraId: cameraId, result: result)
                }
            }
        } else {
            result(FlutterError(code: "NO_RECORDING", message: "No active recording", details: nil))
        }
    }
    
    private func mergeSegments(segmentURLs: [URL], cameraId: Int, result: @escaping FlutterResult) {
        let composition = AVMutableComposition()
        var currentTime = CMTime.zero
        
        do {
            // Add all segments to composition
            for segmentURL in segmentURLs {
                let asset = AVAsset(url: segmentURL)
                
                // Add video track
                if let videoTrack = asset.tracks(withMediaType: .video).first,
                   let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                    try compositionVideoTrack.insertTimeRange(
                        CMTimeRange(start: .zero, duration: asset.duration),
                        of: videoTrack,
                        at: currentTime
                    )
                }
                
                // Add audio track
                if let audioTrack = asset.tracks(withMediaType: .audio).first,
                   let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                    try compositionAudioTrack.insertTimeRange(
                        CMTimeRange(start: .zero, duration: asset.duration),
                        of: audioTrack,
                        at: currentTime
                    )
                }
                
                currentTime = CMTimeAdd(currentTime, asset.duration)
            }
            
            // Create merged file URL
            let tempDir = FileManager.default.temporaryDirectory
            let mergedURL = tempDir.appendingPathComponent("recording_merged_\(Int(Date().timeIntervalSince1970)).mov")
            
            // Export composition
            guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
                cleanupSegmentFiles(segmentURLs: segmentURLs)
                result(FlutterError(code: "EXPORT_FAILED", message: "Failed to create export session", details: nil))
                return
            }
            
            exportSession.outputURL = mergedURL
            exportSession.outputFileType = .mov
            
            exportSession.exportAsynchronously { [weak self] in
                switch exportSession.status {
                case .completed:
                    // Cleanup segment files after successful merge
                    self?.cleanupSegmentFiles(segmentURLs: segmentURLs)
                    
                    // Clear segments from camera instance
                    if var cameraInstance = self?.cameras[cameraId] {
                        cameraInstance.segmentURLs = []
                        self?.cameras[cameraId] = cameraInstance
                    }
                    
                    result(mergedURL.path)
                    
                case .failed:
                    let error = exportSession.error?.localizedDescription ?? "Unknown error"
                    // Cleanup segment files on error
                    self?.cleanupSegmentFiles(segmentURLs: segmentURLs)
                    result(FlutterError(code: "MERGE_FAILED", message: error, details: nil))
                    
                case .cancelled:
                    // Cleanup segment files on cancellation
                    self?.cleanupSegmentFiles(segmentURLs: segmentURLs)
                    result(FlutterError(code: "MERGE_CANCELLED", message: "Merge operation cancelled", details: nil))
                    
                default:
                    break
                }
            }
        } catch {
            cleanupSegmentFiles(segmentURLs: segmentURLs)
            result(FlutterError(code: "COMPOSITION_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func cleanupSegmentFiles(segmentURLs: [URL]) {
        for url in segmentURLs {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                // Log but don't throw - cleanup failure shouldn't break the flow
                print("Failed to cleanup segment file at \(url): \(error.localizedDescription)")
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
    }
    
    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let pixelBuffer = latestPixelBuffer else {
            return nil
        }
        return Unmanaged.passRetained(pixelBuffer)
    }
}

extension WaffleCameraPlugin: AVCaptureFileOutputRecordingDelegate {
    public func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
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
