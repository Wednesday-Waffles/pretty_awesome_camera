# Waffle Camera Plugin - Video Recording with Pause/Resume

## TL;DR

> **Quick Summary**: Create a minimal Flutter camera plugin with video recording, pause/resume functionality, camera preview, front/back camera selection, quality settings, and automatic permission handling for Android (CameraX) and iOS 18+ (AVFoundation).
> 
> **Deliverables**:
> - Flutter plugin with platform interface and method channel implementation
> - Android native implementation using CameraX
> - iOS native implementation using AVFoundation (iOS 18+)
> - Camera preview widget (Texture-based)
> - Full API for recording, pause, resume, camera selection, quality settings
> - Unit tests and integration tests
> - Updated example app demonstrating all features
> 
> **Estimated Effort**: Large
> **Parallel Execution**: YES - 4 waves
> **Critical Path**: Platform Interface → Android/iOS Native → Integration Tests

---

## Context

### Original Request
Create a minimal Flutter camera plugin which allows to record video on Android and iOS with pause/resume feature. Also want a path where it is saved after recording is done.

### Interview Summary
**Key Discussions**:
- **Preview Widget**: Include Texture-based camera preview widget
- **Save Location**: Temporary directory (system may clean up)
- **Camera Options**: Full configuration (front/back camera selection + quality/resolution settings)
- **Permissions**: Plugin handles camera/microphone permissions internally
- **iOS Version**: iOS 18+ only (native pause/resume support)
- **Android Version**: API 21+ (CameraX minimum)
- **Test Strategy**: TDD - Tests first

**Research Findings**:
- **Android**: CameraX `Recording.pause()/resume()` available since camera-video:1.1.0+
- **iOS**: `AVCaptureMovieFileOutput.pauseRecording()` requires iOS 18.0+
- **Architecture**: Keep existing plugin_platform_interface pattern
- **Preview**: Texture widget for both platforms
- **Permissions**: CAMERA + RECORD_AUDIO on Android, NSCameraUsageDescription + NSMicrophoneUsageDescription on iOS

### Metis Review
**Identified Gaps** (addressed):
- **iOS version strategy**: Resolved - iOS 18+ only for native pause/resume
- **Android API level**: Default to API 21+ (max reach with CameraX)
- **Error handling**: Typed exceptions (CameraException with codes)
- **State synchronization**: EventChannel for real-time recording state updates
- **Camera switching**: Blocked during active recording

---

## Work Objectives

### Core Objective
Create a production-ready Flutter camera plugin with video recording capabilities including pause/resume, camera preview, and full configuration options.

### Concrete Deliverables
- `lib/waffle_camera_plugin.dart` - Updated public API with all camera methods
- `lib/waffle_camera_plugin_platform_interface.dart` - Extended platform interface
- `lib/waffle_camera_plugin_method_channel.dart` - Method channel implementation
- `lib/src/camera_exception.dart` - Typed exception classes
- `lib/src/camera_description.dart` - Camera info and settings types
- `lib/src/resolution_preset.dart` - Quality/resolution enums
- `lib/camera_preview.dart` - Texture-based preview widget
- `android/` - Complete Android native implementation with CameraX
- `ios/` - Complete iOS native implementation with AVFoundation
- `test/` - Unit tests for Dart layer
- `example/integration_test/` - Integration tests for recording flow
- `example/lib/main.dart` - Updated example app with full demo

### Definition of Done
- [ ] All unit tests pass: `flutter test`
- [ ] Android integration tests pass on device
- [ ] iOS integration tests pass on device
- [ ] Example app builds and runs on both platforms
- [ ] Recording, pause, resume, stop all work correctly
- [ ] File path returned after recording
- [ ] Permissions handled automatically

### Must Have
- Video recording with start/stop
- Pause and resume during recording
- File path returned after recording completes
- Camera preview widget
- Front/back camera selection
- Quality/resolution settings
- Automatic permission handling
- iOS 18+ support
- Android API 21+ support

### Must NOT Have (Guardrails)
- DO NOT support iOS < 18 (no fallback implementation)
- DO NOT allow camera switching during active recording
- DO NOT call CameraX APIs from background threads (Android)
- DO NOT create separate federated packages (keep single-package structure)
- DO NOT expose native-specific types in Dart API
- DO NOT over-abstract - keep minimal as requested

---

## Verification Strategy (MANDATORY)

> **ZERO HUMAN INTERVENTION** — ALL verification is agent-executed. No exceptions.

### Test Decision
- **Infrastructure exists**: YES (basic scaffold in test/)
- **Automated tests**: TDD (Tests First)
- **Framework**: flutter test (Dart), integration_test for device tests
- **TDD Flow**: Each task follows RED (failing test) → GREEN (minimal impl) → REFACTOR

### QA Policy
Every task MUST include agent-executed QA scenarios.
Evidence saved to `.sisyphus/evidence/task-{N}-{scenario-slug}.{ext}`.

- **Dart API**: Use `flutter test` — Run unit tests, assert pass/fail
- **Android**: Use `flutter build apk` + integration tests on device
- **iOS**: Use `flutter build ios` + integration tests on **physical iPhone only** (simulator does NOT support camera)
- **Integration**: Use `flutter test integration_test` on real devices

> ⚠️ **CRITICAL**: iOS Simulator does NOT support camera hardware. All iOS testing must be done on a physical iPhone running iOS 18+. This is a hard requirement - there is no workaround. Tasks 10, 11, 13 (iOS), and 15 explicitly require a physical iPhone. Plan accordingly.

### Commit Policy

> **COMMIT AFTER EVERY TASK** — No exceptions. Each task completion triggers a git commit.

- After completing each task, the executor MUST commit changes before moving to the next task
- Commit messages follow the format specified in each task
- Pre-commit hooks (like `flutter test`) must pass before committing
- Grouped tasks (marked "Commit: YES (groups with N)") are committed together in a single atomic commit
- This ensures atomic, revertible changes and clear progress tracking
- Use conventional commit format: `type(scope): description`
  - `feat`: New feature
  - `fix`: Bug fix
  - `chore`: Maintenance, dependencies, scaffolding
  - `test`: Adding or updating tests
  - `docs`: Documentation changes
  - `refactor`: Code refactoring without behavior changes

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately — Dart foundation + types):
├── Task 1: Platform scaffolding (flutter create --platforms) [quick]
├── Task 2: Dart type definitions (enums, exceptions, models) [quick]
├── Task 3: Platform interface extension [quick]
├── Task 4: Method channel implementation [quick]
└── Task 5: Unit tests for Dart layer [quick]

Wave 2 (After Wave 1 — Native implementations, MAX PARALLEL):
├── Task 6: Android native - project setup and permissions [quick]
├── Task 7: Android native - camera initialization and preview [deep]
├── Task 8: Android native - video recording with pause/resume [deep]
├── Task 9: iOS native - project setup and permissions [quick]
├── Task 10: iOS native - camera initialization and preview [deep]
└── Task 11: iOS native - video recording with pause/resume [deep]

Wave 3 (After Wave 2 — Widget and example):
├── Task 12: Camera preview widget (Texture-based) [visual-engineering]
├── Task 13: Example app with full demo UI [visual-engineering]
├── Task 14: Integration tests (Android) [unspecified-high]
└── Task 15: Integration tests (iOS) [unspecified-high]

Wave FINAL (After ALL tasks — verification, 4 parallel):
├── Task F1: Plan compliance audit (oracle)
├── Task F2: Code quality review (unspecified-high)
├── Task F3: Real device QA (unspecified-high)
└── Task F4: Scope fidelity check (deep)

Critical Path: Task 1 → Task 3-5 → Task 7-8 (Android) / Task 10-11 (iOS) → Task 14-15 → F1-F4
Parallel Speedup: ~60% faster than sequential
Max Concurrent: 6 (Wave 2)
```

### Dependency Matrix

- **1**: — — 2-5
- **2-5**: 1 — 6-11, 12-15
- **6**: 2-5 — 7-8
- **7**: 6 — 8, 14
- **8**: 7 — 14
- **9**: 2-5 — 10-11
- **10**: 9 — 11, 15
- **11**: 10 — 15
- **12**: 2-5 — 13
- **13**: 12 — 14-15
- **14**: 7-8, 13 — F1-F4
- **15**: 10-11, 13 — F1-F4
- **F1-F4**: 14-15 —

### Agent Dispatch Summary

- **1**: **1** → quick
- **2-5**: **4** → quick (all Dart foundation tasks)
- **6**: **1** → quick (Android setup)
- **7**: **1** → deep (Android camera)
- **8**: **1** → deep (Android recording)
- **9**: **1** → quick (iOS setup)
- **10**: **1** → deep (iOS camera)
- **11**: **1** → deep (iOS recording)
- **12**: **1** → visual-engineering
- **13**: **1** → visual-engineering
- **14**: **1** → unspecified-high
- **15**: **1** → unspecified-high
- **FINAL**: **4** → oracle, unspecified-high x2, deep

---

## TODOs

- [ ] 1. Platform Scaffolding - Add Android and iOS platform support

  **What to do**:
  - Run `flutter create -t plugin --platforms android,ios .` from project root
  - This creates `android/` and `ios/` directories with plugin boilerplate
  - Update `pubspec.yaml` to remove `some_platform` placeholder and add proper platform declarations
  - Verify the plugin structure is correct for both platforms

  **Must NOT do**:
  - DO NOT manually create android/ios directories (use flutter create)
  - DO NOT modify existing lib/ files yet

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Simple scaffolding command, well-defined Flutter tooling
  - **Skills**: [`flutter-expert`]
    - `flutter-expert`: Flutter plugin structure and configuration
  - **Skills Evaluated but Omitted**:
    - `android-mcp`: Not needed - no Android code yet

  **Parallelization**:
  - **Can Run In Parallel**: NO (foundation task, blocks all others)
  - **Parallel Group**: Wave 1 (Task 1 only, then others can start)
  - **Blocks**: Tasks 2-15
  - **Blocked By**: None (can start immediately)

  **References**:
  - `pubspec.yaml:35-44` - Current placeholder platform config to replace
  - Flutter docs: `https://docs.flutter.dev/packages-and-plugins/developing-packages#plugin-platforms`

  **Acceptance Criteria**:
  - [ ] `android/` directory exists with valid Android plugin structure
  - [ ] `ios/` directory exists with valid iOS plugin structure
  - [ ] `pubspec.yaml` has correct platform declarations (android, ios)
  - [ ] `flutter pub get` succeeds without errors

  **QA Scenarios**:
  ```
  Scenario: Platform directories created
    Tool: Bash
    Steps:
      1. ls -la android/ ios/
    Expected Result: Both directories exist with contents
    Evidence: .sisyphus/evidence/task-01-platform-dirs.txt

  Scenario: Pubspec platform config valid
    Tool: Bash
    Steps:
      1. flutter pub get
    Expected Result: Command succeeds, no errors
    Evidence: .sisyphus/evidence/task-01-pub-get.txt
  ```

  **Commit**: YES
  - Message: `chore: add Android and iOS platform scaffolding`
  - Files: `pubspec.yaml, android/, ios/`

- [ ] 2. Dart Type Definitions - Create enums, exceptions, and models

  **What to do**:
  - Create `lib/src/` directory structure
  - Create `lib/src/camera_exception.dart` with `CameraException` class (code, message)
  - Create `lib/src/camera_description.dart` with `CameraDescription` class (name, lensDirection, sensorOrientation)
  - Create `lib/src/resolution_preset.dart` with `ResolutionPreset` enum (low, medium, high, veryHigh, max)
  - Create `lib/src/recording_state.dart` with `RecordingState` enum (idle, recording, paused)
  - Export all from `lib/waffle_camera_plugin.dart`

  **Must NOT do**:
  - DO NOT add methods that require native implementation yet
  - DO NOT over-engineer - keep types minimal

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Simple Dart type definitions, no native code
  - **Skills**: [`flutter-expert`]
    - `flutter-expert`: Dart type system and Flutter patterns

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Task 1 complete)
  - **Parallel Group**: Wave 1 (with Tasks 3, 4, 5)
  - **Blocks**: Tasks 6-15
  - **Blocked By**: Task 1

  **References**:
  - Flutter camera plugin types: `https://github.com/flutter/packages/blob/main/packages/camera/camera/lib/src/camera_description.dart`
  - Pattern: Use simple classes with const constructors

  **Acceptance Criteria**:
  - [ ] `lib/src/camera_exception.dart` exists with CameraException class
  - [ ] `lib/src/camera_description.dart` exists with CameraDescription class
  - [ ] `lib/src/resolution_preset.dart` exists with ResolutionPreset enum
  - [ ] `lib/src/recording_state.dart` exists with RecordingState enum
  - [ ] All types exported from main library file

  **QA Scenarios**:
  ```
  Scenario: Types are importable
    Tool: Bash
    Steps:
      1. dart analyze lib/
    Expected Result: No errors
    Evidence: .sisyphus/evidence/task-02-types-analyze.txt

  Scenario: Exception class works
    Tool: Bash (dart eval or test)
    Steps:
      1. Create CameraException with code and message
      2. Access code and message properties
    Expected Result: Properties return correct values
    Evidence: .sisyphus/evidence/task-02-exception-test.txt
  ```

  **Commit**: YES
  - Message: `feat(dart): add camera type definitions and exceptions`
  - Files: `lib/src/*.dart, lib/waffle_camera_plugin.dart`

- [ ] 3. Platform Interface Extension - Add camera methods to platform interface

  **What to do**:
  - Extend `WaffleCameraPluginPlatform` with camera methods:
    - `Future<List<CameraDescription>> getAvailableCameras()`
    - `Future<int> createCamera(CameraDescription camera, ResolutionPreset preset)`
    - `Future<void> initializeCamera(int cameraId)`
    - `Future<void> startRecording(int cameraId)`
    - `Future<String> stopRecording(int cameraId)` - returns file path
    - `Future<void> pauseRecording(int cameraId)`
    - `Future<void> resumeRecording(int cameraId)`
    - `Future<void> disposeCamera(int cameraId)`
    - `Stream<RecordingState> onRecordingStateChanged(int cameraId)`
  - Each method should throw `UnimplementedError` by default

  **Must NOT do**:
  - DO NOT implement methods (just declare with UnimplementedError)
  - DO NOT add methods not needed for minimal plugin

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Adding abstract method declarations
  - **Skills**: [`flutter-expert`]
    - `flutter-expert`: Platform interface patterns

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 2, 4, 5)
  - **Blocks**: Tasks 4, 6-15
  - **Blocked By**: Task 1, Task 2

  **References**:
  - `lib/waffle_camera_plugin_platform_interface.dart:5-29` - Current interface to extend
  - Pattern: Each method throws UnimplementedError

  **Acceptance Criteria**:
  - [ ] All 9 methods declared in platform interface
  - [ ] Each method throws UnimplementedError by default
  - [ ] Return types match specification
  - [ ] `dart analyze lib/` passes

  **QA Scenarios**:
  ```
  Scenario: Methods throw UnimplementedError
    Tool: Bash (flutter test)
    Steps:
      1. Call each method on default instance
      2. Verify UnimplementedError is thrown
    Expected Result: All methods throw UnimplementedError
    Evidence: .sisyphus/evidence/task-03-interface-test.txt
  ```

  **Commit**: YES
  - Message: `feat(dart): extend platform interface with camera methods`
  - Files: `lib/waffle_camera_plugin_platform_interface.dart`

- [ ] 4. Method Channel Implementation - Implement method channel mappings

  **What to do**:
  - Update `MethodChannelWaffleCameraPlugin` to implement all platform interface methods
  - Map each method to native channel calls:
    - `getAvailableCameras` → invokeMethod('getAvailableCameras')
    - `createCamera` → invokeMethod('createCamera', args)
    - etc.
  - Parse responses into proper Dart types
  - Create EventChannel for `onRecordingStateChanged`

  **Must NOT do**:
  - DO NOT implement native side yet (this task is Dart only)
  - DO NOT add business logic (just channel mapping)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Straightforward method channel implementation
  - **Skills**: [`flutter-expert`]
    - `flutter-expert`: Method channel patterns

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 2, 3, 5)
  - **Blocks**: Tasks 6-15
  - **Blocked By**: Task 1, Task 2, Task 3

  **References**:
  - `lib/waffle_camera_plugin_method_channel.dart:1-19` - Current method channel to extend
  - Pattern: Use `invokeMethod` with typed returns

  **Acceptance Criteria**:
  - [ ] All 8 method channel methods implemented
  - [ ] EventChannel created for state changes
  - [ ] Proper error handling for channel errors
  - [ ] `dart analyze lib/` passes

  **QA Scenarios**:
  ```
  Scenario: Method channel calls are mapped
    Tool: Bash (flutter test with mock channel)
    Steps:
      1. Mock method channel responses
      2. Call each method
      3. Verify correct invokeMethod calls
    Expected Result: All methods map to correct channel calls
    Evidence: .sisyphus/evidence/task-04-channel-test.txt
  ```

  **Commit**: YES
  - Message: `feat(dart): implement method channel mappings`
  - Files: `lib/waffle_camera_plugin_method_channel.dart`

- [ ] 5. Unit Tests for Dart Layer - Write comprehensive unit tests

  **What to do**:
  - Create/update tests in `test/` directory:
    - Test platform interface methods throw UnimplementedError
    - Test method channel with mocked responses
    - Test CameraException creation and properties
    - Test type serialization/deserialization
  - Follow existing test patterns in `test/waffle_camera_plugin_test.dart`
  - Use `MockPlatformInterfaceMixin` for mocking

  **Must NOT do**:
  - DO NOT write integration tests (those come later)
  - DO NOT test native implementations

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Standard Flutter unit testing
  - **Skills**: [`flutter-expert`]
    - `flutter-expert`: Flutter testing patterns

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 2, 3, 4)
  - **Blocks**: None (tests verify other tasks)
  - **Blocked By**: Task 2, Task 3, Task 4

  **References**:
  - `test/waffle_camera_plugin_test.dart` - Existing test patterns
  - `test/waffle_camera_plugin_method_channel_test.dart` - Method channel test patterns

  **Acceptance Criteria**:
  - [ ] Platform interface tests exist and pass
  - [ ] Method channel tests exist and pass
  - [ ] Type tests exist and pass
  - [ ] `flutter test` passes with 0 failures

  **QA Scenarios**:
  ```
  Scenario: All unit tests pass
    Tool: Bash
    Steps:
      1. flutter test
    Expected Result: All tests pass, 0 failures
    Evidence: .sisyphus/evidence/task-05-tests-pass.txt
  ```

  **Commit**: YES
  - Message: `test(dart): add unit tests for platform interface and method channel`
  - Files: `test/*.dart`
  - Pre-commit: `flutter test`

- [ ] 6. Android Native - Project Setup and Permissions

  **What to do**:
  - Update `android/build.gradle` with CameraX dependencies:
    - `androidx.camera:camera-core:1.3.4`
    - `androidx.camera:camera-camera2:1.3.4`
    - `androidx.camera:camera-lifecycle:1.3.4`
    - `androidx.camera:camera-video:1.3.4`
    - `androidx.camera:camera-view:1.3.4`
  - Update `android/src/main/AndroidManifest.xml` with permissions:
    - `CAMERA`
    - `RECORD_AUDIO`
  - Set minimum SDK to 21 in `build.gradle`
  - Create main plugin class extending `FlutterPlugin`

  **Must NOT do**:
  - DO NOT implement camera logic yet (this is setup only)
  - DO NOT add permissions not needed (like WRITE_EXTERNAL_STORAGE for API 29+)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Configuration and dependency setup
  - **Skills**: [`flutter-expert`, `android-mcp`]
    - `flutter-expert`: Flutter plugin Android structure
    - `android-mcp`: Android build configuration

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 7-11)
  - **Blocks**: Tasks 7-8
  - **Blocked By**: Tasks 1-5

  **References**:
  - CameraX docs: `https://developer.android.com/training/camerax`
  - `android/build.gradle` - Add dependencies here
  - `android/src/main/AndroidManifest.xml` - Add permissions

  **Acceptance Criteria**:
  - [ ] CameraX dependencies added to build.gradle
  - [ ] Camera and microphone permissions declared
  - [ ] Plugin class exists and extends FlutterPlugin
  - [ ] `flutter build apk --debug` succeeds

  **QA Scenarios**:
  ```
  Scenario: Android build succeeds
    Tool: Bash
    Steps:
      1. cd example && flutter build apk --debug
    Expected Result: BUILD SUCCESSFUL
    Evidence: .sisyphus/evidence/task-06-android-build.txt
  ```

  **Commit**: YES
  - Message: `chore(android): add CameraX dependencies and permissions`
  - Files: `android/build.gradle, android/src/main/AndroidManifest.xml, android/src/main/kotlin/...`

- [ ] 7. Android Native - Camera Initialization and Preview

  **What to do**:
  - Implement camera initialization in plugin class:
    - Request camera and microphone permissions at runtime
    - Create `ProcessCameraProvider` instance
    - Bind `Preview` use case to lifecycle
    - Bind `VideoCapture<Recorder>` use case
    - Create Texture entry point for preview
    - Handle camera selection (front/back via `CameraSelector`)
    - Handle resolution preset mapping to CameraX quality
  - Implement method channel handler for:
    - `getAvailableCameras` - return list of CameraDescription
    - `createCamera` - create camera with specified settings
    - `initializeCamera` - bind use cases to lifecycle
  - Send texture ID back to Flutter for preview widget

  **Must NOT do**:
  - DO NOT implement recording logic (Task 8)
  - DO NOT call CameraX from background threads
  - DO NOT forget to unbind use cases on dispose

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Complex Android CameraX integration with lifecycle management
  - **Skills**: [`flutter-expert`, `android-mcp`]
    - `flutter-expert`: Flutter plugin Android patterns
    - `android-mcp`: CameraX API and Android lifecycle

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 6, 8-11)
  - **Blocks**: Task 8, Task 14
  - **Blocked By**: Task 6

  **References**:
  - CameraX setup: `https://developer.android.com/training/camerax/preview`
  - `android/src/main/kotlin/.../WaffleCameraPlugin.kt` - Main plugin class
  - Use `ProcessCameraProvider.bindToLifecycle()` for lifecycle binding

  **Acceptance Criteria**:
  - [ ] Permission request works (CAMERA, RECORD_AUDIO)
  - [ ] Camera preview displays via Texture
  - [ ] Front/back camera selection works
  - [ ] Resolution preset applies correctly
  - [ ] Method channel returns camera list

  **QA Scenarios**:
  ```
  Scenario: Camera preview displays on Android
    Tool: mobile-mcp or android-mcp
    Preconditions: Android device connected, permissions granted
    Steps:
      1. Launch example app
      2. Tap "Initialize Camera"
      3. Observe preview widget
    Expected Result: Camera preview visible in Texture widget
    Evidence: .sisyphus/evidence/task-07-android-preview.png

  Scenario: Camera selection works
    Tool: mobile-mcp or android-mcp
    Steps:
      1. Launch example app
      2. Tap "Switch Camera"
      3. Verify camera changes from back to front
    Expected Result: Front camera preview displays
    Evidence: .sisyphus/evidence/task-07-camera-switch.png
  ```

  **Commit**: YES
  - Message: `feat(android): implement camera initialization and texture preview`
  - Files: `android/src/main/kotlin/.../*.kt`

- [ ] 8. Android Native - Video Recording with Pause/Resume

  **What to do**:
  - Implement recording in Android plugin:
    - Configure `Recorder` with quality settings
    - Create output file in temp directory (cacheDir)
    - Implement `startRecording` using `Recording.start()`
    - Implement `pauseRecording` using `Recording.pause()`
    - Implement `resumeRecording` using `Recording.resume()`
    - Implement `stopRecording` using `Recording.stop()`
    - Return file path on stop
    - Send recording state changes via EventChannel
  - Handle error cases:
    - Not recording when pause/resume called
    - Storage errors
    - Recording in progress when start called

  **Must NOT do**:
  - DO NOT allow camera switching during recording
  - DO NOT use deprecated APIs
  - DO NOT block main thread with recording operations

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Complex video recording with state management
  - **Skills**: [`flutter-expert`, `android-mcp`]
    - `flutter-expert`: Flutter event channel patterns
    - `android-mcp`: CameraX video recording APIs

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 6-7, 9-11)
  - **Blocks**: Task 14
  - **Blocked By**: Task 7

  **References**:
  - CameraX video: `https://developer.android.com/training/camerax/video-capture`
  - Use `FileOutputOptions` for file output
  - Listen to `VideoRecordEvent` for state changes

  **Acceptance Criteria**:
  - [ ] Recording starts and creates video file
  - [ ] Pause stops video capture temporarily
  - [ ] Resume continues video capture
  - [ ] Stop returns valid file path
  - [ ] File exists and has content > 0 bytes
  - [ ] State changes sent to Flutter via EventChannel

  **QA Scenarios**:
  ```
  Scenario: Full recording flow on Android
    Tool: mobile-mcp or android-mcp
    Preconditions: Android device, permissions granted
    Steps:
      1. Initialize camera
      2. Start recording
      3. Wait 2 seconds
      4. Pause recording
      5. Wait 1 second
      6. Resume recording
      7. Wait 1 second
      8. Stop recording
      9. Verify returned path exists
    Expected Result: Video file created at returned path
    Evidence: .sisyphus/evidence/task-08-android-recording.txt

  Scenario: Pause without recording fails gracefully
    Tool: mobile-mcp or android-mcp
    Steps:
      1. Initialize camera (don't start recording)
      2. Tap "Pause"
    Expected Result: Error shown, no crash
    Evidence: .sisyphus/evidence/task-08-android-pause-error.txt
  ```

  **Commit**: YES
  - Message: `feat(android): implement video recording with pause/resume`
  - Files: `android/src/main/kotlin/.../*.kt`

- [ ] 9. iOS Native - Project Setup and Permissions

  **What to do**:
  - Update `ios/waffle_camera_plugin.podspec` with dependencies
  - Add permission descriptions to example app's `Info.plist`:
    - `NSCameraUsageDescription`: "This app needs camera access to record videos"
    - `NSMicrophoneUsageDescription`: "This app needs microphone access to record audio"
  - Set minimum iOS version to 18.0 in podspec
  - Create main Swift plugin class implementing `FlutterPlugin`
  - Set up method channel handler

  **Must NOT do**:
  - DO NOT support iOS < 18
  - DO NOT implement camera logic yet (this is setup only)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Configuration and permission setup
  - **Skills**: [`flutter-expert`]
    - `flutter-expert`: Flutter plugin iOS structure

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 6-8, 10-11)
  - **Blocks**: Tasks 10-11
  - **Blocked By**: Tasks 1-5

  **References**:
  - `ios/waffle_camera_plugin.podspec` - Add dependencies
  - `example/ios/Runner/Info.plist` - Add permission descriptions
  - iOS 18 AVFoundation: `https://developer.apple.com/documentation/avfoundation`

  **Acceptance Criteria**:
  - [ ] Podspec configured correctly
  - [ ] Permission descriptions in Info.plist
  - [ ] Minimum iOS version set to 18.0
  - [ ] Plugin class exists and registers with Flutter
  - [ ] `flutter build ios --debug --no-codesign` succeeds

  **QA Scenarios**:
  ```
  Scenario: iOS build succeeds
    Tool: Bash
    Steps:
      1. cd example && flutter build ios --debug --no-codesign
    Expected Result: BUILD SUCCEEDED
    Evidence: .sisyphus/evidence/task-09-ios-build.txt
  ```

  **Commit**: YES
  - Message: `chore(ios): add AVFoundation dependencies and permissions`
  - Files: `ios/*.podspec, example/ios/Runner/Info.plist, ios/Classes/*.swift`

- [ ] 10. iOS Native - Camera Initialization and Preview

  **What to do**:
  - Implement camera initialization in Swift:
    - Request camera and microphone permissions using `AVCaptureDevice.requestAccess`
    - Create `AVCaptureSession`
    - Configure input (camera device) and output (video preview, file output)
    - Handle camera selection (front/back via `AVCaptureDevice.Position`)
    - Handle resolution preset mapping to session preset
    - Create `FlutterTexture` for preview
    - Register texture with Flutter engine
  - Implement method channel handler for:
    - `getAvailableCameras` - return available devices
    - `createCamera` - create capture session
    - `initializeCamera` - start capture session

  **Must NOT do**:
  - DO NOT implement recording logic (Task 11)
  - DO NOT call capture session methods from background thread
  - DO NOT forget to stop session on dispose

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Complex AVFoundation integration with texture support
  - **Skills**: [`flutter-expert`]
    - `flutter-expert`: Flutter iOS plugin patterns

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 6-9, 11)
  - **Blocks**: Task 11, Task 15
  - **Blocked By**: Task 9

  **References**:
  - AVFoundation: `https://developer.apple.com/documentation/avfoundation/cameras_and_media_capture`
  - `ios/Classes/WaffleCameraPlugin.swift` - Main plugin class
  - Use `AVCaptureSession.startRunning()` on background thread

  **Acceptance Criteria**:
  - [ ] Permission request works (camera, microphone)
  - [ ] Camera preview displays via Texture
  - [ ] Front/back camera selection works
  - [ ] Resolution preset applies correctly
  - [ ] Method channel returns camera list

  **QA Scenarios**:
  ```
  Scenario: Camera preview displays on iOS
    Tool: phoneagent
    Preconditions: iOS device connected, permissions granted
    Steps:
      1. Launch example app
      2. Tap "Initialize Camera"
      3. Observe preview widget
    Expected Result: Camera preview visible in Texture widget
    Evidence: .sisyphus/evidence/task-10-ios-preview.png

  Scenario: Camera selection works on iOS
    Tool: phoneagent
    Steps:
      1. Launch example app
      2. Tap "Switch Camera"
      3. Verify camera changes from back to front
    Expected Result: Front camera preview displays
    Evidence: .sisyphus/evidence/task-10-ios-camera-switch.png
  ```

  **Commit**: YES
  - Message: `feat(ios): implement camera initialization and texture preview`
  - Files: `ios/Classes/*.swift`

- [ ] 11. iOS Native - Video Recording with Pause/Resume

  **What to do**:
  - Implement recording in Swift:
    - Create `AVCaptureMovieFileOutput`
    - Add output to capture session
    - Create output file URL in temp directory (NSTemporaryDirectory)
    - Implement `startRecording` using `startRecording(to:recordingDelegate:)`
    - Implement `pauseRecording` using `pauseRecording()` (iOS 18+)
    - Implement `resumeRecording` using `resumeRecording()` (iOS 18+)
    - Implement `stopRecording` using `stopRecording()`
    - Return file path on stop via delegate callback
    - Send recording state changes via EventChannel
  - Handle error cases:
    - Not recording when pause/resume called
    - Storage errors
    - Recording in progress when start called

  **Must NOT do**:
  - DO NOT use deprecated APIs
  - DO NOT forget to check iOS 18 availability (though we require it)
  - DO NOT allow camera switching during recording

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Complex video recording with state management
  - **Skills**: [`flutter-expert`]
    - `flutter-expert`: Flutter event channel patterns

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 6-10)
  - **Blocks**: Task 15
  - **Blocked By**: Task 10

  **References**:
  - AVCaptureMovieFileOutput: `https://developer.apple.com/documentation/avfoundation/avcapturemoviefileoutput`
  - `pauseRecording()`: iOS 18+ API
  - Use `AVCaptureFileOutputRecordingDelegate` for callbacks

  **Acceptance Criteria**:
  - [ ] Recording starts and creates video file
  - [ ] Pause stops video capture temporarily
  - [ ] Resume continues video capture
  - [ ] Stop returns valid file path
  - [ ] File exists and has content > 0 bytes
  - [ ] State changes sent to Flutter via EventChannel

  **QA Scenarios**:
  ```
  Scenario: Full recording flow on iOS
    Tool: phoneagent
    Preconditions: iOS device (iOS 18+), permissions granted
    Steps:
      1. Initialize camera
      2. Start recording
      3. Wait 2 seconds
      4. Pause recording
      5. Wait 1 second
      6. Resume recording
      7. Wait 1 second
      8. Stop recording
      9. Verify returned path exists
    Expected Result: Video file created at returned path
    Evidence: .sisyphus/evidence/task-11-ios-recording.txt

  Scenario: Pause without recording fails gracefully
    Tool: phoneagent
    Steps:
      1. Initialize camera (don't start recording)
      2. Tap "Pause"
    Expected Result: Error shown, no crash
    Evidence: .sisyphus/evidence/task-11-ios-pause-error.txt
  ```

  **Commit**: YES
  - Message: `feat(ios): implement video recording with pause/resume`
  - Files: `ios/Classes/*.swift`

- [ ] 12. Camera Preview Widget - Create Texture-based preview widget

  **What to do**:
  - Create `lib/camera_preview.dart` with `CameraPreview` widget
  - Widget should:
    - Accept `cameraId` as parameter
    - Use `Texture` widget with texture ID from platform
    - Handle loading and error states
    - Support aspect ratio configuration
    - Be stateless where possible
  - Export from main library file

  **Must NOT do**:
  - DO NOT add recording controls (widget is preview only)
  - DO NOT use PlatformView (use Texture for performance)

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
    - Reason: Flutter widget with visual preview component
  - **Skills**: [`flutter-expert`, `flutter-animations`]
    - `flutter-expert`: Flutter widget patterns
    - `flutter-animations`: Smooth state transitions

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 13-15)
  - **Blocks**: Task 13
  - **Blocked By**: Tasks 1-5

  **References**:
  - Flutter Texture widget: `https://api.flutter.dev/flutter/widgets/Texture-class.html`
  - Pattern: Get texture ID from platform, render in Texture widget

  **Acceptance Criteria**:
  - [ ] CameraPreview widget exists
  - [ ] Widget displays camera preview via Texture
  - [ ] Loading state shown while initializing
  - [ ] Error state shown on failure
  - [ ] Exported from main library

  **QA Scenarios**:
  ```
  Scenario: Preview widget renders
    Tool: Bash (flutter test)
    Steps:
      1. Create widget test for CameraPreview
      2. Verify widget builds with valid texture ID
    Expected Result: Widget renders without errors
    Evidence: .sisyphus/evidence/task-12-widget-test.txt
  ```

  **Commit**: YES
  - Message: `feat(widget): add CameraPreview texture widget`
  - Files: `lib/camera_preview.dart, lib/waffle_camera_plugin.dart`

- [ ] 13. Example App - Full demo UI

  **What to do**:
  - Update `example/lib/main.dart` with complete demo:
    - Camera preview display
    - Initialize/dispose camera buttons
    - Start/stop recording buttons
    - Pause/resume recording buttons
    - Camera switch button (front/back)
    - Quality/resolution selector
    - Display recorded file path
    - Error handling UI
  - Add necessary state management (setState or simple provider)
  - Show recording state indicator
  - Display video thumbnail after recording (optional)

  **Must NOT do**:
  - DO NOT add features not in plugin scope
  - DO NOT use complex state management (keep simple)

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
    - Reason: Complete example app UI with multiple controls
  - **Skills**: [`flutter-expert`, `flutter-animations`]
    - `flutter-expert`: Flutter app structure
    - `flutter-animations`: Recording state animations

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 12, 14-15)
  - **Blocks**: Tasks 14-15
  - **Blocked By**: Task 12

  **References**:
  - `example/lib/main.dart` - Current example to update
  - Pattern: Simple StatefulWidget with all controls

  **Acceptance Criteria**:
  - [ ] App displays camera preview
  - [ ] All recording controls work
  - [ ] Camera switch works
  - [ ] Quality selection works
  - [ ] File path displayed after recording
  - [ ] Errors displayed to user

  **QA Scenarios**:
  ```
  Scenario: Example app runs on Android
    Tool: mobile-mcp or android-mcp
    Steps:
      1. cd example && flutter run
      2. Initialize camera
      3. Start, pause, resume, stop recording
      4. Verify file path shown
    Expected Result: All controls work, video saved
    Evidence: .sisyphus/evidence/task-13-example-android.png

  Scenario: Example app runs on iOS
    Tool: phoneagent
    Steps:
      1. cd example && flutter run
      2. Initialize camera
      3. Start, pause, resume, stop recording
      4. Verify file path shown
    Expected Result: All controls work, video saved
    Evidence: .sisyphus/evidence/task-13-example-ios.png
  ```

  **Commit**: YES
  - Message: `feat(example): update example app with full demo`
  - Files: `example/lib/main.dart`

- [ ] 14. Integration Tests - Android

  **What to do**:
  - Create `example/integration_test/camera_android_test.dart`
  - Test full recording flow:
    - Get available cameras
    - Create and initialize camera
    - Start recording
    - Pause and resume recording
    - Stop recording and verify file path
    - Dispose camera
  - Test error cases:
    - Pause without recording
    - Resume without pause
    - Start recording twice
  - Test camera switching
  - Test quality settings

  **Must NOT do**:
  - DO NOT run tests on emulator (use real device for camera)
  - DO NOT skip error case tests

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Comprehensive integration testing
  - **Skills**: [`flutter-expert`, `android-mcp`]
    - `flutter-expert`: Flutter integration test patterns
    - `android-mcp`: Android device testing

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 12-13, 15)
  - **Blocks**: Final Verification
  - **Blocked By**: Tasks 7-8, 13

  **References**:
  - `example/integration_test/plugin_integration_test.dart` - Existing integration test
  - Pattern: Use `IntegrationTestWidgetsFlutterBinding`

  **Acceptance Criteria**:
  - [ ] Integration test file created
  - [ ] All happy path tests pass
  - [ ] All error case tests pass
  - [ ] Tests run on real Android device

  **QA Scenarios**:
  ```
  Scenario: Android integration tests pass
    Tool: Bash (flutter test integration_test)
    Preconditions: Android device connected
    Steps:
      1. cd example && flutter test integration_test/camera_android_test.dart -d <device>
    Expected Result: All tests pass
    Evidence: .sisyphus/evidence/task-14-android-integration.txt
  ```

  **Commit**: YES
  - Message: `test(integration): add Android integration tests`
  - Files: `example/integration_test/camera_android_test.dart`

- [ ] 15. Integration Tests - iOS

  **What to do**:
  - Create `example/integration_test/camera_ios_test.dart`
  - Test full recording flow (same as Android):
    - Get available cameras
    - Create and initialize camera
    - Start recording
    - Pause and resume recording
    - Stop recording and verify file path
    - Dispose camera
  - Test error cases:
    - Pause without recording
    - Resume without pause
    - Start recording twice
  - Test camera switching
  - Test quality settings

  **Must NOT do**:
  - DO NOT run tests on simulator (use real device for camera)
  - DO NOT skip error case tests

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Comprehensive integration testing
  - **Skills**: [`flutter-expert`, `phoneagent`]
    - `flutter-expert`: Flutter integration test patterns
    - `phoneagent`: iOS device testing

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 12-14)
  - **Blocks**: Final Verification
  - **Blocked By**: Tasks 10-11, 13

  **References**:
  - `example/integration_test/plugin_integration_test.dart` - Existing integration test
  - Pattern: Use `IntegrationTestWidgetsFlutterBinding`

  **Acceptance Criteria**:
  - [ ] Integration test file created
  - [ ] All happy path tests pass
  - [ ] All error case tests pass
  - [ ] Tests run on real iOS device (iOS 18+)

  **QA Scenarios**:
  ```
  Scenario: iOS integration tests pass
    Tool: Bash (flutter test integration_test)
    Preconditions: iOS device connected (iOS 18+)
    Steps:
      1. cd example && flutter test integration_test/camera_ios_test.dart -d <device>
    Expected Result: All tests pass
    Evidence: .sisyphus/evidence/task-15-ios-integration.txt
  ```

  **Commit**: YES
  - Message: `test(integration): add iOS integration tests`
  - Files: `example/integration_test/camera_ios_test.dart`

---

## Final Verification Wave (MANDATORY — after ALL implementation tasks)

- [ ] F1. **Plan Compliance Audit** — `oracle`
  Read the plan end-to-end. For each "Must Have": verify implementation exists. For each "Must NOT Have": search codebase for forbidden patterns. Check evidence files exist. Compare deliverables against plan.
  Output: `Must Have [N/N] | Must NOT Have [N/N] | Tasks [N/N] | VERDICT: APPROVE/REJECT`

- [ ] F2. **Code Quality Review** — `unspecified-high`
  Run `dart analyze` + `flutter test`. Review all changed files for: `as any`/`@ts-ignore` equivalents, empty catches, print statements in prod, commented-out code, unused imports. Check AI slop: excessive comments, over-abstraction, generic names.
  Output: `Analyze [PASS/FAIL] | Tests [N pass/N fail] | Files [N clean/N issues] | VERDICT`

- [ ] F3. **Real Device QA** — `unspecified-high` (+ `android-mcp` or `phoneagent` skill)
  Deploy to real Android and iOS devices. Execute full recording flow: initialize → start → pause → resume → stop → verify file. Test error cases: permission denial, wrong state transitions. Capture evidence.
  Output: `Recording [PASS/FAIL] | Pause/Resume [PASS/FAIL] | File Path [PASS/FAIL] | VERDICT`

- [ ] F4. **Scope Fidelity Check** — `deep`
  For each task: read "What to do", read actual diff. Verify 1:1 — everything in spec was built, nothing beyond spec was built. Check "Must NOT do" compliance. Detect cross-task contamination.
  Output: `Tasks [N/N compliant] | Contamination [CLEAN/N issues] | VERDICT`

---

## Commit Strategy

> **COMMIT AFTER EVERY TASK** — Each task must be committed before moving to the next.

### Per-Task Commits

| Task | Commit Message | Files |
|------|----------------|-------|
| 1 | `chore: add Android and iOS platform scaffolding` | `pubspec.yaml, android/, ios/` |
| 2 | `feat(dart): add camera type definitions and exceptions` | `lib/src/*.dart, lib/waffle_camera_plugin.dart` |
| 3 | `feat(dart): extend platform interface with camera methods` | `lib/waffle_camera_plugin_platform_interface.dart` |
| 4 | `feat(dart): implement method channel mappings` | `lib/waffle_camera_plugin_method_channel.dart` |
| 5 | `test(dart): add unit tests for platform interface and method channel` | `test/*.dart` |
| 6 | `chore(android): add CameraX dependencies and permissions` | `android/build.gradle, android/src/main/AndroidManifest.xml, android/src/main/kotlin/...` |
| 7 | `feat(android): implement camera initialization and texture preview` | `android/src/main/kotlin/.../*.kt` |
| 8 | `feat(android): implement video recording with pause/resume` | `android/src/main/kotlin/.../*.kt` |
| 9 | `chore(ios): add AVFoundation dependencies and permissions` | `ios/*.podspec, example/ios/Runner/Info.plist, ios/Classes/*.swift` |
| 10 | `feat(ios): implement camera initialization and texture preview` | `ios/Classes/*.swift` |
| 11 | `feat(ios): implement video recording with pause/resume` | `ios/Classes/*.swift` |
| 12 | `feat(widget): add CameraPreview texture widget` | `lib/camera_preview.dart, lib/waffle_camera_plugin.dart` |
| 13 | `feat(example): update example app with full demo` | `example/lib/main.dart` |
| 14 | `test(integration): add Android integration tests` | `example/integration_test/camera_android_test.dart` |
| 15 | `test(integration): add iOS integration tests` | `example/integration_test/camera_ios_test.dart` |
| F1-F4 | `chore: add final verification evidence` | `.sisyphus/evidence/final-*/` |

### Commit Guidelines

1. **Atomic commits**: Each commit represents exactly one completed task
2. **Pre-commit validation**: Run `flutter test` (or task-specific validation) before committing
3. **Descriptive messages**: Use conventional commit format with clear scope
4. **No WIP commits**: Only commit when task acceptance criteria are met
5. **Revertibility**: Any single commit can be reverted without breaking the build

### Git Workflow

```bash
# After completing each task:
git add <files>
git commit -m "<commit message>"
git push origin <branch>  # Optional: push after each commit or after each wave
```

---

## Success Criteria

### Verification Commands
```bash
# Dart unit tests
flutter test
# Expected: All tests pass

# Android build
cd example && flutter build apk --debug
# Expected: BUILD SUCCESSFUL

# iOS build (macOS only)
cd example && flutter build ios --debug --no-codesign
# Expected: BUILD SUCCEEDED

# Integration tests (requires device)
cd example && flutter test integration_test/camera_integration_test.dart
# Expected: All tests pass
```

### Final Checklist
- [ ] All "Must Have" features implemented
- [ ] All "Must NOT Have" constraints respected
- [ ] All unit tests pass
- [ ] Integration tests pass on both platforms
- [ ] Recording produces valid video file
- [ ] Pause/resume works correctly
- [ ] File path returned after recording
- [ ] Permissions requested and handled
- [ ] Camera preview displays correctly
- [ ] Front/back camera switching works
- [ ] Quality settings applied
