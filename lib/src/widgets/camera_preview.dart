import 'package:flutter/material.dart';

import '../controller/camera_controller.dart';
import '../models/camera_state.dart';

/// A widget that displays the preview for a [CameraController].
class CameraPreview extends StatelessWidget {
  final CameraController controller;

  /// Portrait preview aspect ratio used by the native camera feed.
  static const double _previewAspectRatio = 9 / 16;

  const CameraPreview({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CameraState>(
      valueListenable: controller,
      builder: (context, value, _) {
        final textureId = controller.textureId;
        if (textureId != null &&
            value is! CameraUninitializedState &&
            value is! CameraDisposedState) {
          return _buildTexture(textureId);
        }

        final error = _errorForState(value);
        if (error != null) {
          return Container(
            color: Colors.black,
            child: Center(
              child: Text(
                error.toString(),
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return Container(
          color: Colors.black,
          child: const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        );
      },
    );
  }

  Widget _buildTexture(int textureId) {
    return ColoredBox(
      color: Colors.black,
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: 9,
          height: 16,
          child: AspectRatio(
            aspectRatio: _previewAspectRatio,
            child: Texture(
              textureId: textureId,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ),
    );
  }

  Object? _errorForState(CameraState state) {
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
