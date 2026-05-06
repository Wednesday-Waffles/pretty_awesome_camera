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
    