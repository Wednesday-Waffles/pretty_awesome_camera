# Android Tasks 6-7: Fallback Segment Recording and Merge - Implementation Complete

## Overview
Implemented Android fallback segment recording and merge path for camera switching during recording. This enables users to switch between front/back cameras with a single final output file.

## Changes Made

### 1. CameraInstance Data Class Enhancement
Added three new fields to track segment recording state:
- `segmentFiles: MutableList<File>` - List of segment files created during recording
- `currentSegmentIndex: Int` - Counter for segment numbering 
- `isSwitching: Boolean` - Guard to prevent concurrent switch operations

### 2. New Method Handlers in onMethodCall

#### `isMultiCamSupported` → Returns false
- Android v4.1 always uses fallback path
- No optimized multi-camera path in this release

#### `canSwitchCamera(cameraId)` → Boolean
- Returns true only if recording AND not already switching
- Validates camera exists, returns error if not

#### `switchCamera(cameraId)` → void
- Validates recording state and switching guard
- Workflow:
  1. Set `isSwitching = true`
  2. Stop current recording (segment N)
  3. Switch camera lens direction (front↔back)
  4. Unbind and rebind to opposite camera
  5. Start new recording segment (N+1)
  6. Set `isSwitching = false`
- Runs camera rebinding on main executor to respect lifecycle

#### `canSwitchCurrentCamera` → Boolean
- Convenience check: returns true if any camera is recording and can switch
- Used by Dart layer for UI state

### 3. Modified startRecording
- Now initializes segment tracking: `segmentFiles.clear()`, `currentSegmentIndex = 0`
- Creates first segment with timestamp-based naming: `segment_{timestamp}_0.mp4`
- Adds to segmentFiles list and increments index to 1

### 4. Rewritten stopRecording
- Stops current recording
- Three cases:
  1. **No segments** - Error "NO_RECORDING"
  2. **Single segment** - Return file path directly (no merge needed)
  3. **Multiple segments** - Launch merge on background IO thread
- Merge and cleanup run on `Dispatchers.IO` to avoid UI blocking
- Cleans up all segment files after success or error

### 5. mergeSegments(segmentFiles: List<File>): File
- Creates MediaMuxer with MPEG4 output format
- Two-pass approach:
  1. **Pass 1**: Extract tracks from all segments, add video/audio tracks to muxer
  2. **Pass 2**: Copy sample data from each track to muxer
- Key implementation details:
  - Adds tracks from first occurrence only (reuses same track index for subsequent segments)
  - Starts muxer only after all tracks added
  - Properly handles BufferInfo with timestamp, size, offset, flags
  - Exception handling: stops/releases muxer and deletes output file on error

### 6. copyTrack(extractor, muxer, trackIndex)
- Reads samples from MediaExtractor one at a time
- Reuses ByteBuffer allocation (256KB) for efficiency
- For each sample:
  - Reads sample data into buffer
  - Captures presentation time from extractor.sampleTime
  - Sets buffer metadata (size, offset, flags)
  - Writes to muxer with correct track index
  - Advances to next sample
- Exits when readSampleData returns < 0

### 7. cleanupSegmentFiles(segmentFiles: List<File>)
- Deletes all segment files from disk
- Silently catches exceptions to ensure cleanup completes
- Called on success and failure paths

## Error Handling

| Scenario | Error Code | Message |
|----------|-----------|---------|
| Camera not found | INVALID_CAMERA | "Camera not found" |
| Recording not active | NOT_RECORDING | "Camera not currently recording" |
| Switch already in progress | SWITCH_IN_PROGRESS | "Camera switch already in progress" |
| Activity unavailable | NO_ACTIVITY | "Activity not available" |
| Switch operation fails | SWITCH_ERROR | Exception message |
| No segments recorded | NO_RECORDING | "No recording segments found" |
| Merge fails | MERGE_ERROR | Exception message |
| Stop fails | STOP_ERROR | Exception message |

## Performance Characteristics

- **Switch gap**: Typically <500ms (target per plan)
  - Time includes: stop recording, camera rebind, start new segment
  - No merge during recording, only on stop
  
- **Merge performance**: Depends on segment count and file size
  - Runs on background thread (IO dispatcher) - non-blocking to UI
  - Linear time complexity with total video duration

## API Contract

- All public APIs remain backward compatible
- Path selection (fallback) is transparent to Dart layer
- Single output file returned to user in all cases
- Temporary segments cleaned up automatically

## Testing Considerations

1. Verify segment files created before merge
2. Test merge correctness with multiple switches
3. Validate timestamp continuity in final file
4. Test cleanup on error paths
5. Verify no temp files left after operation
6. Test long-duration recordings (multiple segments)

## Future Improvements (v4.2)

- Android optimized no-merge path using concurrent camera support
- Research CameraManager.getConcurrentCameraIds() for device capability detection
- Measure latency improvement over fallback path before implementing
