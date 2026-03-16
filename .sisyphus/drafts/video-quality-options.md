# Draft: Video Quality Options for Camera Plugin

## Current Implementation Analysis

### Existing Code (from codebase review)
- **ResolutionPreset enum** (`lib/src/resolution_preset.dart`):
  ```dart
  enum ResolutionPreset {
    low,      // 240p
    medium,   // 480p  
    high,     // 720p
    veryHigh, // 1080p
    max,      // Maximum supported
  }
  ```

- **Video Recording Flow**:
  1. `createCamera(camera, preset)` - ResolutionPreset is passed but NOT used in native code
  2. `initializeCamera(cameraId)` - Sets up capture session
  3. `startRecording(cameraId)` - Starts recording without quality parameters

### Platform Implementations

**iOS** (`WaffleCameraPlugin.swift`):
- Uses `AVCaptureMovieFileOutput` for recording
- `AVCaptureSession` is created but NO `sessionPreset` is set
- Quality configuration is missing entirely

**Android** (`WaffleCameraPlugin.kt`):
- Uses CameraX `VideoCapture<Recorder>`
- `Recorder.Builder()` created without quality configuration
- No `QualitySelector` or bitrate settings

## Gap Identified
The `ResolutionPreset` enum exists in Dart, but it's **not actually applied** to video recording on either platform. The quality settings are missing from native implementations.

---

## User Requirements (CONFIRMED)

1. **Scope**: Full control - Resolution + Bitrate + Frame Rate + Codec
2. **API Timing**: Quality set at camera creation (`createCamera()`)
3. **Bug Fix**: Include fixing the recording state events
4. **Defaults**: bitrate and frameRate are **REQUIRED** (no defaults)

## Final API Design

```dart
/// Video quality configuration for recording.
class VideoQualityConfig {
  final int width;             // REQUIRED - e.g., 1920
  final int height;            // REQUIRED - e.g., 1080
  final int bitrate;           // REQUIRED - bits per second (e.g., 5000000 = 5 Mbps)
  final int frameRate;         // REQUIRED - e.g., 30, 60
  final VideoCodec codec;      // h264 or hevc (defaults to h264)

  const VideoQualityConfig({
    required this.width,
    required this.height,
    required this.bitrate,
    required this.frameRate,
    this.codec = VideoCodec.h264,
  });
}

enum VideoCodec {
  h264,  // Most compatible
  hevc,  // H.265 - better compression, less compatible
}
```

### API Change (BREAKING)
```dart
// Before
Future<int> createCamera(CameraDescription camera, ResolutionPreset preset)

// After (BREAKING - old signature removed)
Future<int> createCamera(
  CameraDescription camera, 
  VideoQualityConfig qualityConfig  // Required comprehensive config
)
```

### Method Channel Payload
```dart
{
  'camera': camera.toJson(),
  'qualityConfig': {
    'resolution': qualityConfig.resolution.name,  // 'low', 'medium', 'high', etc.
    'bitrate': qualityConfig.bitrate,             // e.g., 5000000
    'frameRate': qualityConfig.frameRate,         // e.g., 30
    'codec': qualityConfig.codec.name,            // 'h264' or 'hevc'
  }
}
```

## Test Strategy

**Framework**: flutter_test (existing)
**Approach**: TDD - RED→GREEN→REFACTOR for each task
**Tests to add**:
- Unit tests for `VideoQualityConfig` class
- Unit tests for `VideoCodec` enum
- Updated `createCamera` tests with new payload structure
- Integration tests for quality verification

## Summary

| Decision | Choice |
|----------|--------|
| Scope | Full (resolution + bitrate + frame rate + codec) |
| Resolution | Pixel dimensions (width/height) - NOT enum |
| API Timing | At camera creation |
| Required params | width, height, bitrate, frameRate required |
| Codec default | h264 |
| Bitrate unit | Bits per second (bps) |
| Breaking change | YES - old createCamera signature removed |
| Unsupported fallback | Auto-fallback to best available |
| Bug fix | Include event state emissions fix |
| Test strategy | TDD |

## Guardrails (from Metis review)

### MUST NOT (Scope Creep Prevention):
- Audio quality configuration
- Photo capture features
- Streaming/preview quality control
- Quality change during recording
- File format selection (MP4/MOV)
- HDR or special video modes
- Adaptive/automatic bitrate

### MUST (Required):
- Validate width/height/bitrate/frameRate are positive integers
- Auto-fallback when unsupported codec/resolution
- Emit recording state events (idle → recording → paused → idle)
- Update all existing tests

## Edge Cases to Handle
1. Device doesn't support requested resolution → Fallback to closest
2. HEVC not available → Auto-fallback to H.264
3. Frame rate not supported → Fallback to closest supported
4. Invalid params (negative, zero) → Throw ArgumentError

---

## Research Findings (from explore agent)

### Key Discovery: ResolutionPreset is NOT applied!
The `ResolutionPreset` enum exists in Dart and is passed to `createCamera()`, but:
- **Android**: Reads `preset` argument but never uses it
- **iOS**: Doesn't read the preset argument at all

### Files to Modify

**Dart Layer:**
- `lib/src/resolution_preset.dart` - The enum definition
- `lib/waffle_camera_plugin_method_channel.dart` - Method channel calls
- `lib/waffle_camera_plugin_platform_interface.dart` - Platform interface

**Android Layer:**
- `android/.../WaffleCameraPlugin.kt`:
  - `createCamera()` - Store preset in CameraInstance
  - `initializeCamera()` - Apply `QualitySelector` to `Recorder.Builder()`
  - `stopRecording()` - Bug: returns wrong file path (new timestamp instead of actual recording)

**iOS Layer:**
- `ios/Classes/WaffleCameraPlugin.swift`:
  - `createCamera()` - Read preset argument
  - `initializeCamera()` - Set `AVCaptureSession.sessionPreset` based on preset

### Platform Quality Mapping Options

**Android (CameraX):**
```kotlin
QualitySelector.from(Quality.HD)  // Maps to ResolutionPreset.high (720p)
QualitySelector.from(Quality.FHD) // Maps to ResolutionPreset.veryHigh (1080p)
QualitySelector.from(Quality.UHD) // Maps to ResolutionPreset.max (4K)
```

**iOS (AVFoundation):**
```swift
sessionPreset = .hd1280x720  // ResolutionPreset.high
sessionPreset = .hd1920x1080 // ResolutionPreset.veryHigh
sessionPreset = .hd4K3840x2160 // ResolutionPreset.max
```

### Additional Bug Found
Recording state events (`onRecordingStateChanged`) aren't properly emitted on native platforms:
- iOS: Only emits "idle" on listen, never updates
- Android: Event channels created but no emissions
