import 'camera_preview_size.dart';

final class CameraInitializationResult {
  const CameraInitializationResult({
    required this.textureId,
    this.previewSize,
    this.switchDiagnostics,
  });

  final int textureId;
  final CameraPreviewSize? previewSize;

  /// Low-cardinality native timing diagnostics for a camera switch.
  /// Null for initial camera setup and native builds that predate diagnostics.
  final Map<String, Object?>? switchDiagnostics;

  Map<String, Object?> toJson() {
    return {
      'textureId': textureId,
      'previewSize': previewSize?.toJson(),
      if (switchDiagnostics != null) 'switchDiagnostics': switchDiagnostics,
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

    final rawSwitchDiagnostics = json['switchDiagnostics'];
    final switchDiagnostics = rawSwitchDiagnostics is Map
        ? Map<dynamic, dynamic>.from(
            rawSwitchDiagnostics,
          ).map((key, value) => MapEntry(key.toString(), value as Object?))
        : null;

    return CameraInitializationResult(
      textureId: json['textureId'] as int,
      previewSize: previewSize,
      switchDiagnostics: switchDiagnostics,
    );
  }
}
