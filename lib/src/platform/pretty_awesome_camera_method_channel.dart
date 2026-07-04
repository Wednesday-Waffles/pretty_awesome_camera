import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/audio_device_changed_event.dart';
import '../models/camera_config.dart';
import '../models/camera_description.dart';
import '../models/camera_exception.dart';
import '../models/camera_initialization_result.dart';
import '../models/recording_state.dart';
import 'switching_capability.dart';
import 'pretty_awesome_camera_platform_interface.dart';

/// An implementation of [PrettyAwesomeCameraPlatform] that uses method channels.
class MethodChannelPrettyAwesomeCamera extends PrettyAwesomeCameraPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('pretty_awesome_camera');

  /// Event channel for recording state changes.
  late EventChannel _recordingStateEventChannel;

  /// The switching capability detector instance.
  late final SwitchingCapability _switchingCapability = SwitchingCapability();

  CameraException _cameraExceptionFromPlatformException(
    PlatformException exception,
    String fallbackMessage,
  ) {
    final nativeDetails = exception.details;
    return CameraException(
      code: exception.code,
      message: exception.message ?? fallbackMessage,
      details: nativeDetails is Map
          ? nativeDetails.map(
              (key, value) => MapEntry(key.toString(), value as Object?),
            )
          : null,
    );
  }

  CameraException _cameraExceptionFromMissingPluginException(
    MissingPluginException exception,
    String methodName,
  ) {
    return CameraException(
      code: 'NOT_IMPLEMENTED',
      message:
          exception.message ??
          'Platform method $methodName has not been implemented.',
    );
  }

  Future<T?> _invokeCameraMethod<T>(
    String methodName, {
    Object? arguments,
    required String fallbackMessage,
  }) async {
    try {
      return await methodChannel.invokeMethod<T>(methodName, arguments);
    } on MissingPluginException catch (e) {
      throw _cameraExceptionFromMissingPluginException(e, methodName);
    } on PlatformException catch (e) {
      throw _cameraExceptionFromPlatformException(e, fallbackMessage);
    }
  }

  @override
  Future<String?> getPlatformVersion() async {
    final version = await _invokeCameraMethod<String>(
      'getPlatformVersion',
      fallbackMessage: 'Failed to get platform version',
    );
    return version;
  }

  @override
  Future<Map<String, Object?>> getBuildInfo() async {
    final result = await _invokeCameraMethod<dynamic>(
      'getBuildInfo',
      fallbackMessage: 'Failed to get build info',
    );
    if (result == null) {
      throw CameraException(
        code: 'invalid_response',
        message: 'Platform returned null build info',
      );
    }
    return Map<dynamic, dynamic>.from(
      result as Map,
    ).map((key, value) => MapEntry(key.toString(), value as Object?));
  }

  @override
  Future<List<CameraDescription>> getAvailableCameras() async {
    final result = await _invokeCameraMethod<List<dynamic>>(
      'getAvailableCameras',
      fallbackMessage: 'Failed to get available cameras',
    );
    if (result == null) {
      return [];
    }
    return result
        .map(
          (camera) => CameraDescription.fromJson(
            Map<dynamic, dynamic>.from(camera as Map),
          ),
        )
        .toList();
  }

  @override
  Future<int> createCamera(
    CameraDescription camera,
    CameraConfig config,
  ) async {
    final cameraId = await _invokeCameraMethod<int>(
      'createCamera',
      arguments: {
        'camera': camera.toJson(),
        'preset': config.resolutionPreset.name,
        if (config.videoBitrate != null) 'videoBitrate': config.videoBitrate,
      },
      fallbackMessage: 'Failed to create camera',
    );
    if (cameraId == null) {
      throw CameraException(
        code: 'invalid_response',
        message: 'Platform returned null camera ID',
      );
    }
    return cameraId;
  }

  @override
  Future<CameraInitializationResult> initializeCamera(int cameraId) async {
    final result = await _invokeCameraMethod<dynamic>(
      'initializeCamera',
      arguments: {'cameraId': cameraId},
      fallbackMessage: 'Failed to initialize camera',
    );
    if (result == null) {
      throw CameraException(
        code: 'invalid_response',
        message: 'Platform returned null initialization result',
      );
    }
    if (result is int) {
      return CameraInitializationResult(textureId: result);
    }
    return CameraInitializationResult.fromJson(
      Map<dynamic, dynamic>.from(result as Map),
    );
  }

  @override
  Future<void> startRecording(int cameraId) async {
    await _invokeCameraMethod<void>(
      'startRecording',
      arguments: {'cameraId': cameraId},
      fallbackMessage: 'Failed to start recording',
    );
  }

  @override
  Future<String?> stopRecording(int cameraId) async {
    final filePath = await _invokeCameraMethod<String>(
      'stopRecording',
      arguments: {'cameraId': cameraId},
      fallbackMessage: 'Failed to stop recording',
    );
    return filePath;
  }

  @override
  Future<void> pauseRecording(int cameraId) async {
    await _invokeCameraMethod<void>(
      'pauseRecording',
      arguments: {'cameraId': cameraId},
      fallbackMessage: 'Failed to pause recording',
    );
  }

  @override
  Future<void> resumeRecording(int cameraId) async {
    await _invokeCameraMethod<void>(
      'resumeRecording',
      arguments: {'cameraId': cameraId},
      fallbackMessage: 'Failed to resume recording',
    );
  }

  @override
  Future<double> setZoom(int cameraId, double zoomFactor) async {
    final appliedZoom = await _invokeCameraMethod<double>(
      'setZoom',
      arguments: {'cameraId': cameraId, 'zoom': zoomFactor},
      fallbackMessage: 'Failed to set zoom',
    );
    if (appliedZoom == null) {
      throw CameraException(
        code: 'invalid_response',
        message: 'Platform returned null zoom factor',
      );
    }
    return appliedZoom;
  }

  @override
  Future<void> disposeCamera(int cameraId) async {
    await _invokeCameraMethod<void>(
      'disposeCamera',
      arguments: {'cameraId': cameraId},
      fallbackMessage: 'Failed to dispose camera',
    );
  }

  @override
  Stream<RecordingState> onRecordingStateChanged(int cameraId) {
    _recordingStateEventChannel = EventChannel(
      'pretty_awesome_camera/recording_state_$cameraId',
    );
    return _recordingStateEventChannel
        .receiveBroadcastStream()
        .map((state) {
          return RecordingState.values.firstWhere(
            (e) => e.name == state as String,
          );
        })
        .handleError((error) {
          throw CameraException(
            code: 'stream_error',
            message: error.toString(),
          );
        });
  }

  @override
  Stream<AudioDeviceChangedEvent> onAudioDeviceChanged(int cameraId) {
    final audioDeviceChannel = EventChannel(
      'pretty_awesome_camera/audio_device_$cameraId',
    );
    return audioDeviceChannel
        .receiveBroadcastStream()
        .map((event) => AudioDeviceChangedEvent.fromMap(event as Map))
        .handleError((error) {
          throw CameraException(
            code: 'stream_error',
            message: error.toString(),
          );
        });
  }

  @override
  Future<bool> canSwitchCamera(int cameraId) async {
    final canSwitch = await _invokeCameraMethod<bool>(
      'canSwitchCamera',
      arguments: {'cameraId': cameraId},
      fallbackMessage: 'Failed to check if camera can switch',
    );
    return canSwitch ?? false;
  }

  @override
  Future<CameraInitializationResult> switchCamera(int cameraId) async {
    final result = await _invokeCameraMethod<dynamic>(
      'switchCamera',
      arguments: {'cameraId': cameraId},
      fallbackMessage: 'Failed to switch camera',
    );
    if (result == null) {
      throw CameraException(
        code: 'invalid_response',
        message: 'Platform returned null camera switch result',
      );
    }
    if (result is int) {
      return CameraInitializationResult(textureId: result);
    }
    return CameraInitializationResult.fromJson(
      Map<dynamic, dynamic>.from(result as Map),
    );
  }

  @override
  Future<bool> get canSwitchCurrentCamera async {
    final canSwitch = await _invokeCameraMethod<bool>(
      'canSwitchCurrentCamera',
      fallbackMessage: 'Failed to check if current camera can switch',
    );
    return canSwitch ?? false;
  }

  @override
  Future<bool> isMultiCamSupported() async {
    final supported = await _invokeCameraMethod<bool>(
      'isMultiCamSupported',
      fallbackMessage: 'Failed to detect MultiCam support',
    );
    return supported ?? false;
  }

  @override
  Future<String> getSwitchingPath() async {
    try {
      final path = await _switchingCapability.detectedPath;
      return path.name;
    } catch (e) {
      if (e is CameraException) {
        rethrow;
      }
      throw CameraException(
        code: 'path_detection_failed',
        message: 'Failed to detect switching path: $e',
      );
    }
  }
}
