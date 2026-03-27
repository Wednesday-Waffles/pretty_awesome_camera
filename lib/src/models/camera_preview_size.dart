import 'dart:math' as math;

final class CameraPreviewSize {
  const CameraPreviewSize({
    required this.width,
    required this.height,
  });

  final int width;
  final int height;

  double get aspectRatio => width / height;

  double get portraitAspectRatio {
    final shortestSide = math.min(width, height);
    final longestSide = math.max(width, height);
    return shortestSide / longestSide;
  }

  Map<String, Object?> toJson() {
    return {
      'width': width,
      'height': height,
    };
  }

  factory CameraPreviewSize.fromJson(Map<dynamic, dynamic> json) {
    return CameraPreviewSize(
      width: json['width'] as int,
      height: json['height'] as int,
    );
  }
}
