/// Exception thrown by the camera plugin when an error occurs.
class CameraException implements Exception {
  /// Error code identifying the type of error.
  final String code;

  /// Human-readable error message.
  final String message;

  /// Creates a [CameraException] with the given [code] and [message].
  const CameraException({required this.code, required this.message});

  @override
  String toString() => 'CameraException(code: $code, message: $message)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraException &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          message == other.message;

  @override
  int get hashCode => code.hashCode ^ message.hashCode;
}
