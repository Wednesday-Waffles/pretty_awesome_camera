# pretty_awesome_camera

`pretty_awesome_camera` is a Flutter camera plugin focused on a controller-first API.

You can:
- preload available camera metadata when the app starts
- create a `CameraController` before opening the camera screen
- prewarm the camera during navigation
- pass that same controller into `CameraPreview`

## Install

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  pretty_awesome_camera: ^0.0.1
```

Import it with:

```dart
import 'package:pretty_awesome_camera/pretty_awesome_camera.dart';
```

## Basic Flow

The intended flow is:

1. Preload camera details once
2. Create a controller
3. Start `prewarmUp()`
4. Render `CameraPreview(controller: controller)`

## Preload Camera Details

If you want camera discovery to happen early, call:

```dart
await CameraController.preloadAvailableCameras();
```

You can do this at app startup so later controller creation can reuse cached camera metadata.

## Create A Controller

Create a controller without opening the camera immediately:

```dart
final controller = await CameraController.create(
  config: const CameraConfig(
    resolutionPreset: ResolutionPreset.high,
    lensDirection: LensDirection.front,
  ),
);
```

Notes:
- `lensDirection` in `CameraConfig` is optional
- if `lensDirection` is `null`, the controller falls back to the front camera by default
- `create()` selects the camera, but does not start camera resources yet

## Prewarm Before Opening The Screen

You can start camera initialization before the destination screen is shown:

```dart
final controller = await CameraController.create(
  config: const CameraConfig(
    resolutionPreset: ResolutionPreset.high,
    lensDirection: LensDirection.front,
  ),
);

final prewarmFuture = controller.prewarmUp();
```

This is useful while a route transition is happening.

## Use In `CameraPreview`

Pass the same controller into `CameraPreview`:

```dart
class CameraScreen extends StatelessWidget {
  const CameraScreen({
    super.key,
    required this.controller,
  });

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CameraPreview(controller: controller),
    );
  }
}
```

## Full Example

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pretty_awesome_camera/pretty_awesome_camera.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await CameraController.preloadAvailableCameras();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _openCamera(BuildContext context) async {
    final controller = await CameraController.create(
      config: const CameraConfig(
        resolutionPreset: ResolutionPreset.high,
        lensDirection: LensDirection.front,
      ),
    );

    final prewarmFuture = controller.prewarmUp();

    if (!context.mounted) {
      await controller.disposeCamera();
      controller.dispose();
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CameraScreen(
          controller: controller,
          prewarmFuture: prewarmFuture,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => _openCamera(context),
          child: const Text('Open camera'),
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
  late final CameraController _controller = widget.controller;

  @override
  void initState() {
    super.initState();
    widget.prewarmFuture.catchError((_) {});
  }

  @override
  void dispose() {
    unawaited(_controller.disposeCamera());
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          CameraPreview(controller: _controller),
          Positioned(
            bottom: 32,
            left: 24,
            right: 24,
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _controller.startRecording(),
                    child: const Text('Record'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _controller.stopRecording(),
                    child: const Text('Stop'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

## Controller APIs

Main APIs available on `CameraController`:

- `CameraController.create(...)`
- `CameraController.preloadAvailableCameras()`
- `controller.prewarmUp()`
- `controller.startRecording()`
- `controller.pauseRecording()`
- `controller.resumeRecording()`
- `controller.stopRecording()`
- `controller.switchToNextCamera()`
- `controller.reconfigure(...)`
- `controller.clearRecordedFile()`
- `controller.disposeCamera()`

## State Updates

`CameraController` is a `ValueNotifier<CameraState>`.

The controller emits concrete states such as:

- `CameraUninitializedState`
- `CameraInitializingState`
- `CameraReadyState`
- `CameraVideoRecordedState`
- `CameraRecordingState`
- `CameraPausedState`
- `CameraSwitchingState`
- `CameraStoppingRecordingState`
- `CameraDisposedState`

You should generally check the concrete state type instead of relying on a generic enum.

Example:

```dart
final state = controller.value;

if (state is CameraReadyState) {
  // ready to record
}

if (state is CameraVideoRecordedState) {
  debugPrint(state.recordedFilePath);
}
```

## Example App

The example app in [example/lib/main.dart](/Users/ketanchoyal/CascadeProjects/waffle_camera_plugin/example/lib/main.dart) demonstrates:

- startup preload
- controller creation before navigation
- prewarm during navigation
- preview rendering with `CameraPreview`
- recording controls using the same controller
