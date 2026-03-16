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
            let input = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
            
            let videoOutput = AVCaptureMovieFileOutput()
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
            }
            
            cameraInstance.captureSession = captureSession
            cameraInstance.videoOutput = videoOutput
            
            if let textureRegistry = textureRegistry {
                guard let texture = CameraPreviewTexture(session: captureSession) else {
                    result(FlutterError(code: "TEXTURE_ERROR", message: "Failed to create preview texture", details: nil))
                    return
                }
                let textureId = textureRegistry.register(texture)
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
    
    private func stopRecording(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let cameraId = args["cameraId"] as? Int,
              let cameraInstance = cameras[cameraId],
              let videoOutput = cameraInstance.videoOutput else {
            result(FlutterError(code: "INVALID_CAMERA", message: "Camera not found", details: nil))
            return
        }
        
        videoOutput.stopRecording()
        if let url = cameraInstance.recordingURL {
            result(url.path)
        } else {
            result(FlutterError(code: "NO_RECORDING", message: "No active recording", details: nil))
        }
    }
}

class CameraPreviewTexture: NSObject, FlutterTexture, AVCaptureVideoDataOutputSampleBufferDelegate {
    var latestPixelBuffer: CVPixelBuffer?
    let captureSession: AVCaptureSession
    let videoDataOutput: AVCaptureVideoDataOutput
    let videoDataOutputQueue: DispatchQueue
    
    init?(session: AVCaptureSession) {
        self.captureSession = session
        self.videoDataOutput = AVCaptureVideoDataOutput()
        self.videoDataOutputQueue = DispatchQueue(label: "VideoDataOutputQueue")
        
        super.init()
        
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
        } else {
            return nil
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            latestPixelBuffer = pixelBuffer
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
