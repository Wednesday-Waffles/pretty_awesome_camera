import 'camera_preview_size.dart';

final class CameraInitializationResult {
  const CameraInitializationResult({
    required this.textureId,
    this.previewSize,
  });

  final int textureId;
  final CameraPreviewSize? previewSize;

  Map<String, Object?> toJson() {
    return {
      'textureId': textureId,
      'previewSize': previewSize?.toJson(),
    };
  }

  factory CameraInitializationResult.fromJson(Map<dynamic, dynamic> json) {
    final previewSizeJson = json['previewSize'];
    CameraPreviewSize? previewSize;
    if (previewSizeJson is Map) {
      final previewSizeMap = Map<dynamic, dynamic>.from(previewSizeJson);
      final width = previewSizeMap['width'];
      final height = previewSizeMap['height'];
      if (width is int && height is int) {
        previewSize = CameraPreviewSize(width: width, height: height);
      }
    }

    return CameraInitializationResult(
      textureId: json['textureId'] as int,
      previewSize: previewSize,
    );
  }
}
