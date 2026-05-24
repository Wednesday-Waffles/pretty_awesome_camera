/// Represents an event emitted when the active audio input device (microphone) changes.
class AudioDeviceChangedEvent {
  /// The user-friendly name of the active audio input device (e.g., "Apple AirPods", "iPhone Microphone").
  final String deviceName;

  /// The raw iOS port type representation of the active input device (e.g., "MicrophoneBuiltIn", "BluetoothHFP").
  final String portType;

  /// Whether the active audio input device is connected via Bluetooth.
  final bool isBluetooth;

  /// Creates a new [AudioDeviceChangedEvent] instance.
  const AudioDeviceChangedEvent({
    required this.deviceName,
    required this.portType,
    required this.isBluetooth,
  });

  /// Creates a new [AudioDeviceChangedEvent] instance from a map.
  factory AudioDeviceChangedEvent.fromMap(Map<dynamic, dynamic> map) {
    return AudioDeviceChangedEvent(
      deviceName: map['deviceName'] as String? ?? 'iPhone Microphone',
      portType: map['portType'] as String? ?? 'MicrophoneBuiltIn',
      isBluetooth: map['isBluetooth'] as bool? ?? false,
    );
  }

  /// Converts this event to a map.
  Map<String, dynamic> toMap() {
    return {
      'deviceName': deviceName,
      'portType': portType,
      'isBluetooth': isBluetooth,
    };
  }

  @override
  String toString() {
    return 'AudioDeviceChangedEvent(deviceName: $deviceName, portType: $portType, isBluetooth: $isBluetooth)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AudioDeviceChangedEvent &&
        other.deviceName == deviceName &&
        other.portType == portType &&
        other.isBluetooth == isBluetooth;
  }

  @override
  int get hashCode => Object.hash(deviceName, portType, isBluetooth);
}
