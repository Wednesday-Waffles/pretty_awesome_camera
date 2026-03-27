import 'package:flutter/material.dart';

import '../controller/camera_controller.dart';
import '../models/camera_state.dart';

/// A widget that displays the preview for a [CameraController].
class CameraPreview extends StatelessWidget {
  final CameraController controller;
  final double? aspectRatio;

  /// Portrait preview aspect ratio fallback used until native dimensions are available.
  static const double _fallbackPreviewAspectRatio = 9 / 16;

  const CameraPreview({super.key, required this.controller, this.aspectRatio});

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
    final nativeAspectRatio =
        controller.previewAspectRatio ?? _fallbackPreviewAspectRatio;
    final texture = Texture(
      textureId: textureId,
      filterQuality: FilterQuality.high,
    );

    if (aspectRatio == null) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final targetWidth = constraints.maxWidth;
          final targetHeight = constraints.maxHeight;

          if (!targetWidth.isFinite ||
              !targetHeight.isFinite ||
              targetWidth <= 0 ||
              targetHeight <= 0) {
            return ColoredBox(
              color: Colors.black,
              child: Center(
                child: AspectRatio(
                  aspectRatio: nativeAspectRatio,
                  child: texture,
                ),
              ),
            );
          }

          return ColoredBox(
            color: Colors.black,
            child: _buildCroppedTexture(
              texture: texture,
              nativeAspectRatio: nativeAspectRatio,
              targetWidth: targetWidth,
              targetHeight: targetHeight,
            ),
          );
        },
      );
    }

    return ColoredBox(
      color: Colors.transparent,
      child: Center(
        child: AspectRatio(
          aspectRatio: aspectRatio!,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return _buildCroppedTexture(
                texture: texture,
                nativeAspectRatio: nativeAspectRatio,
                targetWidth: constraints.maxWidth,
                targetHeight: constraints.maxHeight,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCroppedTexture({
    required Widget texture,
    required double nativeAspectRatio,
    required double targetWidth,
    required double targetHeight,
  }) {
    final widthFromHeight = targetHeight * nativeAspectRatio;
    final heightFromWidth = targetWidth / nativeAspectRatio;

    final childWidth = widthFromHeight >= targetWidth
        ? widthFromHeight
        : targetWidth;
    final childHeight = widthFromHeight >= targetWidth
        ? targetHeight
        : heightFromWidth;

    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.center,
        minWidth: childWidth,
        maxWidth: childWidth,
        minHeight: childHeight,
        maxHeight: childHeight,
        child: SizedBox(
          width: childWidth,
          height: childHeight,
          child: texture,
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
