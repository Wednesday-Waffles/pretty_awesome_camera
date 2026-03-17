import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:waffle_camera_plugin/waffle_camera_plugin.dart';
import 'package:waffle_camera_plugin/waffle_camera_plugin_platform_interface.dart';
import 'package:gallery_saver/gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Waffle Camera Plugin Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const CameraDemoScreen(),
    );
  }
}

class CameraDemoScreen extends StatefulWidget {
  const CameraDemoScreen({super.key});

  @override
  State<CameraDemoScreen> createState() => _CameraDemoScreenState();
}

class _CameraDemoScreenState extends State<CameraDemoScreen> {
  final _platform = WaffleCameraPluginPlatform.instance;

  List<CameraDescription> _cameras = [];
  int? _selectedCameraIndex;
  int? _cameraId;
  int? _textureId;

  bool _isInitializing = false;
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isSwitching = false;
  String? _errorMessage;
  String? _recordedFilePath;
  String? _selectedPath;

  RecordingState _recordingState = RecordingState.idle;
  StreamSubscription<RecordingState>? _recordingStateSubscription;
  StreamSubscription<dynamic>? _textureChangedSubscription;

  @override
  void initState() {
    super.initState();
    _loadCameras();
  }

  @override
  void dispose() {
    _recordingStateSubscription?.cancel();
    _textureChangedSubscription?.cancel();
    _disposeCamera();
    super.dispose();
  }

  Future<void> _loadCameras() async {
    try {
      final cameras = await _platform.getAvailableCameras();
      setState(() {
        _cameras = cameras;
        if (cameras.isNotEmpty) {
          _selectedCameraIndex = 0;
        }
      });
    } on PlatformException catch (e) {
      setState(() {
        _errorMessage = 'Failed to get cameras: ${e.message}';
      });
    }
  }

  Future<void> _initializeCamera() async {
    if (_selectedCameraIndex == null || _cameras.isEmpty) return;

    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    try {
      // Dispose existing camera first
      await _disposeCamera();

      final camera = _cameras[_selectedCameraIndex!];

      // Create camera
      final cameraId = await _platform.createCamera(
        camera,
        ResolutionPreset.high,
      );
      _cameraId = cameraId;

      // Initialize camera — returns the texture ID
      final textureId = await _platform.initializeCamera(cameraId);

      // Subscribe to recording state changes
      _recordingStateSubscription = _platform
          .onRecordingStateChanged(cameraId)
          .listen((state) {
            setState(() {
              _recordingState = state;
            });
          });

      // Subscribe to texture changes (camera switch creates new texture)
      final textureChannel = EventChannel(
        'waffle_camera_plugin/texture_changed_$cameraId',
      );
      _textureChangedSubscription = textureChannel
          .receiveBroadcastStream()
          .listen((dynamic newTextureId) {
            if (newTextureId is int) {
              setState(() {
                _textureId = newTextureId;
              });
            }
          });

      setState(() {
        _textureId = textureId as int?;
        _isInitializing = false;
        _recordedFilePath = null;
      });
    } on PlatformException catch (e) {
      setState(() {
        _errorMessage = 'Failed to initialize camera: ${e.message}';
        _isInitializing = false;
      });
    }
  }

  Future<void> _disposeCamera() async {
    if (_cameraId != null) {
      await _recordingStateSubscription?.cancel();
      _recordingStateSubscription = null;

      try {
        await _platform.disposeCamera(_cameraId!);
      } catch (e) {
        // Ignore dispose errors
      }

      setState(() {
        _cameraId = null;
        _textureId = null;
        _isRecording = false;
        _isPaused = false;
        _recordingState = RecordingState.idle;
      });
    }
  }

  Future<void> _startRecording() async {
    if (_cameraId == null) return;

    try {
      await _platform.startRecording(_cameraId!);
      setState(() {
        _isRecording = true;
        _isPaused = false;
        _recordedFilePath = null;
      });
    } on PlatformException catch (e) {
      setState(() {
        _errorMessage = 'Failed to start recording: ${e.message}';
      });
    }
  }

  Future<void> _pauseRecording() async {
    if (_cameraId == null) return;

    try {
      await _platform.pauseRecording(_cameraId!);
      setState(() {
        _isPaused = true;
      });
    } on PlatformException catch (e) {
      setState(() {
        _errorMessage = 'Failed to pause recording: ${e.message}';
      });
    }
  }

  Future<void> _resumeRecording() async {
    if (_cameraId == null) return;

    try {
      await _platform.resumeRecording(_cameraId!);
      setState(() {
        _isPaused = false;
      });
    } on PlatformException catch (e) {
      setState(() {
        _errorMessage = 'Failed to resume recording: ${e.message}';
      });
    }
  }

  Future<void> _stopRecording() async {
    if (_cameraId == null) return;

    try {
      final filePath = await _platform.stopRecording(_cameraId!);
      setState(() {
        _isRecording = false;
        _isPaused = false;
        _recordedFilePath = filePath;
      });
    } on PlatformException catch (e) {
      setState(() {
        _errorMessage = 'Failed to stop recording: ${e.message}';
      });
    }
  }

  Future<void> _saveToGallery() async {
    if (_recordedFilePath == null) return;

    try {
      PermissionStatus status;

      if (Platform.isIOS) {
        // Check current status first
        status = await Permission.photos.status;

        // If not determined yet, request it
        if (status.isDenied || status.isRestricted) {
          status = await Permission.photos.request();
        }
      } else {
        status = await Permission.storage.status;
        if (status.isDenied) {
          status = await Permission.storage.request();
        }
      }

      if (status.isGranted || status.isLimited) {
        final success = await GallerySaver.saveVideo(_recordedFilePath!);
        if (success == true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Video saved to gallery')),
            );
          }
        } else {
          setState(() {
            _errorMessage = 'Failed to save video to gallery';
          });
        }
      } else if (status.isDenied) {
        setState(() {
          _errorMessage =
              'Permission denied. Please allow access to save videos.';
        });
      } else if (status.isPermanentlyDenied) {
        setState(() {
          _errorMessage =
              'Permission permanently denied. Please enable in Settings > Privacy & Security > Photos';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error saving to gallery: $e';
      });
    }
  }

  void _switchCamera() {
    if (_cameras.length < 2) return;

    setState(() {
      _selectedCameraIndex = (_selectedCameraIndex! + 1) % _cameras.length;
    });

    _initializeCamera();
  }

  Future<void> _switchCameraAndContinueRecording() async {
    if (_cameras.length < 2 || _cameraId == null) return;

    // Stop current recording
    String? firstPartPath;
    if (_isRecording) {
      firstPartPath = await _platform.stopRecording(_cameraId!);
    }

    // Dispose current camera
    await _disposeCamera();

    // Switch to next camera
    setState(() {
      _selectedCameraIndex = (_selectedCameraIndex! + 1) % _cameras.length;
    });

    // Initialize new camera
    await _initializeCamera();

    // Start new recording
    if (_cameraId != null) {
      await _platform.startRecording(_cameraId!);
      setState(() {
        _isRecording = true;
        _isPaused = false;
        _recordedFilePath = firstPartPath;
      });
    }
  }

  Future<void> _switchCameraDuringRecording() async {
    if (_cameras.length < 2 || _cameraId == null || !_isRecording) return;

    setState(() {
      _isSwitching = true;
    });

    try {
      developer.log('Camera switch started for camera ID: $_cameraId');
      print('🎥 Camera switch started for camera ID: $_cameraId');

      // Switch to next camera
      setState(() {
        _selectedCameraIndex = (_selectedCameraIndex! + 1) % _cameras.length;
      });

      // Call platform method to switch camera during recording
      await _platform.switchCamera(_cameraId!);

      // Determine which path was selected
      bool canSwitch = await _platform.canSwitchCamera(_cameraId!);
      _selectedPath = canSwitch ? 'iosOptimizedMultiCam' : 'fallback';

      developer.log('Camera switch completed. Selected path: $_selectedPath');
      print('✅ Camera switch completed. Selected path: $_selectedPath');
    } on PlatformException catch (e) {
      developer.log('Camera switch failed: ${e.message}', error: e);
      print('❌ Camera switch failed: ${e.message}');

      setState(() {
        _errorMessage = 'Failed to switch camera: ${e.message}';
      });
    } finally {
      setState(() {
        _isSwitching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Waffle Camera Plugin Demo'),
        actions: [
          if (_cameras.length > 1)
            IconButton(
              icon: const Icon(Icons.switch_camera),
              onPressed: _cameraId == null ? null : _switchCamera,
              tooltip: 'Switch Camera',
            ),
        ],
      ),
      body: Column(
        children: [
          // Error message
          if (_errorMessage != null)
            Container(
              width: double.infinity,
              color: Colors.red.shade100,
              padding: const EdgeInsets.all(16),
              child: Text(
                _errorMessage!,
                style: TextStyle(color: Colors.red.shade900),
              ),
            ),

          // Camera preview
          Expanded(child: _buildCameraPreview()),

          // Camera info
          if (_selectedCameraIndex != null && _cameras.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Camera: ${_cameras[_selectedCameraIndex!].name}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),

          // Recording state
          if (_isRecording)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isPaused ? Icons.pause_circle : Icons.fiber_manual_record,
                    color: _isPaused ? Colors.orange : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isPaused ? 'PAUSED' : 'RECORDING',
                    style: TextStyle(
                      color: _isPaused ? Colors.orange : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

          // Recorded file info
          if (_recordedFilePath != null)
            Container(
              width: double.infinity,
              color: Colors.green.shade100,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Video saved to:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _recordedFilePath!,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _saveToGallery,
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Save to Gallery'),
                  ),
                ],
              ),
            ),

          // Control buttons
          _buildControlButtons(),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_isInitializing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Initializing camera...'),
          ],
        ),
      );
    }

    if (_textureId != null) {
      return CameraPreview(cameraId: _textureId!, aspectRatio: 16 / 9);
    }

    if (_cameras.isEmpty) {
      return const Center(child: Text('No cameras available'));
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.camera_alt, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'Camera not initialized',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _initializeCamera,
            icon: const Icon(Icons.camera),
            label: const Text('Initialize Camera'),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButtons() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // Switch camera button during recording (shown only when recording)
          if (_isRecording && _cameras.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: _isSwitching
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.blue, width: 2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.blue,
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Switching camera...',
                            style: TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: _switchCameraDuringRecording,
                      icon: const Icon(Icons.switch_camera),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      label: const Text('Switch Camera'),
                    ),
            ),

          // Main control buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Initialize/Dispose button
              if (_textureId == null)
                ElevatedButton.icon(
                  onPressed: _isInitializing ? null : _initializeCamera,
                  icon: const Icon(Icons.camera),
                  label: const Text('Start Camera'),
                )
              else
                ElevatedButton.icon(
                  onPressed: _isRecording ? null : _disposeCamera,
                  icon: const Icon(Icons.close),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  label: const Text('Stop Camera'),
                ),

              // Recording controls
              if (_textureId != null) ...[
                if (!_isRecording)
                  ElevatedButton.icon(
                    onPressed: _startRecording,
                    icon: const Icon(Icons.fiber_manual_record),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    label: const Text('Record'),
                  )
                else ...[
                  // Pause/Resume button
                  ElevatedButton.icon(
                    onPressed: _isPaused ? _resumeRecording : _pauseRecording,
                    icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
                    label: Text(_isPaused ? 'Resume' : 'Pause'),
                  ),

                  // Stop button
                  ElevatedButton.icon(
                    onPressed: _stopRecording,
                    icon: const Icon(Icons.stop),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    label: const Text('Stop'),
                  ),
                ],
              ],
            ],
          ),
        ],
      ),
    );
  }
}
