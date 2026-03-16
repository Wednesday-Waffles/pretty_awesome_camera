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

## Open Questions (to clarify with user)

1. **Scope of video quality options?**
   - Just resolution (use existing ResolutionPreset)?
   - Add bitrate control?
   - Add frame rate control?
   - Add codec selection (H.264, H.265/HEVC)?

2. **API Design preference?**
   - Simple: Use existing `ResolutionPreset` enum (just implement it)
   - Advanced: Add separate `VideoQualityConfig` class with all options

3. **Should quality be set at camera creation or recording start?**
   - Currently: passed to `createCamera()` but unused
   - Option A: Apply at `createCamera()` (like Flutter camera package)
   - Option B: Pass to `startRecording()` for per-recording flexibility

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
