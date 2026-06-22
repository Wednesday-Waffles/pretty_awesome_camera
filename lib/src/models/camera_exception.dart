import 'package:flutter/foundation.dart';

/// Exception thrown by the camera plugin when an error occurs.
class CameraException implements Exception {
  /// Error code identifying the type of error.
  final String code;

  /// Human-readable error message.
  final String message;

  /// Low-cardinality native diagnostic details.
  ///
  /// The plugin should avoid putting raw localized error strings or device
  /// names here. App clients can forward selected fields to analytics.
  final Map<String, Object?>? details;

  /// Creates a [CameraException] with the given [code] and [message].
  const CameraException({
    required this.code,
    required this.message,
    this.details,
  });

  @override
  String toString() {
    final nativeDetails = details;
    if (nativeDetails == null || nativeDetails.isEmpty) {
      return 'CameraException(code: $code, message: $message)';
    }
    return 'CameraException(code: $code, message: $message, details: $nativeDetails)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraException &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          message == other.message &&
          mapEquals(details, other.details);

  @override
  int get hashCode => Object.hash(
    code,
    message,
    details == null
        ? null
        : Object.hashAll(
            details!.entries.map(
              (entry) => Object.hash(entry.key, entry.value),
            ),
          ),
  );
}
