import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pretty_awesome_camera/pretty_awesome_camera.dart';

import 'recording_permutation_harness.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF090909),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF5A36),
          brightness: Brightness.dark,
        ),
      ),
      home: const CameraLaunchScreen(),
    );
  }
}

class CameraLaunchScreen extends StatefulWidget {
  const CameraLaunchScreen({super.key});

  @override
  State<CameraLaunchScreen> createState() => _CameraLaunchScreenState();
}

class _CameraLaunchScreenState extends State<CameraLaunchScreen> {
  bool _isPrimingCache = true;
  bool _isOpeningCamera = false;
  String? _message;
  List<CameraDescription> _cachedCameras = const [];

  @override
  void initState() {
    super.initState();
    _primeCameraCache();
  }

  Future<void> _primeCameraCache() async {
    setState(() {
      _isPrimingCache = true;
      _message = null;
    });

    try {
      final cameras = await CameraController.preloadAvailableCameras();
      if (!mounted) {
        return;
      }
      setState(() {
        _cachedCameras = cameras;
        _isPrimingCache = false;
      });
    } on CameraException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _message = error.message;
        _isPrimingCache = false;
      });
    }
  }

  Future<void> _openCamera() async {
    setState(() {
      _isOpeningCamera = true;
      _message = null;
    });

    CameraController? controller;
    try {
      controller = await CameraController.create(
        preferredLens: LensDirection.front,
        config: const CameraConfig(
          resolutionPreset: ResolutionPreset.medium,
          videoBitrate: 800000,
        ),
      );
      final prewarmFuture = controller.prewarmUp();

      if (!mounted) {
        await controller.disposeCamera();
        controller.dispose();
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CameraScreen(
            controller: controller!,
            prewarmFuture: prewarmFuture,
          ),
        ),
      );
    } on CameraException catch (error) {
      await controller?.disposeCamera();
      controller?.dispose();
      if (!mounted) {
        return;
      }
      setState(() {
        _message = error.message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningCamera = false;
        });
      }
    }
  }

  Future<void> _openDiagnostics() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const RecordingPermutationScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final frontCameraAvailable = _cachedCameras.any(
      (camera) => camera.lensDirection == LensDirection.front,
    );

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF170B07), Color(0xFF090909), Color(0xFF24120C)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                const Text(
                  'Camera prewarm demo',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'This example primes camera details on app start, creates the controller before navigation, starts prewarm during navigation, and then renders the same controller inside the preview screen.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                _InfoCard(
                  title: 'Startup cache',
                  body: _isPrimingCache
                      ? 'Loading available cameras into the controller cache...'
                      : 'Cached ${_cachedCameras.length} cameras. Front camera ${frontCameraAvailable ? "found" : "not found"}.',
                ),
                const SizedBox(height: 14),
                _InfoCard(
                  title: 'Open flow',
                  body:
                      '1. Create controller\n2. Call prewarmUp() while route transitions\n3. Pass that controller into CameraPreview',
                ),
                if (_message != null) ...[
                  const SizedBox(height: 14),
                  _InfoCard(title: 'Message', body: _message!),
                ],
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isPrimingCache || _isOpeningCamera
                        ? null
                        : _openCamera,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5A36),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                    child: _isOpeningCamera
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Create Controller And Navigate',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _isPrimingCache ? null : _openDiagnostics,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.32),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                    child: const Text(
                      'Recording Diagnostics',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RecordingPermutationScreen extends StatefulWidget {
  const RecordingPermutationScreen({super.key});

  @override
  State<RecordingPermutationScreen> createState() =>
      _RecordingPermutationScreenState();
}

class _RecordingPermutationScreenState
    extends State<RecordingPermutationScreen> {
  final RecordingPermutationHarness _harness = RecordingPermutationHarness();
  bool _isRunning = false;
  String? _message;
  List<RecordingPermutationResult> _results = const [];

  Future<void> _runAll() {
    return _runScenarios(RecordingPermutationScenario.values);
  }

  Future<void> _runOne(RecordingPermutationScenario scenario) {
    return _runScenarios([scenario]);
  }

  Future<void> _runScenarios(
    List<RecordingPermutationScenario> scenarios,
  ) async {
    final hasPermissions = await _ensurePermissions();
    if (!hasPermissions) {
      setState(() {
        _message = 'Camera and microphone permissions are required.';
      });
      return;
    }

    setState(() {
      _isRunning = true;
      _message = null;
    });

    try {
      final results = await _harness.runAll(scenarios: scenarios);
      if (!mounted) {
        return;
      }
      setState(() {
        _results = [...results, ..._results];
        _message = 'Completed ${results.length} scenario(s).';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _message = 'Harness failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  Future<bool> _ensurePermissions() async {
    final statuses = await [Permission.camera, Permission.microphone].request();
    return statuses.values.every((status) => status.isGranted);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF120F1A), Color(0xFF090909), Color(0xFF152118)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Recording diagnostics',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    _GlassIconButton(
                      icon: CupertinoIcons.back,
                      onTap: () async {
                        if (mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _InfoCard(
                  title: 'Harness output',
                  body:
                      'Each scenario writes a video plus a .pretty_camera_harness.json sidecar containing the expected pause-adjusted duration for ffprobe validation.',
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  _InfoCard(title: 'Status', body: _message!),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _isRunning ? null : _runAll,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5A36),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: _isRunning
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Run All Scenarios'),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: RecordingPermutationScenario.values.map((scenario) {
                    return ActionChip(
                      label: Text(scenario.id),
                      onPressed: _isRunning ? null : () => _runOne(scenario),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      return _PermutationResultCard(result: _results[index]);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PermutationResultCard extends StatelessWidget {
  const _PermutationResultCard({required this.result});

  final RecordingPermutationResult result;

  @override
  Widget build(BuildContext context) {
    final status = result.isSkipped
        ? 'skipped'
        : result.isSuccess
        ? 'success'
        : 'failed';
    final color = result.isSkipped
        ? Colors.amber
        : result.isSuccess
        ? Colors.greenAccent
        : Colors.redAccent;
    final detail = result.skippedReason ?? result.error ?? result.videoPath;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      result.scenario.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(status, style: TextStyle(color: color)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'expected=${result.expectedDuration.inMilliseconds}ms paused=${result.pausedDuration.inMilliseconds}ms',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              if (detail != null) ...[
                const SizedBox(height: 6),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
              if (result.metadataPath != null) ...[
                const SizedBox(height: 6),
                Text(
                  result.metadataPath!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    required this.controller,
    required this.prewarmFuture,
  });

  final CameraController controller;
  final Future<void> prewarmFuture;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  CameraConfig _config = const CameraConfig(
    resolutionPreset: ResolutionPreset.medium,
    videoBitrate: 800000,
  );
  String? _message;
  Future<String>? _switchingPathFuture;

  // Recording timer
  final Stopwatch _recordingStopwatch = Stopwatch();
  Timer? _timerUpdateTicker;

  StreamSubscription<AudioDeviceChangedEvent>? _audioDeviceSubscription;
  AudioDeviceChangedEvent? _currentAudioDevice;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _config = _controller.config;
    _switchingPathFuture = _controller.getSwitchingPath();
    _controller.addListener(_handleControllerChanged);
    widget.prewarmFuture.catchError((Object error) {
      if (error is CameraException && mounted) {
        _showMessage(error.message);
      }
    });
    _audioDeviceSubscription = _controller.onAudioDeviceChanged.listen((event) {
      if (mounted) {
        setState(() {
          _currentAudioDevice = event;
        });
      }
    });
  }

  @override
  void dispose() {
    _timerUpdateTicker?.cancel();
    _audioDeviceSubscription?.cancel();
    _controller.removeListener(_handleControllerChanged);
    unawaited(_controller.disposeCamera());
    _controller.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) {
      return;
    }

    final error = _errorForState(_controller.value);
    if (error != null && error.message != _message) {
      _showMessage(error.message);
    }

    // Manage recording timer based on state
    final value = _controller.value;
    if (value is CameraRecordingState) {
      _startRecordingTimer();
    } else if (value is CameraPausedState) {
      _pauseRecordingTimer();
    } else if (value is CameraReadyState ||
        value is CameraVideoRecordedState ||
        value is CameraStoppingRecordingState) {
      _stopRecordingTimer();
    }

    setState(() {});
  }

  void _startRecordingTimer() {
    if (!_recordingStopwatch.isRunning) {
      _recordingStopwatch.start();
      _timerUpdateTicker?.cancel();
      _timerUpdateTicker = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => setState(() {}),
      );
    }
  }

  void _pauseRecordingTimer() {
    if (_recordingStopwatch.isRunning) {
      _recordingStopwatch.stop();
      _timerUpdateTicker?.cancel();
    }
  }

  void _stopRecordingTimer() {
    _recordingStopwatch.stop();
    _recordingStopwatch.reset();
    _timerUpdateTicker?.cancel();
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    setState(() {
      _message = message;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _applyPreset(ResolutionPreset preset) async {
    final nextConfig = _config.copyWith(resolutionPreset: preset);
    setState(() {
      _config = nextConfig;
    });

    try {
      await _controller.reconfigure(config: nextConfig);
    } on CameraException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _switchCamera() async {
    try {
      await _controller.switchToNextCamera();
    } on CameraException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _startRecording() async {
    try {
      await _controller.startRecording();
    } on CameraException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _pauseRecording() async {
    try {
      await _controller.pauseRecording();
    } on CameraException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _resumeRecording() async {
    try {
      await _controller.resumeRecording();
    } on CameraException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _stopRecording() async {
    try {
      await _controller.stopRecording();
    } on CameraException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _saveToGallery(String filePath) async {
    try {
      PermissionStatus status;

      if (Platform.isIOS) {
        status = await Permission.photos.status;
        if (status.isDenied || status.isRestricted) {
          status = await Permission.photos.request();
        }
      } else if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        status = androidInfo.version.sdkInt >= 33
            ? await Permission.photos.request()
            : await Permission.storage.request();
      } else {
        status = await Permission.storage.request();
      }

      if (!mounted) {
        return;
      }

      if (status.isGranted || status.isLimited) {
        await Gal.putVideo(filePath);
        _showMessage('Saved to gallery.');
      } else {
        _showMessage('Permission denied while saving video.');
      }
    } catch (error) {
      _showMessage('Failed to save video: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    final isBusy = switch (value) {
      CameraInitializingState() ||
      CameraStoppingRecordingState() ||
      CameraSwitchingState() => true,
      _ => false,
    };

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(controller: _controller),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.58),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.18),
                  Colors.black.withValues(alpha: 0.78),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _CameraStatusCard(value: value)),
                      const SizedBox(width: 12),
                      _GlassIconButton(
                        icon: CupertinoIcons.back,
                        onTap: () async {
                          if (mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                    ],
                  ),
                  if (_currentAudioDevice != null) ...[
                    const SizedBox(height: 12),
                    _AudioDeviceCard(device: _currentAudioDevice),
                  ],
                  // Recording timer
                  if (value is CameraRecordingState ||
                      value is CameraPausedState) ...[
                    const SizedBox(height: 16),
                    _RecordingTimerDisplay(
                      stopwatch: _recordingStopwatch,
                      isPaused: value is CameraPausedState,
                    ),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    _InfoCard(title: 'Message', body: _message!),
                  ],
                  const Spacer(),
                  _InfoCard(
                    title: 'Warmup flow',
                    body:
                        'This controller was created before navigation and prewarmed while this route was opening.',
                  ),
                  const SizedBox(height: 14),
                  _CameraSettingsCard(
                    currentPreset: _config.resolutionPreset,
                    switchingPathFuture: _switchingPathFuture,
                    isLocked: switch (value) {
                      CameraRecordingState() ||
                      CameraPausedState() ||
                      CameraInitializingState() => true,
                      _ => false,
                    },
                    onPresetChanged: _applyPreset,
                  ),
                  const SizedBox(height: 16),
                  _CameraControls(
                    controller: _controller,
                    onSwitchCamera: _switchCamera,
                    onStartRecording: _startRecording,
                    onPauseRecording: _pauseRecording,
                    onResumeRecording: _resumeRecording,
                    onStopRecording: _stopRecording,
                    onSaveToGallery: _saveToGallery,
                  ),
                ],
              ),
            ),
          ),
          if (isBusy)
            const ColoredBox(
              color: Colors.black38,
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  CameraException? _errorForState(CameraState state) {
    return switch (state) {
      CameraUninitializedState() => state.error,
      CameraInitializingState() => state.error,
      CameraReadyState() => state.error,
      CameraVideoRecordedState() => state.error,
      CameraStartingRecordingState() => state.error,
      CameraRecordingState() => state.error,
      CameraPausedState() => state.error,
      CameraSwitchingState() => state.error,
      CameraStoppingRecordingState() => state.error,
      CameraDisposedState() => state.error,
    };
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.74),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CameraStatusCard extends StatelessWidget {
  const _CameraStatusCard({required this.value});

  final CameraState value;

  @override
  Widget build(BuildContext context) {
    final cameraName = switch (value) {
      CameraUninitializedState(:final description) ||
      CameraInitializingState(:final description) ||
      CameraDisposedState(
        :final description,
      ) => description?.lensDirection.name.toUpperCase() ?? '--',
      CameraReadyState(:final description) ||
      CameraVideoRecordedState(:final description) ||
      CameraStartingRecordingState(:final description) ||
      CameraRecordingState(:final description) ||
      CameraPausedState(:final description) ||
      CameraSwitchingState(:final description) ||
      CameraStoppingRecordingState(
        :final description,
      ) => description?.lensDirection.name.toUpperCase() ?? '--',
    };

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _statusColor(value),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$cameraName camera',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'State: ${value.name}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(CameraState value) {
    return switch (value) {
      CameraRecordingState() => const Color(0xFFFF5533),
      CameraPausedState() => Colors.amber,
      CameraReadyState() || CameraVideoRecordedState() => Colors.greenAccent,
      CameraInitializingState() ||
      CameraStartingRecordingState() ||
      CameraSwitchingState() ||
      CameraStoppingRecordingState() => Colors.lightBlueAccent,
      CameraDisposedState() || CameraUninitializedState() => Colors.white54,
    };
  }
}

class _CameraSettingsCard extends StatelessWidget {
  const _CameraSettingsCard({
    required this.currentPreset,
    required this.switchingPathFuture,
    required this.isLocked,
    required this.onPresetChanged,
  });

  final ResolutionPreset currentPreset;
  final Future<String>? switchingPathFuture;
  final bool isLocked;
  final ValueChanged<ResolutionPreset> onPresetChanged;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Resolution',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (switchingPathFuture != null)
                FutureBuilder<String>(
                  future: switchingPathFuture,
                  builder: (context, snapshot) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: Text(
                        snapshot.data ?? 'loading...',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    );
                  },
                ),
              DropdownButtonHideUnderline(
                child: DropdownButton<ResolutionPreset>(
                  value: currentPreset,
                  dropdownColor: const Color(0xFF171717),
                  items: ResolutionPreset.values
                      .map(
                        (preset) => DropdownMenuItem(
                          value: preset,
                          child: Text(_presetLabel(preset)),
                        ),
                      )
                      .toList(),
                  onChanged: isLocked
                      ? null
                      : (preset) {
                          if (preset != null) {
                            onPresetChanged(preset);
                          }
                        },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _presetLabel(ResolutionPreset preset) {
    return switch (preset) {
      ResolutionPreset.low => 'Low',
      ResolutionPreset.medium => 'Medium',
      ResolutionPreset.high => 'High',
      ResolutionPreset.veryHigh => 'Very High',
      ResolutionPreset.max => 'Max',
    };
  }
}

class _CameraControls extends StatelessWidget {
  const _CameraControls({
    required this.controller,
    required this.onSwitchCamera,
    required this.onStartRecording,
    required this.onPauseRecording,
    required this.onResumeRecording,
    required this.onStopRecording,
    required this.onSaveToGallery,
  });

  final CameraController controller;
  final Future<void> Function() onSwitchCamera;
  final Future<void> Function() onStartRecording;
  final Future<void> Function() onPauseRecording;
  final Future<void> Function() onResumeRecording;
  final Future<void> Function() onStopRecording;
  final Future<void> Function(String filePath) onSaveToGallery;

  @override
  Widget build(BuildContext context) {
    final value = controller.value;

    if (value case CameraVideoRecordedState(:final recordedFilePath)) {
      return Row(
        children: [
          Expanded(
            child: _GlassActionButton(
              icon: CupertinoIcons.refresh,
              label: 'Retake',
              onTap: () async {
                controller.clearRecordedFile();
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _GlassActionButton(
              icon: CupertinoIcons.square_arrow_down,
              label: 'Save',
              onTap: () => onSaveToGallery(recordedFilePath),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: _GlassActionButton(
            icon: CupertinoIcons.switch_camera,
            label: 'Switch',
            onTap: controller.hasMultipleCameras ? onSwitchCamera : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _GlassActionButton(
            icon: CupertinoIcons.circle,
            label: 'Record',
            onTap: switch (value) {
              CameraReadyState() ||
              CameraVideoRecordedState() => onStartRecording,
              _ => null,
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _GlassActionButton(
            icon: value is CameraPausedState
                ? Icons.play_arrow_rounded
                : Icons.pause_rounded,
            label: value is CameraPausedState ? 'Resume' : 'Pause',
            onTap: switch (value) {
              CameraRecordingState() => onPauseRecording,
              CameraPausedState() => onResumeRecording,
              _ => null,
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _GlassActionButton(
            icon: Icons.stop_rounded,
            label: 'Stop',
            onTap: switch (value) {
              CameraRecordingState() ||
              CameraPausedState() ||
              CameraSwitchingState() => onStopRecording,
              _ => null,
            },
          ),
        ),
      ],
    );
  }
}

class _GlassActionButton extends StatelessWidget {
  const _GlassActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final FutureOr<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: GestureDetector(
        onTap: onTap == null ? null : () => onTap!.call(),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 22),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Icon(icon, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _RecordingTimerDisplay extends StatelessWidget {
  const _RecordingTimerDisplay({
    required this.stopwatch,
    required this.isPaused,
  });

  final Stopwatch stopwatch;
  final bool isPaused;

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final centiseconds = (duration.inMilliseconds.remainder(1000) / 10).floor();

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}.'
        '${centiseconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = stopwatch.elapsed;
    final formattedTime = _formatDuration(elapsed);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: isPaused
                ? Colors.amber.withValues(alpha: 0.2)
                : const Color(0xFFFF5533).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isPaused
                  ? Colors.amber.withValues(alpha: 0.4)
                  : const Color(0xFFFF5533).withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isPaused ? Colors.amber : const Color(0xFFFF5533),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                formattedTime,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              if (isPaused) ...[
                const SizedBox(width: 10),
                Text(
                  'PAUSED',
                  style: TextStyle(
                    color: Colors.amber.shade300,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AudioDeviceCard extends StatelessWidget {
  const _AudioDeviceCard({required this.device});

  final AudioDeviceChangedEvent? device;

  @override
  Widget build(BuildContext context) {
    if (device == null) {
      return const SizedBox.shrink();
    }

    final deviceName = device!.deviceName;
    final isBluetooth = device!.isBluetooth;
    final portType = device!.portType;

    IconData iconData = CupertinoIcons.mic_fill;
    if (isBluetooth) {
      iconData = CupertinoIcons.bluetooth;
    } else if (portType.toLowerCase().contains('headset') ||
        portType.toLowerCase().contains('headphone')) {
      iconData = Icons.headphones_rounded;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isBluetooth
                      ? Colors.blue.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  iconData,
                  color: isBluetooth ? Colors.blueAccent : Colors.white70,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'ACTIVE MICROPHONE',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      deviceName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
