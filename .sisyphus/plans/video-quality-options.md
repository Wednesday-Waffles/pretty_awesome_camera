# Video Quality Options for Camera Plugin

## TL;DR

> **Quick Summary**: Add full video quality control (resolution, bitrate, frame rate, codec) to the camera plugin with pixel-based resolution, auto-fallback for unsupported settings, and fix the recording state event bug.
> 
> **Deliverables**:
> - New `VideoQualityConfig` class with width/height/bitrate/frameRate/codec
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
- User wants FULL control: resolution (as pixels), bitrate, frame rate, codec
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
- Resolution as pixel dimensions (not enum): User confirmed
- Breaking API change: User approved
- Auto-fallback behavior: User confirmed
- Bitrate units in bps: User confirmed

---

## Work Objectives

### Core Objective
Implement comprehensive video quality configuration for camera recording with pixel-based resolution, required bitrate/frameRate, optional codec selection, and fix the recording state event bug.

### Concrete Deliverables
- `lib/src/video_quality_config.dart` - New config class
- `lib/src/video_codec.dart` - New codec enum
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
- `VideoQualityConfig` class with required width/height/bitrate/frameRate
- `VideoCodec` enum (h264, hevc)
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
Wave 1 (Foundation - Dart types + tests, can run in parallel):
├── Task 1: VideoCodec enum + tests [quick]
├── Task 2: VideoQualityConfig class + tests [quick]
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

- **1, 2, 3**: No dependencies (foundation, parallel)
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

- [ ] 1. Create VideoCodec enum with tests (TDD)

  **What to do**:
  - Write failing tests for `VideoCodec` enum in `test/src/video_codec_test.dart`
  - Create `lib/src/video_codec.dart` with `h264` and `hevc` values
  - Add `toJson()` and `fromJson()` methods for platform channel serialization
  - Ensure tests pass

  **Must NOT do**:
  - Add additional codecs beyond h264/hevc
  - Add any quality-related logic

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
  - [ ] Test file created: `test/src/video_codec_test.dart`
  - [ ] Enum file created: `lib/src/video_codec.dart`
  - [ ] `flutter test test/src/video_codec_test.dart` → PASS

  **QA Scenarios**:
  ```
  Scenario: VideoCodec serialization works correctly
    Tool: Bash
    Steps:
      1. Run `flutter test test/src/video_codec_test.dart`
    Expected Result: All tests pass (test toJson returns 'h264'/'hevc', fromJson creates correct enum)
    Evidence: .sisyphus/evidence/task-01-codec-test.txt
  ```

  **Commit**: YES
  - Message: `feat(camera): add VideoCodec enum`
  - Files: `lib/src/video_codec.dart`, `test/src/video_codec_test.dart`

- [ ] 2. Create VideoQualityConfig class with tests (TDD)

  **What to do**:
  - Write failing tests for `VideoQualityConfig` in `test/src/video_quality_config_test.dart`
  - Create `lib/src/video_quality_config.dart` with:
    - Required fields: `width` (int), `height` (int), `bitrate` (int), `frameRate` (int)
    - Optional field: `codec` (VideoCodec, default h264)
    - Constructor validation (positive integers)
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
  - **Can Run In Parallel**: YES (with Tasks 1, 2)
  - **Parallel Group**: Wave 1
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
    - `android-mcp`: May be useful for testing on Android emulator

  **Parallelization**:
  - **Can Run In Parallel**: NO (depends on Task 3)
  - **Parallel Group**: Wave 2
  - **Blocks**: Task 5
  - **Blocked By**: Task 3

  **References**:
  - `android/.../WaffleCameraPlugin.kt:34-35` - Event channel/sink declarations (unused)
  - `android/.../WaffleCameraPlugin.kt:211-239` - startRecording/stopRecording (need event emissions)
  - `ios/Classes/WaffleCameraPlugin.swift:328-340` - iOS RecordingStateStreamHandler pattern

  **Acceptance Criteria**:
  - [ ] Event channel created per camera in `initializeCamera()`
  - [ ] Events emitted in correct sequence
  - [ ] `./gradlew test` passes

  **QA Scenarios**:
  ```
  Scenario: Recording state events emitted correctly on Android
    Tool: Bash (Android emulator required)
    Preconditions: Android emulator running
    Steps:
      1. Run `flutter test integration_test/camera_android_test.dart`
    Expected Result: Tests verify event sequence (idle → recording → paused → idle)
    Evidence: .sisyphus/evidence/task-04-android-events.txt
  ```

  **Commit**: YES
  - Message: `fix(android): emit recording state events`
  - Files: `android/src/main/kotlin/.../WaffleCameraPlugin.kt`

- [ ] 5. Android - Implement video quality configuration

  **What to do**:
  - Store `VideoQualityConfig` in `CameraInstance` data class when `createCamera()` is called
  - In `initializeCamera()`:
    - Parse quality config from stored data
    - Configure `Recorder.Builder()` with:
      - Bitrate via `setBitRate()` or similar
      - Frame rate via `setTargetFrameRate()`
    - Select closest resolution using `QualitySelector` with fallback
  - Handle codec selection (H.264 default, HEVC if requested and available)
  - Implement auto-fallback when exact quality not available
  - Fix `stopRecording()` to return actual file path (current bug: creates new timestamp)

  **Must NOT do**:
  - Add audio configuration
  - Modify iOS code
  - Throw error when quality unavailable (use fallback)

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Complex CameraX API integration with quality mapping logic
  - **Skills**: [`android-mcp`, `flutter-expert`]
    - `android-mcp`: For testing on emulator
    - `flutter-expert`: For Flutter plugin patterns

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Task 7 after Task 4)
  - **Parallel Group**: Wave 2 (after Task 4)
  - **Blocks**: Task 6
  - **Blocked By**: Task 4

  **References**:
  - `android/.../WaffleCameraPlugin.kt:39-47` - CameraInstance data class (add qualityConfig)
  - `android/.../WaffleCameraPlugin.kt:104-119` - createCamera (store config)
  - `android/.../WaffleCameraPlugin.kt:164-168` - Recorder.Builder (add quality config)
  - CameraX docs: `QualitySelector`, `Recorder.Builder.setBitRate()`, `VideoCapture`

  **Acceptance Criteria**:
  - [ ] Quality config stored per camera instance
  - [ ] Bitrate applied to recorder
  - [ ] Frame rate applied to video capture
  - [ ] Resolution mapped to closest supported
  - [ ] Codec selection works (H.264/HEVC)
  - [ ] `./gradlew test` passes

  **QA Scenarios**:
  ```
  Scenario: Android recording uses specified quality
    Tool: Bash (Android emulator)
    Preconditions: Android emulator running
    Steps:
      1. Record video with VideoQualityConfig(width: 1920, height: 1080, bitrate: 8000000, frameRate: 30)
      2. Stop recording and get file path
      3. Verify file exists and has content
    Expected Result: Video file created with approximately correct properties
    Evidence: .sisyphus/evidence/task-05-android-quality.txt
  ```

  **Commit**: YES
  - Message: `feat(android): implement video quality configuration`
  - Files: `android/src/main/kotlin/.../WaffleCameraPlugin.kt`

- [ ] 6. Android - Update example and verify

  **What to do**:
  - Update `example/lib/main.dart` to use new `VideoQualityConfig` API
  - Add quality selector UI (dropdown for preset qualities)
  - Verify example app builds: `flutter build apk --debug`
  - Verify example runs on emulator

  **Must NOT do**:
  - Add complex UI (simple dropdown is enough)
  - Add new features beyond quality selection

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Example app update and verification
  - **Skills**: [`flutter-expert`, `android-mcp`]
    - `flutter-expert`: Flutter widget development
    - `android-mcp`: Testing on emulator

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Task 9 after respective platform tasks)
  - **Parallel Group**: Wave 2 (after Task 5)
  - **Blocks**: Task 10
  - **Blocked By**: Task 5

  **References**:
  - `example/lib/main.dart` - Current example app
  - `lib/src/video_quality_config.dart` - New API to use

  **Acceptance Criteria**:
  - [ ] Example app updated with VideoQualityConfig
  - [ ] Quality selector UI functional
  - [ ] `flutter build apk --debug` succeeds
  - [ ] App runs on Android emulator

  **QA Scenarios**:
  ```
  Scenario: Example app builds and runs on Android
    Tool: Bash
    Steps:
      1. cd example && flutter build apk --debug
      2. Verify build succeeds with exit code 0
    Expected Result: APK created successfully
    Evidence: .sisyphus/evidence/task-06-android-build.txt
  ```

  **Commit**: YES
  - Message: `feat(example): update for VideoQualityConfig API`
  - Files: `example/lib/main.dart`

- [ ] 7. iOS - Fix recording state event emissions

  **What to do**:
  - Store reference to `RecordingStateStreamHandler` in `CameraInstance`
  - Create method to emit state changes in the handler
  - Wire up `AVCaptureFileOutputRecordingDelegate` callbacks:
    - `fileOutputDidStartRecording` → emit `recording`
    - `fileOutputDidFinishRecording` → emit `idle`
  - Update `pauseRecording()` and `resumeRecording()` to emit states
  - Pass handler reference to camera instance for state updates

  **Must NOT do**:
  - Change quality configuration (separate task)
  - Modify Android code

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Platform-specific Swift/AVFoundation implementation
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Task 4 after Task 3)
  - **Parallel Group**: Wave 3
  - **Blocks**: Task 8
  - **Blocked By**: Task 3

  **References**:
  - `ios/Classes/WaffleCameraPlugin.swift:323-326` - AVCaptureFileOutputRecordingDelegate (empty)
  - `ios/Classes/WaffleCameraPlugin.swift:328-340` - RecordingStateStreamHandler
  - `ios/Classes/WaffleCameraPlugin.swift:13-20` - CameraInstance struct

  **Acceptance Criteria**:
  - [ ] Delegate methods emit correct states
  - [ ] Pause/resume emit state changes
  - [ ] iOS build succeeds

  **QA Scenarios**:
  ```
  Scenario: Recording state events emitted correctly on iOS
    Tool: Bash (iOS simulator required)
    Preconditions: iOS simulator running
    Steps:
      1. Run `flutter test integration_test/camera_ios_test.dart`
    Expected Result: Tests verify event sequence (idle → recording → paused → idle)
    Evidence: .sisyphus/evidence/task-07-ios-events.txt
  ```

  **Commit**: YES
  - Message: `fix(ios): emit recording state events`
  - Files: `ios/Classes/WaffleCameraPlugin.swift`

- [ ] 8. iOS - Implement video quality configuration

  **What to do**:
  - Store `VideoQualityConfig` in `CameraInstance` when `createCamera()` is called
  - In `initializeCamera()`:
    - Parse quality config from stored data
    - Set `AVCaptureSession.sessionPreset` based on resolution (with fallback)
    - Configure compression settings via `AVVideoCompressionPropertiesKey`:
      - `AVVideoAverageBitRateKey` for bitrate
      - `AVVideoExpectedSourceFrameRateKey` for frame rate
    - Set codec via `AVVideoCodecType` (`.h264` or `.hevc`)
  - Implement auto-fallback when session preset not available
  - Handle device format selection for exact resolution

  **Must NOT do**:
  - Add audio configuration
  - Modify Android code
  - Throw error when quality unavailable (use fallback)

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Complex AVFoundation API with compression settings
  - **Skills**: [`flutter-expert`]
    - `flutter-expert`: For Flutter plugin patterns

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Task 5 after respective event fixes)
  - **Parallel Group**: Wave 3 (after Task 7)
  - **Blocks**: Task 9
  - **Blocked By**: Task 7

  **References**:
  - `ios/Classes/WaffleCameraPlugin.swift:13-20` - CameraInstance (add qualityConfig)
  - `ios/Classes/WaffleCameraPlugin.swift:83-102` - createCamera (store config)
  - `ios/Classes/WaffleCameraPlugin.swift:104-177` - initializeCamera (apply quality)
  - AVFoundation docs: `AVCaptureSession.sessionPreset`, `AVVideoCompressionPropertiesKey`

  **Acceptance Criteria**:
  - [ ] Quality config stored per camera instance
  - [ ] Session preset set based on resolution
  - [ ] Compression properties set for bitrate/frame rate
  - [ ] Codec selection works
  - [ ] iOS build succeeds

  **QA Scenarios**:
  ```
  Scenario: iOS recording uses specified quality
    Tool: Bash (iOS simulator)
    Preconditions: iOS simulator running
    Steps:
      1. Record video with VideoQualityConfig(width: 1920, height: 1080, bitrate: 8000000, frameRate: 30)
      2. Stop recording and get file path
      3. Verify file exists and has content
    Expected Result: Video file created
    Evidence: .sisyphus/evidence/task-08-ios-quality.txt
  ```

  **Commit**: YES
  - Message: `feat(ios): implement video quality configuration`
  - Files: `ios/Classes/WaffleCameraPlugin.swift`

- [ ] 9. iOS - Verify example runs

  **What to do**:
  - Verify example app builds for iOS: `flutter build ios --no-codesign`
  - Verify example runs on iOS simulator
  - Test quality configuration changes in example app

  **Must NOT do**:
  - Add new UI (done in Task 6)
  - Add new features

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Build verification and testing
  - **Skills**: [`flutter-expert`]
    - `flutter-expert`: Flutter/iOS patterns

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Task 6)
  - **Parallel Group**: Wave 3 (after Task 8)
  - **Blocks**: Task 10
  - **Blocked By**: Task 8

  **References**:
  - `example/lib/main.dart` - Updated in Task 6
  - `ios/Classes/WaffleCameraPlugin.swift` - Implementation to verify

  **Acceptance Criteria**:
  - [ ] `flutter build ios --no-codesign` succeeds
  - [ ] App runs on iOS simulator
  - [ ] Quality selection works

  **QA Scenarios**:
  ```
  Scenario: Example app builds for iOS
    Tool: Bash
    Steps:
      1. cd example && flutter build ios --no-codesign
      2. Verify build succeeds with exit code 0
    Expected Result: iOS build created successfully
    Evidence: .sisyphus/evidence/task-09-ios-build.txt
  ```

  **Commit**: NO (groups with Task 8)

- [ ] 10. Update example app with quality selector UI

  **What to do**:
  - Add quality preset dropdown in example app (already started in Task 6)
  - Presets: 720p@5Mbps/30fps, 1080p@8Mbps/30fps, 1080p@12Mbps/60fps, 4K@20Mbps/30fps
  - Add custom quality input option (width, height, bitrate, frame rate)
  - Add codec selector (H.264, HEVC)
  - Display current recording quality info

  **Must NOT do**:
  - Over-engineer the UI (keep it simple)
  - Add features beyond quality selection

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
    - Reason: UI/UX for quality selector
  - **Skills**: [`flutter-expert`]
    - `flutter-expert`: Flutter widget development

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 4
  - **Blocks**: Task 11
  - **Blocked By**: Task 6, Task 9

  **References**:
  - `example/lib/main.dart` - Current example
  - `lib/src/video_quality_config.dart` - API to use
  - `lib/src/video_codec.dart` - Codec enum

  **Acceptance Criteria**:
  - [ ] Quality preset dropdown works
  - [ ] Custom quality inputs work
  - [ ] Codec selector works
  - [ ] UI displays current settings

  **QA Scenarios**:
  ```
  Scenario: Quality selector UI functions correctly
    Tool: Bash (emulator)
    Steps:
      1. Launch example app on emulator
      2. Select 1080p preset
      3. Start recording
      4. Verify quality settings are applied
    Expected Result: Recording starts with selected quality
    Evidence: .sisyphus/evidence/task-10-quality-ui.txt
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
  - Test: Codec selection
  - Run tests on both Android and iOS

  **Must NOT do**:
  - Add unit tests (already done in earlier tasks)
  - Skip any platform

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Integration testing requiring emulator/simulator
  - **Skills**: [`flutter-expert`, `android-mcp`]
    - `flutter-expert`: Flutter testing
    - `android-mcp`: Android emulator testing

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 4
  - **Blocks**: Task 12
  - **Blocked By**: Task 10

  **References**:
  - `example/integration_test/plugin_integration_test.dart` - Existing integration tests
  - `example/integration_test/camera_android_test.dart` - Android tests
  - `example/integration_test/camera_ios_test.dart` - iOS tests

  **Acceptance Criteria**:
  - [ ] Integration tests updated
  - [ ] Tests pass on Android emulator
  - [ ] Tests pass on iOS simulator
  - [ ] `flutter test integration_test/` passes

  **QA Scenarios**:
  ```
  Scenario: Integration tests pass on Android
    Tool: Bash
    Preconditions: Android emulator running
    Steps:
      1. cd example && flutter test integration_test/
    Expected Result: All tests pass
    Evidence: .sisyphus/evidence/task-11-android-integration.txt

  Scenario: Integration tests pass on iOS
    Tool: Bash
    Preconditions: iOS simulator running
    Steps:
      1. cd example && flutter test integration_test/
    Expected Result: All tests pass
    Evidence: .sisyphus/evidence/task-11-ios-integration.txt
  ```

  **Commit**: YES
  - Message: `test: add integration tests for video quality`
  - Files: `example/integration_test/*.dart`

- [ ] 12. Cleanup - Remove deprecated code and update docs

  **What to do**:
  - Remove `lib/src/resolution_preset.dart` (replaced by VideoQualityConfig)
  - Update README.md with new API usage examples
  - Add API documentation to `VideoQualityConfig` and `VideoCodec`
  - Update CHANGELOG.md with breaking changes note

  **Must NOT do**:
  - Keep ResolutionPreset for backward compatibility (breaking change approved)
  - Add new features

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Cleanup and documentation
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 4
  - **Blocks**: Final Wave
  - **Blocked By**: Task 11

  **References**:
  - `lib/src/resolution_preset.dart` - File to remove
  - `lib/src/video_quality_config.dart` - New class to document
  - `README.md` - To update

  **Acceptance Criteria**:
  - [ ] `resolution_preset.dart` deleted
  - [ ] README updated with new API examples
  - [ ] All tests still pass after cleanup

  **QA Scenarios**:
  ```
  Scenario: Cleanup doesn't break tests
    Tool: Bash
    Steps:
      1. Run `flutter test`
    Expected Result: All tests pass
    Evidence: .sisyphus/evidence/task-12-cleanup.txt
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
