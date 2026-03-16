import Flutter
import UIKit
import AVFoundation

public class WaffleCameraPlugin: NSObject, FlutterPlugin {
    private var cameras: [Int: CameraInstance] = [:]
    private var nextCameraId = 0
    private var textureRegistry: FlutterTextureRegistry?
    
    struct CameraInstance {
        let cameraId: Int
        var captureSession: AVCaptureSession?
        var videoOutput: AVCaptureMovieFileOutput?
        var textureId: Int64?
        var lensPosition: AVCaptureDevice.Position = .back
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "waffle_camera_plugin", binaryMessenger: registrar.messenger())
        let instance = WaffleCameraPlugin()
        instance.textureRegistry = registrar.textures()
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
                let textureId = textureRegistry.register(CameraPreviewTexture(session: captureSession))
                cameraInstance.textureId = textureId
            }
            
            cameras[cameraId] = cameraInstance
            
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
        cameras.removeValue(forKey: cameraId)
        
         result(nil)
    }
}

class CameraPreviewTexture: NSObject, FlutterTexture {
    let session: AVCaptureSession
    
    init(session: AVCaptureSession) {
        self.session = session
        super.init()
    }
    
    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        return nil
    }
}
