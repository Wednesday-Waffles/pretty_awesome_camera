# Seamless Camera Switching During Recording (v4.1)

## TL;DR

> **Quick Summary**: Implement seamless camera switching during video recording with a **phased, risk-reduced architecture**:
> 1. **Phase v4.1**: API + iOS optimized path (MultiCam-capable devices only) + iOS fallback + Android fallback.
> 2. **Phase v4.2**: Evaluate Android optimized no-merge switching only after validating a concrete mechanism on target hardware.
>
> **Why this plan**:
> - Avoids unsupported assumptions about simultaneous front/back capture on all devices.
> - Preserves broad compatibility through fallback segment-merge paths.
> - Delivers the clearest high-confidence implementation first.
>
> **Deliverables in v4.1**:
> - Platform API additions: `canSwitchCamera`, `switchCamera`, `canSwitchCurrentCamera`
> - Runtime capability detection and path selection
> - iOS optimized path using `AVCaptureMultiCamSession` where supported
> - iOS fallback segment-recording + merge path
> - Android fallback segment-recording + merge path
> - Single user-facing output file on all supported paths
> - Example app updates and integration tests
>
> **Estimated Effort**: Large
> **Parallel Execution**: YES - 4 waves
> **Critical Path**: Task 1 → Task 2 → (Tasks 3-5 iOS + 6-7 Android in parallel) → Task 8 → Tasks 9-10 → Final verification

---

## Context

### Original Request
The goal is to let users switch between front and back cameras during video recording while ending with one final output file.

### Architecture Decision
Use a **tiered implementation** instead of assuming one universal strategy:

- **Tier A: iOS optimized no-merge path**
  - Use only when `AVCaptureMultiCamSession.isMultiCamSupported` is true.
  - This provides the best switching behavior on supported iPhones.

- **Tier B: Fallback segment-merge path**
  - Use on iOS devices without MultiCam support.
  - Use as the default Android implementation in v4.1.
  - This preserves broad compatibility and avoids unsupported camera assumptions.

### Why Android optimized is deferred
Even when Android reports concurrent camera combinations, that does **not** automatically define a simple or safe single-encoder switching architecture for this plugin. The exact encoder/camera pipeline still needs validation on real devices before it should be committed as production scope.

---

## Phased Delivery

### v4.1
- API + state model
- Runtime path selection
- iOS optimized path (MultiCam-capable devices only)
- iOS fallback segment-merge path
- Android fallback segment-merge path
- Method channels, example app, and integration tests

### v4.2
- Android optimized no-merge path, only after validation on devices with verified concurrent front/back support

---

## Objectives

### Core Objective
Enable camera switching during recording with one final output file, using the safest supported implementation per device.

### Deliverables
- `canSwitchCamera(int cameraId) -> Future<bool>`
- `canSwitchCurrentCamera -> Future<bool>`
- `switchCamera(int cameraId) -> Future<void>`
- Runtime capability detection for optimized vs fallback path
- iOS optimized implementation for MultiCam-capable devices
- iOS fallback implementation for non-MultiCam devices
- Android fallback implementation for current release scope
- Updated example app and automated tests

### Definition of Done
- [ ] User can tap “Switch Camera” while recording.
- [ ] App keeps a single user-facing recording flow.
- [ ] Final result is one output file on both optimized and fallback paths.
- [ ] Capability detection selects the correct path at runtime.
- [ ] Unsupported optimized paths fall back automatically.
- [ ] Existing recording APIs remain backward compatible.

### Must Have
- One final output file returned to Flutter.
- Explicit runtime capability detection before choosing path.
- iOS optimized path only on MultiCam-supported devices.
- Fallback path on iOS and Android.
- Error handling for invalid state and concurrent switching.
- Integration tests for optimized and fallback behavior.

### Must NOT Have
- Assuming concurrent front/back camera support on all devices.
- Assuming Android optimized no-merge switching is ready in v4.1.
- Breaking existing recording methods.
- Leaving temporary files behind after success or failure.

---

## Runtime Strategy

### Path Selection Rules
At recording start, choose the implementation path in this order:

1. **iOS optimized path**
   - If `AVCaptureMultiCamSession.isMultiCamSupported` is true, use MultiCam path.

2. **Fallback path**
   - Otherwise use segmented recording with post-stop merge.

3. **Android v4.1 rule**
   - Always use fallback path in v4.1.
   - Android optimized path is explicitly out of scope until validated in v4.2.

### Android Concurrent Camera Verification
- Use `CameraManager.getConcurrentCameraIds()` in the future Android optimized evaluation to determine whether the desired front/back camera pair can be configured concurrently.
- Treat API level alone as insufficient proof of concurrent-camera support.
- If concurrent combinations do not include the selected front/back pair, optimized Android switching must not be attempted.

**Known Limitation**:
- Even when concurrent streaming is supported, feeding both cameras into a practical single-encoder switching flow may still require custom buffer routing and hardware-specific validation.
- That may not provide enough latency benefit over fallback segment-merge to justify Phase 1 complexity.

**Initial Implementation Decision**:
- v4.1 ships **fallback-only on Android**.
- Android optimized no-merge switching is deferred to v4.2.

### User Experience Contract
Regardless of path:
- App exposes the same public Dart API.
- User sees one recording session.
- User receives one final output file.
- If switching fails, the error is surfaced clearly and recording state remains consistent.

### Recording State Machine
```text
idle
  └─[startRecording]──► recording
                            ├─[switchCamera]──► switching ──► recording
                            └─[stopRecording]──► finalizing ──► idle
```text

- `switching` is guarded by `isSwitching`.
- `switchCamera` when not recording throws `CameraException('invalidState', ...)`.
- Concurrent `switchCamera` calls throw `CameraException('switchInProgress', ...)`.
- If switching fails mid-recording, native code must either continue safely on the current camera or fail clearly with a standardized error contract.

---

## Performance Targets

These are engineering targets, not platform guarantees.

- **iOS Optimized**: target <50ms gap.
- **iOS Fallback**: target <500ms gap.
- **Android Fallback**: target <500ms gap.
- Measure gap using media timestamps where possible, not UI timing.

---

## Verification Strategy

### Test Policy

- Unit tests for API and method channel behavior.
- Integration tests for iOS optimized path when supported.
- Integration tests for iOS fallback path on non-MultiCam devices.
- Integration tests for Android fallback path.
- Device-required tests tagged for CI skipping.


### QA Principles

- Measure switching gap using timestamps where possible.
- Verify runtime path selection via logs.
- Verify final file validity and cleanup behavior.
- Verify long-recording behavior separately for fallback paths.

---

## Execution Strategy

### Parallel Waves

```text
Wave 1 (Foundation)
└── Task 1: API and state model

Wave 2 (Capability Layer)
└── Task 2: Runtime path detection and selection

Wave 3 (Platform implementations in parallel)
├── Task 3: iOS optimized no-merge path (MultiCam only)
├── Task 4: iOS fallback segment recording
├── Task 5: iOS fallback merge/export
├── Task 6: Android fallback segment recording
└── Task 7: Android fallback merge/export

Wave 4 (Integration)
├── Task 8: Method channel bindings
├── Task 9: Example app UI and logging
└── Task 10: Integration tests

Wave Final (Verification)
├── Task F1: Plan compliance audit
├── Task F2: Code quality review
├── Task F3: Manual QA on physical devices
└── Task F4: Scope fidelity check
```


---

## TODOs

- [x] 1. **Define Platform API and State Rules**

**What to do**:
    - Add `canSwitchCamera(int cameraId)` to platform interface.
    - Add `switchCamera(int cameraId)` to platform interface.
    - Add `canSwitchCurrentCamera` convenience getter.
    - Add `isSwitching` guard in Dart layer.
    - Standardize `CameraException('invalidState', ...)` and `CameraException('switchInProgress', ...)`.
    - Define one shared native error contract for switching failure.

**Must NOT do**:
    - Change existing public recording method signatures.
    - Add path-specific Dart APIs; path selection must stay internal.

**Acceptance Criteria**:
    - [x] All three API methods exist.
    - [x] Invalid-state and concurrent-switch errors are standardized.
    - [x] Existing public recording API remains backward compatible.

**QA Scenarios**:

```bash
grep -n "canSwitchCamera\|switchCamera\|canSwitchCurrentCamera" lib/waffle_camera_plugin_platform_interface.dart
flutter test test/ -t invalidState
flutter test test/ -t switchInProgress
```

**Commit**: YES
    - Message: `feat(interface): add camera switching APIs and state guards`

---

- [x] 2. **Implement Runtime Capability Detection and Path Selection**

**What to do**:
    - Create internal capability model: `iosOptimizedMultiCam`, `fallbackSegmentMerge`.
    - On iOS, detect `AVCaptureMultiCamSession.isMultiCamSupported`.
    - On Android, always select fallback path in v4.1.
    - Add future-facing Android concurrent verification helper using `CameraManager.getConcurrentCameraIds()` for v4.2 research.
    - Expose debug logs showing selected path.
    - Ensure all unsupported optimized cases fall back automatically before recording begins.

**Must NOT do**:
    - Attempt optimized path first and recover after partial camera setup.
    - Treat API level alone as proof of concurrent-camera support.
    - Expose Android optimized path as production-ready in v4.1.

**Acceptance Criteria**:
    - [x] Path selected before recording setup completes.
    - [x] Unsupported optimized path always falls back safely.
    - [x] Logs clearly show selected path.
    - [x] Android always uses fallback path in v4.1.

**QA Scenarios**:

```bash
# iOS supported device
# Expect: "Path selected: ios_multicam_optimized"

# iOS unsupported device
# Expect: "Path selected: fallback_segment_merge"

# Android any v4.1 device
# Expect: "Path selected: android_fallback_segment_merge"
```

**Commit**: YES
    - Message: `feat(core): add runtime path selection for camera switching`

---

- [ ] 3. **iOS Optimized No-Merge Path (MultiCam Only)**

**What to do**:
    - Use `AVCaptureMultiCamSession` only on supported devices.
    - Keep optimized implementation internal; no API changes.
    - Feed front and back camera pipelines into one continuous recording flow.
    - Switch active camera routing without ending the recording session.
    - Keep stop behavior lightweight with no switching-specific merge/export stage.
    - Verify timestamp continuity and output validity.

**Performance Targets**:
    - iOS Optimized: target <50ms gap.

**Must NOT do**:
    - Treat this as the default baseline for all iOS devices.
    - Remove fallback support.

**Acceptance Criteria**:
    - [ ] MultiCam path runs only on supported devices.
    - [ ] Switching works without segmented merge.
    - [ ] Stop time is materially faster than fallback path.
    - [ ] Final file is valid and playable.
    - [ ] Gap remains within target on test devices.

**QA Scenarios**:

```bash
# On iPhone XR or newer supporting MultiCam
# Start recording, switch twice, stop.
# Verify one output file and optimized path logs.
```

**Commit**: NO

---

- [ ] 4. **iOS Fallback Segment Recording**

**What to do**:
    - Implement segment-based recording for non-MultiCam devices.
    - Finish current segment, reconfigure to target camera, start next segment.
    - Preserve video orientation and audio settings across segments.
    - Track segment metadata needed for final merge.
    - Keep switch gap under the documented fallback tolerance.

**Performance Targets**:
    - iOS Fallback: target <500ms gap.

**Must NOT do**:
    - Require users to manage multiple files.
    - Break existing recording state transitions.

**Acceptance Criteria**:
    - [ ] Segments created correctly on unsupported devices.
    - [ ] Switching stays within fallback gap target.
    - [ ] Metadata captured for merge.

**QA Scenarios**:

```bash
# Record, switch once, verify segment_0 and segment_1 exist before stop merge.
```

**Commit**: NO

---

- [ ] 5. **iOS Fallback Merge and Cleanup**

**What to do**:
    - Merge fallback segments into one final file.
    - Return the merged file path from `stopRecording`.
    - Clean up intermediate segments on success and error.
    - Run merge work off the main thread.
    - Validate long-recording behavior on high quality presets.

**Must NOT do**:
    - Leave segment files after merge.
    - Block UI thread during export.

**Acceptance Criteria**:
    - [ ] One final merged file returned.
    - [ ] Cleanup works in success and failure paths.
    - [ ] Long fallback recordings complete without unbounded temp-file growth.

**QA Scenarios**:

```bash
# Record with 2 switches, stop, verify merged output exists and temp segments are deleted.
```

**Commit**: YES
    - Message: `feat(ios): add fallback segment recording and merge path for camera switching`

---

- [ ] 6. **Android Fallback Segment Recording**

**What to do**:
    - Implement segment-based recording for Android in v4.1.
    - Finish current segment, rebind/reconfigure target camera, start next segment.
    - Preserve orientation, audio config, and codec parameters across segments.
    - Capture merge metadata and timestamps.
    - Keep switch gap under the documented fallback tolerance.

**Performance Targets**:
    - Android Fallback: target <500ms gap.

**Must NOT do**:
    - Use optimized-path assumptions in fallback flow.
    - Change minSdk support.

**Acceptance Criteria**:
    - [ ] Segments created correctly on fallback devices.
    - [ ] Switching works with bounded gap.
    - [ ] Metadata captured for merge.

**QA Scenarios**:

```bash
# Record, switch, verify segment files exist before stop merge.
```

**Commit**: NO

---

- [ ] 7. **Android Fallback Merge and Cleanup**

**What to do**:
    - Merge fallback segments into one final MP4.
    - Normalize timestamps as needed for correct playback.
    - Clean up temporary files on success and failure.
    - Run merge off the main thread.
    - Validate longer recordings at higher quality settings.

**Must NOT do**:
    - Leave temporary files behind.
    - Block app responsiveness during finalize.

**Acceptance Criteria**:
    - [ ] Final merged file returned to Flutter.
    - [ ] Playback is correct after one or more switches.
    - [ ] Cleanup and failure handling work.

**QA Scenarios**:

```bash
# Record with 2 switches, stop, verify one final file and no leftover temp files.
```

**Commit**: YES
    - Message: `feat(android): add fallback segment recording and merge path for camera switching`

---

- [ ] 8. **Method Channel Bindings**

**What to do**:
    - Add handlers for `canSwitchCamera`, `canSwitchCurrentCamera`, and `switchCamera`.
    - Keep method channel API path-agnostic.
    - Propagate native errors as `CameraException`.
    - Add unit tests for new channel methods.

**Acceptance Criteria**:
    - [ ] All new APIs callable from Dart.
    - [ ] Errors propagated correctly.
    - [ ] Tests pass.

**Commit**: YES
    - Message: `feat(channel): add method channel bindings for camera switching`

---

- [ ] 9. **Example App UI and Logging**

**What to do**:
    - Add switch button visible only during recording.
    - Disable while `isSwitching` is true.
    - Show visual feedback during switch.
    - Add logs for selected runtime path, switch events, and finalize behavior.

**Acceptance Criteria**:
    - [ ] UI behaves correctly during recording and switching.
    - [ ] Logs identify optimized vs fallback path.
    - [ ] Playback confirms one final file.

**Commit**: YES
    - Message: `feat(example): add switch UI and path logging`

---

- [ ] 10. **Integration Tests**

**What to do**:
    - Add device-tagged integration tests.
    - Test iOS optimized path on devices that support it.
    - Test iOS fallback path on devices that do not.
    - Test Android fallback path.
    - Test invalid-state and concurrent-switch errors.
    - Test final file validity and cleanup.
    - Include at least one longer-recording regression scenario for each fallback path.

**Acceptance Criteria**:
    - [ ] Tests cover iOS optimized and both fallback paths.
    - [ ] Tests skip gracefully when required hardware is unavailable.
    - [ ] Negative cases pass.
    - [ ] Long-recording fallback regressions covered.

**Commit**: YES
    - Message: `test(integration): add camera switching integration coverage for optimized and fallback paths`

---

## Future Scope (v4.2)

### Android Optimized No-Merge Evaluation

This is intentionally **not** in v4.1 implementation scope.

**Research goals**:

- Validate whether devices reporting front/back concurrent support can support a production-ready low-gap switch flow for this plugin.
- Measure whether the latency improvement is meaningful versus Android fallback segment-merge.
- Confirm encoder, surface, and audio pipeline stability on target devices.

**Exit criteria before implementation**:

- Proven mechanism on at least two target Android device families.
- Stable long-recording behavior.
- Clear performance win over fallback path.
- No regression in output validity or crash rate.

---

## Final Verification Wave

- [ ] F1. **Plan Compliance Audit**
    - Verify runtime capability checks exist before optimized path selection.
    - Verify fallback path exists on both platforms.
    - Verify one final output file is returned in all supported flows.
- [ ] F2. **Code Quality Review**
    - Run `dart analyze`, `flutter test`, and platform-specific tests.
    - Review path selection, cleanup, and error handling.
- [ ] F3. **Manual QA on Physical Devices**
    - Test iOS optimized path on MultiCam-capable device.
    - Test iOS fallback path on non-MultiCam device.
    - Test Android fallback path on at least one device.
    - Run at least one long high-quality fallback recording per platform.
- [ ] F4. **Scope Fidelity Check**
    - Verify no scope creep.
    - Verify public API stayed path-agnostic.
    - Verify no unsupported universal camera assumptions remain.

---

## Commit Strategy

| Task | Commit | Message |
| :-- | :-- | :-- |
| 1 | YES | `feat(interface): add camera switching APIs and state guards` |
| 2 | YES | `feat(core): add runtime path selection for camera switching` |
| 3-5 | YES (Task 5) | `feat(ios): add optimized and fallback camera switching paths` |
| 6-7 | YES (Task 7) | `feat(android): add fallback camera switching path` |
| 8 | YES | `feat(channel): add method channel bindings for camera switching` |
| 9 | YES | `feat(example): add switch UI and path logging` |
| 10 | YES | `test(integration): add camera switching integration coverage for optimized and fallback paths` |


---

## Success Criteria

### Verification Commands

```bash
# Unit tests
flutter test

# Integration tests on supported devices
cd example && flutter test integration_test/ --tags requires_device

# Static analysis
dart analyze lib/
```


### Final Checklist

- [ ] Runtime capability detection works.
- [ ] iOS optimized path only runs on MultiCam-supported devices.
- [ ] iOS fallback path works on non-MultiCam devices.
- [ ] Android fallback path works reliably in v4.1.
- [ ] One final output file returned in all supported flows.
- [ ] No unsupported universal camera assumptions remain.
- [ ] Temporary files cleaned up correctly.
- [ ] Long-recording fallback scenarios validated.
