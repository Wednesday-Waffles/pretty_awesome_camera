# Video Quality Options for Camera Plugin

## TL;DR

> **Quick Summary**: Add full video quality control (quality preset enum, bitrate, frame rate, codec) to the camera plugin with auto-fallback for unsupported settings, and fix the recording state event bug.
> 
> **Deliverables**:
> - New `VideoQualityConfig` class with quality/bitrate/frameRate/codec
> - New `VideoQuality` enum (sd, hd, fullHd, ultraHd)
> - New `VideoCodec` enum (h264, hevc)
> - Updated `createCamera()` API (breaking change)
> - Android CameraX quality configuration
> - iOS AVFoundation quality configuration
> - Fixed recording state event emissions
> - Unit and integration tests
> 
> **Estimated Effort**: Medium
> **Parallel Execution**: YES - 4 waves
> **Critical Path**: Task 1 → Task 3 → Task 5 → Task 7 → Task 9

---

## Context

### Original Request
Add option for video quality in the camera plugin.

### Interview Summary
**Key Discussions**:
- Current `ResolutionPreset` enum exists but is NOT applied on native platforms
- User wants FULL control: quality preset enum, bitrate, frame rate, codec
- Quality set at camera creation with required parameters
- Auto-fallback when device doesn't support requested settings
- Fix recording state event emissions bug
- TDD approach for all new code

**Research Findings**:
- Android uses CameraX with `VideoCapture<Recorder>` - can use `QualitySelector` and `Recorder.Builder()`
- iOS uses `AVCaptureMovieFileOutput` - can set `sessionPreset` and compression properties
- Recording state events not wired up on either platform
- Existing tests in `test/waffle_camera_plugin_method_channel_test.dart`

### Metis Review
**Identified Gaps** (addressed):
- Quality as enum (sd, hd, fullHd, ultraHd): User confirmed
- Breaking API change: User approved
- Auto-fallback behavior: User confirmed
- Bitrate units in bps: User confirmed

---

## Work Objectives

### Core Objective
Implement comprehensive video quality configuration for camera recording with quality preset enum, required bitrate/frameRate, optional codec selection, and fix the recording state event bug.

### Concrete Deliverables
- `lib/src/video_quality.dart` - Quality preset enum (sd, hd, fullHd, ultraHd)
- `lib/src/video_codec.dart` - Codec enum (h264, hevc)
- `lib/src/video_quality_config.dart` - Config class
- Updated `lib/waffle_camera_plugin_platform_interface.dart`
- Updated `lib/waffle_camera_plugin_method_channel.dart`
- Updated `android/.../WaffleCameraPlugin.kt`
- Updated `ios/Classes/WaffleCameraPlugin.swift`
- Updated tests in `test/waffle_camera_plugin_method_channel_test.dart`
- Updated example app in `example/lib/main.dart`

### Definition of Done
- [ ] `flutter test` passes with new tests
- [ ] `flutter build ios` succeeds
- [ ] `flutter build apk` succeeds
- [ ] Recording with custom quality produces correct file on both platforms
- [ ] Recording state events emitted correctly (idle → recording → paused → idle)

### Must Have
- `VideoQuality` enum (sd, hd, fullHd, ultraHd)
- `VideoCodec` enum (h264, hevc)
- `VideoQualityConfig` class with required quality/bitrate/frameRate
- Quality applied on both Android and iOS
- Recording state events working
- Auto-fallback for unsupported settings

### Must NOT Have (Guardrails)
- Audio quality configuration (out of scope)
- Photo capture features
- Quality change during recording
- File format selection (MP4/MOV)
- HDR or special video modes
- Adaptive/automatic bitrate

---

## Verification Strategy (MANDATORY)

> **ZERO HUMAN INTERVENTION** — ALL verification is agent-executed. No exceptions.

### Test Decision
- **Infrastructure exists**: YES (flutter_test)
- **Automated tests**: TDD (RED-GREEN-REFACTOR)
- **Framework**: flutter_test

### QA Policy
Every task MUST include agent-executed QA scenarios.
Evidence saved to `.sisyphus/evidence/task-{N}-{scenario-slug}.{ext}`.

- **Dart unit tests**: `flutter test test/path/to/test.dart`
- **Integration tests**: `flutter test integration_test/` on device/emulator
- **Build verification**: `flutter build ios/apk`

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Foundation - Dart types):
├── Task 1: VideoQuality + VideoCodec enums + tests [quick]
└── Task 2: VideoQualityConfig class + tests [quick]

Wave 1b (Dart API - after Wave 1):
└── Task 3: Update platform interface + method channel [quick]

Wave 2 (Android implementation):
├── Task 4: Android - Fix recording state events [unspecified-high]
├── Task 5: Android - Implement quality configuration [deep]
└── Task 6: Android - Update tests and example [unspecified-high]

Wave 3 (iOS implementation):
├── Task 7: iOS - Fix recording state events [unspecified-high]
├── Task 8: iOS - Implement quality configuration [deep]
└── Task 9: iOS - Update tests and example [unspecified-high]

Wave 4 (Integration + cleanup):
├── Task 10: Update example app with quality UI [visual-engineering]
├── Task 11: Integration tests on both platforms [deep]
└── Task 12: Cleanup - remove ResolutionPreset, docs [quick]

Wave FINAL (Verification - 4 parallel):
├── Task F1: Plan compliance audit (oracle)
├── Task F2: Code quality review (unspecified-high)
├── Task F3: Integration QA (unspecified-high)
└── Task F4: Scope fidelity check (deep)
```

### Dependency Matrix

- **1, 2**: No dependencies (parallel in Wave 1)
- **3**: Depends on 1, 2 (Wave 1b)
- **4**: Depends on 3
- **5**: Depends on 4
- **6**: Depends on 5
- **7**: Depends on 3
- **8**: Depends on 7
- **9**: Depends on 8
- **10**: Depends on 6, 9
- **11**: Depends on 10
- **12**: Depends on 11
- **F1-F4**: Depends on 12

### Agent Dispatch Summary

- **Wave 1**: 3 tasks → quick, quick, quick
- **Wave 2**: 3 tasks → unspecified-high, deep, unspecified-high
- **Wave 3**: 3 tasks → unspecified-high, deep, unspecified-high
- **Wave 4**: 3 tasks → visual-engineering, deep, quick
- **FINAL**: 4 tasks → oracle, unspecified-high, unspecified-high, deep

---

## TODOs

- [ ] 1. Create VideoQuality and VideoCodec enums with tests (TDD)

  **What to do**:
  - Write failing tests for `VideoQuality` enum in `test/src/video_quality_test.dart`
  - Create `lib/src/video_quality.dart` with values: `sd` (480p), `hd` (720p), `fullHd` (1080p), `ultraHd` (4K)
  - Add `toJson()` and `fromJson()` methods for platform channel serialization
  - Add `dimensions` getter returning `(int width, int height)`
  - Write failing tests for `VideoCodec` enum in `test/src/video_codec_test.dart`
  - Create `lib/src/video_codec.dart` with `h264` and `hevc` values
  - Add `toJson()` and `fromJson()` methods
  - Ensure all tests pass

  **Must NOT do**:
  - Add additional quality levels or codecs
  - Add any quality-related logic beyond enum definition

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Simple enum creation, straightforward implementation
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Task 2)
  - **Parallel Group**: Wave 1 (with Task 2)
  - **Blocks**: Task 3
  - **Blocked By**: None

  **References**:
  - `lib/src/resolution_preset.dart` - Pattern for enum structure
  - `lib/src/camera_description.dart` - Pattern for toJson/fromJson

  **Acceptance Criteria**:
  - [ ] Test files created: `test/src/video_quality_test.dart`, `test/src/video_codec_test.dart`
  - [ ] Enum files created: `lib/src/video_quality.dart`, `lib/src/video_codec.dart`
  - [ ] `flutter test test/src/video_quality_test.dart` → PASS
  - [ ] `flutter test test/src/video_codec_test.dart` → PASS

  **QA Scenarios**:
  ```
  Scenario: VideoQuality and VideoCodec serialization works correctly
    Tool: Bash
    Steps:
      1. Run `flutter test test/src/video_quality_test.dart`
      2. Run `flutter test test/src/video_codec_test.dart`
    Expected Result: All tests pass (test toJson returns correct strings, fromJson creates correct enums)
    Evidence: .sisyphus/evidence/task-01-enum-tests.txt
  ```

  **Commit**: YES
  - Message: `feat(camera): add VideoQuality and VideoCodec enums`
  - Files: `lib/src/video_quality.dart`, `lib/src/video_codec.dart`, `test/src/video_quality_test.dart`, `test/src/video_codec_test.dart`

- [ ] 2. Create VideoQualityConfig class with tests (TDD)

  **What to do**:
  - Write failing tests for `VideoQualityConfig` in `test/src/video_quality_config_test.dart`
  - Create `lib/src/video_quality_config.dart` with:
    - Required fields: `quality` (VideoQuality), `bitrate` (int), `frameRate` (int)
    - Optional field: `codec` (VideoCodec, default h264)
    - Constructor validation (positive bitrate/frameRate)
    - `toJson()` and `fromJson()` methods
    - `copyWith()` method
    - Equality and hashCode
  - Export from `lib/waffle_camera_plugin.dart`
  - Ensure tests pass

  **Must NOT do**:
  - Add optional bitrate/frameRate (they are REQUIRED)
  - Add validation for max values (only positive check)
  - Add default values for required fields

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Data class with validation, straightforward
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Task 1)
  - **Parallel Group**: Wave 1 (with Task 1)
  - **Blocks**: Task 3
  - **Blocked By**: None

  **References**:
  - `lib/src/camera_description.dart:15-45` - Pattern for toJson/fromJson and validation
  - `lib/src/video_quality.dart` - Quality enum to reference
  - `lib/src/video_codec.dart` - Codec enum to reference

  **Acceptance Criteria**:
  - [ ] Test file created: `test/src/video_quality_config_test.dart`
  - [ ] Class file created: `lib/src/video_quality_config.dart`
  - [ ] Export added to `lib/waffle_camera_plugin.dart`
  - [ ] `flutter test test/src/video_quality_config_test.dart` → PASS

  **QA Scenarios**:
  ```
  Scenario: VideoQualityConfig validates required fields
    Tool: Bash
    Steps:
      1. Run `flutter test test/src/video_quality_config_test.dart`
    Expected Result: Tests for constructor validation pass (throws on negative/zero values)
    Evidence: .sisyphus/evidence/task-02-config-validation.txt

  Scenario: VideoQualityConfig serializes correctly
    Tool: Bash
    Steps:
      1. Run `flutter test test/src/video_quality_config_test.dart`
    Expected Result: Tests for toJson/fromJson pass
    Evidence: .sisyphus/evidence/task-02-config-serialization.txt
  ```

  **Commit**: YES
  - Message: `feat(camera): add VideoQualityConfig class`
  - Files: `lib/src/video_quality_config.dart`, `test/src/video_quality_config_test.dart`, `lib/waffle_camera_plugin.dart`

- [ ] 3. Update platform interface and method channel

  **What to do**:
  - Update `WaffleCameraPluginPlatform.createCamera()` signature to accept `VideoQualityConfig` instead of `ResolutionPreset`
  - Update `MethodChannelWaffleCameraPlugin.createCamera()` to send new payload:
    ```dart
    {
      'camera': camera.toJson(),
      'qualityConfig': qualityConfig.toJson()
    }
    ```
  - Update existing tests in `test/waffle_camera_plugin_method_channel_test.dart` to use new API
  - Remove `ResolutionPreset` parameter usage (keep enum file for now, remove in Task 12)

  **Must NOT do**:
  - Remove `ResolutionPreset` enum file yet (done in Task 12)
  - Change any native platform code (this is Dart-only)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: API signature update, test modifications
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 1b (sequential after Wave 1)
  - **Blocks**: Task 4, Task 7
  - **Blocked By**: Task 1, Task 2

  **References**:
  - `lib/waffle_camera_plugin_platform_interface.dart:42-44` - Current createCamera signature
  - `lib/waffle_camera_plugin_method_channel.dart:52-74` - Current implementation
  - `test/waffle_camera_plugin_method_channel_test.dart:98-170` - Tests to update

  **Acceptance Criteria**:
  - [ ] Platform interface updated
  - [ ] Method channel updated with new payload structure
  - [ ] All tests in `test/waffle_camera_plugin_method_channel_test.dart` pass
  - [ ] `flutter test` → PASS

  **QA Scenarios**:
  ```
  Scenario: Method channel sends correct payload
    Tool: Bash
    Steps:
      1. Run `flutter test test/waffle_camera_plugin_method_channel_test.dart`
    Expected Result: createCamera tests pass with new VideoQualityConfig payload
    Evidence: .sisyphus/evidence/task-03-method-channel.txt
  ```

  **Commit**: YES
  - Message: `feat(camera): update createCamera to use VideoQualityConfig`
  - Files: `lib/waffle_camera_plugin_platform_interface.dart`, `lib/waffle_camera_plugin_method_channel.dart`, `test/waffle_camera_plugin_method_channel_test.dart`
  - Pre-commit: `flutter test`

- [ ] 4. Android - Fix recording state event emissions

  **What to do**:
  - Store `eventSink` reference when event channel is listened to
  - Emit `recording` state in `startRecording()` after recording starts
  - Emit `paused` state in `pauseRecording()` after pause succeeds
  - Emit `recording` state in `resumeRecording()` after resume succeeds
  - Emit `idle` state in `stopRecording()` after recording stops
  - Create event channel in `initializeCamera()` (currently missing)

  **Must NOT do**:
  - Change quality configuration (separate task)
  - Modify iOS code

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Platform-specific implementation requiring Android/CameraX knowledge
  - **Skills**: [`android-mcp`]

  **Parallelization**:
  - **Can Run In Parallel**: NO (depends on Task 3)
  - **Parallel Group**: Wave 2
  - **Blocks**: Task 5
  - **Blocked By**: Task 3

  **References**:
  - `android/.../WaffleCameraPlugin.kt:34-35` - Event channel/sink declarations (unused)
  - `android/.../WaffleCameraPlugin.kt:211-239` - startRecording/stopRecording (need event emissions)

  **Acceptance Criteria**:
  - [ ] Event channel created per camera in `initializeCamera()`
  - [ ] Events emitted in correct sequence
  - [ ] `./gradlew test` passes

  **QA Scenarios**:
  ```
  Scenario: Android recording state events emitted correctly
    Tool: Bash (requires Android emulator)
    Preconditions: Android emulator running with camera support
    Steps:
      1. cd example && flutter test integration_test/camera_android_test.dart
      2. Verify test output shows event sequence assertions passing
    Expected Result: Tests pass, event sequence (idle → recording → paused → idle) verified
    Evidence: .sisyphus/evidence/task-04-android-events.txt

  Scenario: Android build succeeds with event changes
    Tool: Bash
    Steps:
      1. cd android && ./gradlew build
    Expected Result: Build exits with code 0, no compilation errors
    Evidence: .sisyphus/evidence/task-04-android-build.txt
  ```

  **Commit**: YES
  - Message: `fix(android): emit recording state events`
  - Files: `android/src/main/kotlin/.../WaffleCameraPlugin.kt`

- [ ] 5. Android - Implement video quality configuration

  **What to do**:
  - Store `VideoQualityConfig` in `CameraInstance` data class when `createCamera()` is called
  - Create quality mapping from `VideoQuality` enum to CameraX `Quality`:
    - `sd` → Quality.SD (or lowest available)
    - `hd` → Quality.HD (720p)
    - `fullHd` → Quality.FHD (1080p)
    - `ultraHd` → Quality.UHD (4K)
  - Configure `Recorder.Builder()` with bitrate
  - Use `QualitySelector.from(quality)` with fallback strategy
  - Set frame rate via `setTargetFrameRate()`
  - Handle codec selection (H.264 default, HEVC if requested)
  - Fix `stopRecording()` to return actual file path (current bug)

  **Must NOT do**:
  - Add audio configuration
  - Modify iOS code
  - Throw error when quality unavailable (use fallback)

  **Recommended Agent Profile**:
  - **Category**: `deep`
  - **Skills**: [`android-mcp`, `flutter-expert`]

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Task 7)
  - **Parallel Group**: Wave 2
  - **Blocks**: Task 6
  - **Blocked By**: Task 4

  **Acceptance Criteria**:
  - [ ] Quality config stored per camera instance
  - [ ] VideoQuality enum mapped to CameraX Quality
  - [ ] Bitrate, frame rate, codec applied

  **QA Scenarios**:
  ```
  Scenario: Android recording uses specified quality preset
    Tool: Bash (requires Android emulator)
    Preconditions: Android emulator running with camera support
    Steps:
      1. Run example app with VideoQualityConfig(quality: VideoQuality.fullHd, bitrate: 8000000, frameRate: 30)
      2. Start and stop recording
      3. Verify file exists at returned path
    Expected Result: Video file created, path returned successfully
    Evidence: .sisyphus/evidence/task-05-android-quality.txt

  Scenario: Android quality fallback works
    Tool: Bash (requires Android emulator)
    Steps:
      1. Request ultraHd quality on device that may not support it
      2. Verify recording still succeeds (fallback applied)
    Expected Result: Recording succeeds with fallback quality
    Evidence: .sisyphus/evidence/task-05-android-fallback.txt
  ```

  **Commit**: YES
  - Message: `feat(android): implement video quality configuration`
  - Files: `android/src/main/kotlin/.../WaffleCameraPlugin.kt`

- [ ] 6. Android - Update example and verify

  **What to do**:
  - Update `example/lib/main.dart` to use new `VideoQualityConfig` API
  - Add quality selector UI (dropdown for presets)
  - Verify example builds: `flutter build apk --debug`

  **Must NOT do**:
  - Add complex UI (simple dropdown is enough)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: [`flutter-expert`, `android-mcp`]

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Task 9)
  - **Parallel Group**: Wave 2
  - **Blocks**: Task 10
  - **Blocked By**: Task 5

  **Acceptance Criteria**:
  - [ ] Example app updated with VideoQualityConfig
  - [ ] Quality selector UI functional
  - [ ] `flutter build apk --debug` succeeds

  **QA Scenarios**:
  ```
  Scenario: Example app builds for Android
    Tool: Bash
    Steps:
      1. cd example && flutter build apk --debug
    Expected Result: Build exits with code 0, APK created at example/build/app/outputs/flutter-apk/app-debug.apk
    Evidence: .sisyphus/evidence/task-06-android-build.txt

  Scenario: Example app uses VideoQualityConfig API
    Tool: Bash
    Steps:
      1. grep -n "VideoQualityConfig" example/lib/main.dart
    Expected Result: Returns at least one match showing VideoQualityConfig usage
    Evidence: .sisyphus/evidence/task-06-api-usage.txt
  ```

  **Commit**: YES
  - Message: `feat(example): update for VideoQualityConfig API`
  - Files: `example/lib/main.dart`

- [ ] 7. iOS - Fix recording state event emissions

  **What to do**:
  - Store reference to `RecordingStateStreamHandler` in `CameraInstance`
  - Wire up `AVCaptureFileOutputRecordingDelegate` callbacks:
    - `fileOutputDidStartRecording` → emit `recording`
    - `fileOutputDidFinishRecording` → emit `idle`
  - Update `pauseRecording()` and `resumeRecording()` to emit states

  **Must NOT do**:
  - Change quality configuration (separate task)
  - Modify Android code

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Task 4)
  - **Parallel Group**: Wave 3
  - **Blocks**: Task 8
  - **Blocked By**: Task 3

  **Acceptance Criteria**:
  - [ ] Delegate methods emit correct states
  - [ ] Pause/resume emit state changes
  - [ ] iOS build succeeds

  **QA Scenarios**:
  ```
  Scenario: iOS recording state events emitted correctly
    Tool: Bash (requires iOS simulator)
    Preconditions: iOS simulator running with camera support
    Steps:
      1. cd example && flutter test integration_test/camera_ios_test.dart
      2. Verify test output shows event sequence assertions passing
    Expected Result: Tests pass, event sequence (idle → recording → paused → idle) verified
    Evidence: .sisyphus/evidence/task-07-ios-events.txt

  Scenario: iOS build succeeds with event changes
    Tool: Bash
    Steps:
      1. cd example && flutter build ios --no-codesign
    Expected Result: Build exits with code 0, no compilation errors
    Evidence: .sisyphus/evidence/task-07-ios-build.txt
  ```

  **Commit**: YES
  - Message: `fix(ios): emit recording state events`
  - Files: `ios/Classes/WaffleCameraPlugin.swift`

- [ ] 8. iOS - Implement video quality configuration

  **What to do**:
  - Store `VideoQualityConfig` in `CameraInstance` when `createCamera()` is called
  - Create quality mapping from `VideoQuality` enum to `AVCaptureSession.Preset`:
    - `sd` → .vga640x480
    - `hd` → .hd1280x720
    - `fullHd` → .hd1920x1080
    - `ultraHd` → .hd4K3840x2160
  - Set `AVCaptureSession.sessionPreset` based on quality
  - Configure compression settings via `AVVideoCompressionPropertiesKey`:
    - `AVVideoAverageBitRateKey` for bitrate
    - `AVVideoExpectedSourceFrameRateKey` for frame rate
  - Set codec via `AVVideoCodecType` (`.h264` or `.hevc`)

  **Must NOT do**:
  - Add audio configuration
  - Modify Android code
  - Throw error when quality unavailable (use fallback)

  **Recommended Agent Profile**:
  - **Category**: `deep`
  - **Skills**: [`flutter-expert`]

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Task 5)
  - **Parallel Group**: Wave 3
  - **Blocks**: Task 9
  - **Blocked By**: Task 7

  **Acceptance Criteria**:
  - [ ] Quality config stored per camera instance
  - [ ] Session preset set based on quality
  - [ ] Compression properties set for bitrate/frame rate
  - [ ] Codec selection works
  - [ ] iOS build succeeds

  **QA Scenarios**:
  ```
  Scenario: iOS recording uses specified quality preset
    Tool: Bash (requires iOS simulator)
    Preconditions: iOS simulator running
    Steps:
      1. Run example app with VideoQualityConfig(quality: VideoQuality.fullHd, bitrate: 8000000, frameRate: 30)
      2. Start and stop recording
      3. Verify file exists at returned path
    Expected Result: Video file created, path returned successfully
    Evidence: .sisyphus/evidence/task-08-ios-quality.txt

  Scenario: iOS quality fallback works
    Tool: Bash (requires iOS simulator)
    Steps:
      1. Request ultraHd quality on device that may not support it
      2. Verify recording still succeeds (fallback applied)
    Expected Result: Recording succeeds with fallback quality
    Evidence: .sisyphus/evidence/task-08-ios-fallback.txt
  ```

  **Commit**: YES
  - Message: `feat(ios): implement video quality configuration`
  - Files: `ios/Classes/WaffleCameraPlugin.swift`

- [ ] 9. iOS - Verify example runs

  **What to do**:
  - Verify example builds: `flutter build ios --no-codesign`
  - Verify example runs on iOS simulator
  - Test quality configuration changes

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: [`flutter-expert`]

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Task 6)
  - **Parallel Group**: Wave 3
  - **Blocks**: Task 10
  - **Blocked By**: Task 8

  **Acceptance Criteria**:
  - [ ] `flutter build ios --no-codesign` succeeds
  - [ ] App runs on iOS simulator

  **QA Scenarios**:
  ```
  Scenario: iOS example app builds
    Tool: Bash
    Steps:
      1. cd example && flutter build ios --no-codesign
    Expected Result: Build exits with code 0
    Evidence: .sisyphus/evidence/task-09-ios-build.txt
  ```

  **Commit**: NO (groups with Task 8)

- [ ] 10. Update example app with quality selector UI

  **What to do**:
  - Add quality preset dropdown: SD, HD, Full HD, Ultra HD
  - Add bitrate input (optional advanced)
  - Add frame rate input (30/60)
  - Add codec selector (H.264, HEVC)
  - Display current recording quality info

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
  - **Skills**: [`flutter-expert`]

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 4
  - **Blocks**: Task 11
  - **Blocked By**: Task 6, Task 9

  **Acceptance Criteria**:
  - [ ] Quality preset dropdown works
  - [ ] Frame rate selector works
  - [ ] Codec selector works
  - [ ] UI displays current settings

  **QA Scenarios**:
  ```
  Scenario: Quality selector UI functional
    Tool: Bash (requires emulator)
    Preconditions: Android emulator OR iOS simulator running
    Steps:
      1. Launch example app
      2. Select "Full HD (1080p)" preset
      3. Verify dropdown shows selected preset
    Expected Result: UI reflects selection, VideoQualityConfig updated
    Evidence: .sisyphus/evidence/task-10-quality-ui.txt

  Scenario: Quality changes applied to recording
    Tool: Bash (requires emulator)
    Steps:
      1. Select HD (720p) preset
      2. Start recording
      3. Stop recording
      4. Verify recording succeeds
    Expected Result: Recording completes with selected quality
    Evidence: .sisyphus/evidence/task-10-quality-recording.txt
  ```

  **Commit**: YES
  - Message: `feat(example): add quality selector UI`
  - Files: `example/lib/main.dart`

- [ ] 11. Integration tests for video quality

  **What to do**:
  - Create/update integration tests in `example/integration_test/`
  - Test: Recording with different quality configurations
  - Test: Recording state event sequence
  - Test: Quality fallback when unsupported
  - Run tests on both Android and iOS

  **Recommended Agent Profile**:
  - **Category**: `deep`
  - **Skills**: [`flutter-expert`, `android-mcp`]

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 4
  - **Blocks**: Task 12
  - **Blocked By**: Task 10

  **Acceptance Criteria**:
  - [ ] Integration tests created/updated
  - [ ] Tests pass on Android emulator
  - [ ] Tests pass on iOS simulator

  **QA Scenarios**:
  ```
  Scenario: Android integration tests pass
    Tool: Bash (requires Android emulator)
    Preconditions: Android emulator running
    Steps:
      1. cd example && flutter test integration_test/camera_android_test.dart
    Expected Result: All tests exit with code 0
    Evidence: .sisyphus/evidence/task-11-android-integration.txt

  Scenario: iOS integration tests pass
    Tool: Bash (requires iOS simulator)
    Preconditions: iOS simulator running
    Steps:
      1. cd example && flutter test integration_test/camera_ios_test.dart
    Expected Result: All tests exit with code 0
    Evidence: .sisyphus/evidence/task-11-ios-integration.txt
  ```

  **Commit**: YES
  - Message: `test: add integration tests for video quality`
  - Files: `example/integration_test/*.dart`

- [ ] 12. Cleanup - Remove deprecated code and update docs

  **What to do**:
  - Remove `lib/src/resolution_preset.dart` (replaced by VideoQuality)
  - Update README.md with new API usage examples
  - Add API documentation to `VideoQuality`, `VideoCodec`, `VideoQualityConfig`
  - Update CHANGELOG.md with breaking changes note

  **Must NOT do**:
  - Keep ResolutionPreset for backward compatibility (breaking change approved)

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 4
  - **Blocks**: Final Wave
  - **Blocked By**: Task 11

  **Acceptance Criteria**:
  - [ ] `resolution_preset.dart` deleted
  - [ ] README updated with new API examples
  - [ ] All tests still pass

  **QA Scenarios**:
  ```
  Scenario: ResolutionPreset removed
    Tool: Bash
    Steps:
      1. test -f lib/src/resolution_preset.dart && echo "FILE EXISTS" || echo "FILE DELETED"
    Expected Result: Output is "FILE DELETED"
    Evidence: .sisyphus/evidence/task-12-file-deleted.txt

  Scenario: All tests still pass after cleanup
    Tool: Bash
    Steps:
      1. flutter test
    Expected Result: All tests pass, exit code 0
    Evidence: .sisyphus/evidence/task-12-tests-pass.txt

  Scenario: README contains VideoQualityConfig example
    Tool: Bash
    Steps:
      1. grep -n "VideoQualityConfig" README.md
    Expected Result: Returns at least one match
    Evidence: .sisyphus/evidence/task-12-readme-updated.txt
  ```

  **Commit**: YES
  - Message: `refactor: remove ResolutionPreset, update docs`
  - Files: Multiple (deleted file, README.md, CHANGELOG.md)
  - Pre-commit: `flutter test`

---

## Final Verification Wave (MANDATORY — after ALL implementation tasks)

- [ ] F1. **Plan Compliance Audit** — `oracle`
  Read the plan end-to-end. For each "Must Have": verify implementation exists. For each "Must NOT Have": search codebase for forbidden patterns. Check evidence files exist in .sisyphus/evidence/.
  Output: `Must Have [N/N] | Must NOT Have [N/N] | VERDICT: APPROVE/REJECT`

- [ ] F2. **Code Quality Review** — `unspecified-high`
  Run `flutter analyze` + `flutter test`. Review all changed files for: `dynamic`, `as any`, empty catches, unused imports. Check AI slop: excessive comments, over-abstraction.
  Output: `Analyze [PASS/FAIL] | Tests [N pass/N fail] | Files [N clean/N issues] | VERDICT`

- [ ] F3. **Integration QA** — `unspecified-high`
  Run `flutter test integration_test/` on both Android emulator and iOS simulator. Verify recording with quality config produces files with correct properties.
  Output: `Android [PASS/FAIL] | iOS [PASS/FAIL] | VERDICT`

- [ ] F4. **Scope Fidelity Check** — `deep`
  For each task: read "What to do", read actual diff. Verify 1:1 — everything in spec was built, nothing beyond spec. Check "Must NOT do" compliance.
  Output: `Tasks [N/N compliant] | Contamination [CLEAN/N issues] | VERDICT`

---

## Commit Strategy

- **Wave 1**: `feat(camera): add VideoQualityConfig and VideoCodec types`
- **Wave 2**: `feat(android): implement video quality configuration and fix events`
- **Wave 3**: `feat(ios): implement video quality configuration and fix events`
- **Wave 4**: `feat(example): add quality selector UI and integration tests`

---

## Success Criteria

### Verification Commands
```bash
# Unit tests
flutter test

# Build verification
flutter build ios --no-codesign
flutter build apk --debug

# Integration tests (requires device/emulator)
flutter test integration_test/
```

### Final Checklist
- [ ] All "Must Have" present
- [ ] All "Must NOT Have" absent
- [ ] All tests pass
- [ ] Recording state events work correctly
- [ ] Quality configuration applied on both platforms
