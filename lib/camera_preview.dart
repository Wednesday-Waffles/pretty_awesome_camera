import 'package:flutter/material.dart';

/// A widget that displays a camera preview using a Flutter Texture.
///
/// The [cameraId] is the texture ID obtained from the platform when
/// initializing the camera.
///
/// Example usage:
/// ```dart
/// CameraPreview(
///   cameraId: textureId,
///   aspectRatio: 16 / 9,
/// )
/// ```
class CameraPreview extends StatelessWidget {
  /// The texture ID for the camera preview.
  final int cameraId;

  /// The aspect ratio of the camera preview.
  /// Defaults to 16:9 if not specified.
  final double? aspectRatio;

  const CameraPreview({Key? key, required this.cameraId, this.aspectRatio})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio ?? 16 / 9,
      child: Texture(textureId: cameraId),
    );
  }
}

/// A stateful widget that handles camera initialization and displays
/// a preview with loading and error states.
///
/// Example usage:
/// ```dart
/// CameraPreviewWithState(
///   cameraIdFuture: initializeCamera(),
///   aspectRatio: 16 / 9,
/// )
/// ```
class CameraPreviewWithState extends StatefulWidget {
  /// A future that resolves to the camera texture ID.
  final Future<int> cameraIdFuture;

  /// The aspect ratio of the camera preview.
  final double? aspectRatio;

  const CameraPreviewWithState({
    Key? key,
    required this.cameraIdFuture,
    this.aspectRatio,
  }) : super(key: key);

  @override
  State<CameraPreviewWithState> createState() => _CameraPreviewWithStateState();
}

class _CameraPreviewWithStateState extends State<CameraPreviewWithState> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: widget.cameraIdFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return AspectRatio(
            aspectRatio: widget.aspectRatio ?? 16 / 9,
            child: Container(
              color: Colors.black,
              child: const Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return AspectRatio(
            aspectRatio: widget.aspectRatio ?? 16 / 9,
            child: Container(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error, color: Colors.red, size: 48),
                    const SizedBox(height: 8),
                    Text(
                      'Camera error: ${snapshot.error ?? "Unknown error"}',
                      style: const TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return CameraPreview(
          cameraId: snapshot.data!,
          aspectRatio: widget.aspectRatio,
        );
      },
    );
  }
}
