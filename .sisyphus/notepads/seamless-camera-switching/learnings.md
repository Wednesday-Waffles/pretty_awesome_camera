# Task 1: Define Platform API and State Rules

## Completed Implementation

### Changes Made:
1. **RecordingState Enum** - Extended `lib/src/recording_state.dart` to add `switching` state
   - Added new enum value with documentation
   - Pattern: Document each state with /// comment

2. **Platform Interface** - Extended `lib/waffle_camera_plugin_platform_interface.dart` with 3 new abstract methods:
   - `Future<bool> canSwitchCamera(int cameraId)` - Check if camera can switch
   - `Future<void> switchCamera(int cameraId)` - Switch to a different camera
   - `Future<bool> get canSwitchCurrentCamera` - Convenience getter for current camera
   - All methods include comprehensive dartdoc comments explaining behavior and exceptions

3. **Method Channel Implementation** - Added implementations in `lib/waffle_camera_plugin_method_channel.dart`:
   - Each method uses `methodChannel.invokeMethod()` following existing pattern
   - Proper error handling: catch `PlatformException`, wrap in `CameraException`
   - Return defaults: `canSwitch ?? false` for bool returns, void for switch operation

4. **Test Fixes** - Updated `test/waffle_camera_plugin_test.dart`:
   - Added new method implementations to `MockWaffleCameraPluginPlatform`
   - Added new method implementations to `ConcreteWaffleCameraPluginPlatform`
   - All 66 tests pass with no errors

### Key Patterns Observed:
- **Error Handling**: PlatformException → CameraException with code and message
- **Bool Returns**: Use `?? false` to handle null from platform
- **Method Naming**: Snake_case for method channel calls (e.g., 'switchCamera')
- **Documentation**: Comprehensive dartdoc with @override on all implementations

### Verification Results:
- `dart analyze lib/` - No errors (only 2 info warnings about super parameters in unrelated files)
- `flutter test` - All 66 tests pass ✓
- Implementation follows existing patterns consistently ✓
- No breaking changes to existing public APIs ✓

---

# Task 2: Runtime Capability Detection and Path Selection

## Completed Implementation

### Files Created:

1. **lib/src/switching_path.dart** - Internal enum for switching paths
   - `iosOptimizedMultiCam` - Fast path on iOS MultiCam devices
   - `fallbackSegmentMerge` - Segment merge on iOS non-MultiCam devices
   - `androidFallbackSegmentMerge` - Fallback path for all Android v4.1 devices
   - Documentation marks this as internal-only; users see same public API regardless of path

2. **lib/src/switching_capability.dart** - Capability detection class
   - `SwitchingCapability` class manages runtime path selection
   - `detectedPath` getter: async detection with caching
   - iOS detection: Calls `isMultiCamSupported()` via method channel
   - Android detection: Always returns fallback path in v4.1
   - Logging with `dart:developer.log` shows selected path for debugging
   - `canUseOptimizedPath()` sync method checks cached path
   - `_detectAndroidConcurrentCameras()` future-facing helper for v4.2 research
   - Falls back gracefully if detection fails

### Platform Interface Changes:

Added 2 new abstract methods to `lib/waffle_camera_plugin_platform_interface.dart`:
- `Future<bool> isMultiCamSupported()` - iOS MultiCam detection
- `Future<String> getSwitchingPath()` - Returns detected path name

### Method Channel Implementation:

Added to `lib/waffle_camera_plugin_method_channel.dart`:
- `isMultiCamSupported()` implementation with proper error handling
- `getSwitchingPath()` implementation using `SwitchingCapability`
- Both follow error pattern: PlatformException → CameraException

### Test Updates:

Updated test mocks to implement new interface methods:
- Added to `MockWaffleCameraPluginPlatform` (test mock)
- Added to `ConcreteWaffleCameraPluginPlatform` (test base)

## Key Implementation Patterns

### Capability Detection Strategy:
1. **Platform check first** - iOS vs Android early decision
2. **iOS optimized path** - Check `isMultiCamSupported` via method channel
3. **Android v4.1 rule** - Always fallback (explicit constraint)
4. **Fallback gracefully** - If detection fails, use fallback path
5. **Cache result** - `_detectedPath` field prevents repeated detection

### Logging Pattern:
- Uses `dart:developer.log` with name `'waffle_camera.switching'`
- Logs show: platform, MultiCam status, selected path
- Useful for QA debugging and verifying correct path selection

### Error Handling:
- PlatformException → CameraException with code and message
- Detection failures wrapped in `capability_detection_failed` code
- Falls back to fallback path if native detection throws

### Future-Facing Design:
- `_detectAndroidConcurrentCameras()` method included for v4.2
- Uses `CameraManager.getConcurrentCameraIds()` API
- Marked with `// ignore: unused_element` comment
- Demonstrates that concurrent support ≠ production readiness
- Shows research path without exposing incomplete features

## Verification Results

- `dart analyze lib/` ✓ Clean (2 info warnings pre-existing in camera_preview.dart)
- `flutter test` ✓ All 66 tests pass
- Implementation follows existing patterns ✓
- No breaking changes to public APIs ✓
- Path selection deterministic and logged ✓

## Design Notes

### Why Internal-Only Path:
- Users don't need to know about implementation details
- Same public API surface for all devices
- Easier to swap paths in future versions without API churn

### Why Fallback on Android v4.1:
- Concurrent camera support requires careful validation on real hardware
- Single-encoder switching flow needs device-specific tuning
- v4.2 evaluation gate prevents premature optimization
- Fallback path is proven and reliable

### Why Fallback on MultiCam Detection Failure:
- Better safe than sorry - conservative default
- Preserves recording functionality even if detection breaks
- Allows graceful degradation in edge cases

