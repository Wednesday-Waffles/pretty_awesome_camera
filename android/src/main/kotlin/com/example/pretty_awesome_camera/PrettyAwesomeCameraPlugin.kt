package com.example.pretty_awesome_camera

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.SensorManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Range
import android.util.Size
import android.view.Surface
import android.view.OrientationEventListener
import androidx.annotation.OptIn
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalMirrorMode
import androidx.camera.core.MirrorMode
import androidx.camera.core.Preview
import androidx.camera.core.UseCaseGroup
import androidx.camera.core.resolutionselector.AspectRatioStrategy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.AudioStats
import androidx.camera.video.FallbackStrategy
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.ExperimentalPersistentRecording
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors

class PrettyAwesomeCameraPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private companion object {
        const val STOP_FINALIZE_TIMEOUT_MS = 10_000L
        const val TARGET_FRAME_RATE_FPS = 30

        // Sanity ceiling for caller-supplied encoder bitrates. CameraX clamps
        // the target into the encoder's supported range at runtime, but iOS
        // AVAssetWriter fails startWriting() on absurd values — both platforms
        // reject early with the same bound so behavior stays symmetric.
        const val MAX_VIDEO_BITRATE_BPS = 100_000_000

        // startRecording's MethodChannel result is held until CameraX emits
        // VideoRecordEvent.Start, giving Dart positive confirmation the
        // recorder engaged. This bounds how long Dart can be held.
        const val START_CONFIRM_TIMEOUT_MS = 5_000L

        // How long to wait for Bluetooth routing (setCommunicationDevice /
        // legacy SCO) to confirm before starting on the built-in mic anyway.
        // Never fail a recording for Bluetooth.
        const val BT_ROUTE_TIMEOUT_MS = 2_000L
    }

    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding? = null
    private val cameras = mutableMapOf<Int, CameraInstance>()
    private var nextCameraId = 0
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler: Handler by lazy { Handler(Looper.getMainLooper()) }
    private val eventChannels = mutableMapOf<Int, EventChannel>()
    private val streamHandlers = mutableMapOf<Int, RecordingStateStreamHandler>()
    private val audioEventChannels = mutableMapOf<Int, EventChannel>()
    private val audioStreamHandlers = mutableMapOf<Int, AudioDeviceStreamHandler>()
    private val audioLevelEventChannels = mutableMapOf<Int, EventChannel>()
    private val audioLevelStreamHandlers = mutableMapOf<Int, AudioLevelStreamHandler>()
    private var orientationListener: OrientationListener? = null

    data class PendingStop(
        val result: Result,
        val outputFile: File,
        val timeoutRunnable: Runnable
    )

    // Exactly-once holder for the startRecording result: completed by
    // VideoRecordEvent.Start (success), Finalize-before-Start (typed error),
    // dispose/detach (typed cancellation), or the confirm timeout. All
    // completion paths run on the main thread; completePendingStart() nulls
    // the holder first so a late Start after timeout is a no-op, never a
    // double-complete.
    data class PendingStart(
        val result: Result,
        val timeoutRunnable: Runnable,
        val requestedAtMs: Long
    )

    data class CompletedFinalize(
        val outputFile: File,
        val error: Int,
        val hasValidData: Boolean,
        val hasCause: Boolean
    )

    data class PendingDispose(
        val result: Result,
        val timeoutRunnable: Runnable
    )

    data class CameraInstance(
        val cameraId: Int,
        var cameraDescription: Map<String, Any>? = null,
        var resolutionPreset: String = "high",
        var videoBitrate: Int? = null,
        var textureEntry: TextureRegistry.SurfaceTextureEntry? = null,
        var camera: Camera? = null,
        var videoCapture: VideoCapture<Recorder>? = null,
        var preview: Preview? = null,
        var recording: Recording? = null,
        var recordingURL: String? = null,
        var isSwitching: Boolean = false,
        var isPaused: Boolean = false,
        var pendingPauseResult: Result? = null,
        var pendingResumeResult: Result? = null,
        var pendingStart: PendingStart? = null,
        var pendingStop: PendingStop? = null,
        var completedFinalize: CompletedFinalize? = null,
        var pendingDispose: PendingDispose? = null,
        var pauseCount: Int = 0,
        var resumeCount: Int = 0,
        var switchCount: Int = 0,
        // Bluetooth-mic routing (Phase 4). preferBluetoothMic comes from the
        // Dart CameraConfig (itself RC-gated app-side); btRouteEngaged tracks
        // whether we own a communication-device/SCO request that must be torn
        // down on every recording exit path.
        var preferBluetoothMic: Boolean = false,
        var btRouteEngaged: Boolean = false,
        var btRouteResult: String = "disabled"
    )

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "pretty_awesome_camera")
        channel.setMethodCallHandler(this)
        flutterPluginBinding = binding
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getAvailableCameras" -> getAvailableCameras(result)
            "createCamera" -> createCamera(call, result)
            "initializeCamera" -> initializeCamera(call, result)
            "disposeCamera" -> disposeCamera(call, result)
            "startRecording" -> startRecording(call, result)
            "getRecordingSettings" -> getRecordingSettings(call, result)
            "pauseRecording" -> pauseRecording(call, result)
            "resumeRecording" -> resumeRecording(call, result)
            "stopRecording" -> stopRecording(call, result)
            "setZoom" -> setZoom(call, result)
            "isMultiCamSupported" -> isMultiCamSupported(result)
            "canSwitchCamera" -> canSwitchCamera(call, result)
            "switchCamera" -> switchCamera(call, result)
            "canSwitchCurrentCamera" -> canSwitchCurrentCamera(result)
            "getBuildInfo" -> getBuildInfo(result)
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            else -> result.notImplemented()
        }
    }

    private fun getBuildInfo(result: Result) {
        result.success(
            mapOf(
                "platform" to "android",
                "pluginGitSha" to BuildConfig.PLUGIN_GIT_SHA,
                "cameraxVersion" to BuildConfig.CAMERAX_VERSION,
                "nativePauseResume" to true,
                "previewSwitch" to true,
                "persistentRecordingSwitch" to true
            )
        )
    }

    private fun getAvailableCameras(result: Result) {
        val activity = this.activity ?: run {
            result.error("NO_ACTIVITY", "Activity not available", null)
            return
        }
        
        try {
            val cameraManager = activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val camerasList = mutableListOf<Map<String, Any>>()
            
            for (cameraId in cameraManager.cameraIdList) {
                val characteristics = cameraManager.getCameraCharacteristics(cameraId)
                val lensFacing = characteristics.get(CameraCharacteristics.LENS_FACING)
                val orientation = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
                
                val lensDirection = when (lensFacing) {
                    CameraCharacteristics.LENS_FACING_FRONT -> "front"
                    CameraCharacteristics.LENS_FACING_BACK -> "back"
                    else -> "external"
                }
                
                camerasList.add(mapOf(
                    "name" to "Camera $cameraId",
                    "lensDirection" to lensDirection,
                    "sensorOrientation" to orientation
                ))
            }
            
            result.success(camerasList)
        } catch (e: Exception) {
            result.error("CAMERA_ERROR", e.message, null)
        }
    }

    private fun createCamera(call: MethodCall, result: Result) {
        val cameraDescription = call.argument<Map<String, Any>>("camera")
        
        if (cameraDescription == null) {
            result.error("INVALID_ARGUMENT", "Camera description is required", null)
            return
        }

        val resolutionPreset = call.argument<String>("preset") ?: "high"
        if (!isSupportedResolutionPreset(resolutionPreset)) {
            result.error("INVALID_ARGUMENT", "Unsupported resolution preset: $resolutionPreset", null)
            return
        }

        val videoBitrateValue = call.argument<Any>("videoBitrate")
        val videoBitrateLong = when (videoBitrateValue) {
            null -> null
            is Int -> videoBitrateValue.toLong()
            is Long -> videoBitrateValue
            else -> {
                result.error("INVALID_ARGUMENT", "videoBitrate must be an integer", null)
                return
            }
        }
        if (videoBitrateLong != null && videoBitrateLong <= 0) {
            result.error("INVALID_ARGUMENT", "videoBitrate must be greater than zero", null)
            return
        }
        if (videoBitrateLong != null && videoBitrateLong > MAX_VIDEO_BITRATE_BPS) {
            result.error("INVALID_ARGUMENT", "videoBitrate must be at most $MAX_VIDEO_BITRATE_BPS", null)
            return
        }
        val videoBitrate = videoBitrateLong?.toInt()
        val preferBluetoothMic = call.argument<Boolean>("preferBluetoothMic") ?: false

        val cameraId = nextCameraId++
        cameras[cameraId] = CameraInstance(
            cameraId = cameraId,
            cameraDescription = cameraDescription,
            resolutionPreset = resolutionPreset,
            videoBitrate = videoBitrate,
            preferBluetoothMic = preferBluetoothMic
        )

        result.success(cameraId)
    }

    private fun initializeCamera(call: MethodCall, result: Result) {
        val cameraId = call.argument<Int>("cameraId")
        val activity = this.activity ?: run {
            result.error("NO_ACTIVITY", "Activity not available", null)
            return
        }
        val binding = flutterPluginBinding ?: run {
            result.error("NO_BINDING", "Flutter plugin binding not available", null)
            return
        }
        
        val cameraInstance = cameras[cameraId]
        if (cameraInstance == null) {
            result.error("INVALID_CAMERA", "Camera not found", null)
            return
        }
        
        val cameraProviderFuture = ProcessCameraProvider.getInstance(activity)
        cameraProviderFuture.addListener({
            try {
                val cameraProvider = cameraProviderFuture.get()
                
                val lensDirection = cameraInstance.cameraDescription?.get("lensDirection") as? String
                val cameraSelector = when (lensDirection) {
                    "front" -> CameraSelector.DEFAULT_FRONT_CAMERA
                    else -> CameraSelector.DEFAULT_BACK_CAMERA
                }
                
                val textureEntry = binding.textureRegistry.createSurfaceTexture()
                cameraInstance.textureEntry = textureEntry

                val preview = buildPreview(cameraInstance)
                cameraInstance.preview = preview

                val recorder = buildRecorder(cameraInstance)
                val videoCapture = buildVideoCapture(recorder)
                cameraInstance.videoCapture = videoCapture

                val useCaseGroup = UseCaseGroup.Builder()
                    .addUseCase(preview)
                    .addUseCase(videoCapture)
                    .build()

                cameraProvider.unbindAll()
                val camera = cameraProvider.bindToLifecycle(
                    activity as LifecycleOwner,
                    cameraSelector,
                    useCaseGroup
                )

                preview.setSurfaceProvider(createSurfaceProvider(textureEntry))
                cameraInstance.camera = camera

                val actualCameraId = cameraId!!
                flutterPluginBinding?.let { pluginBinding ->
                    val stateChannel = EventChannel(
                        pluginBinding.binaryMessenger,
                        "pretty_awesome_camera/recording_state_${actualCameraId}"
                    )
                    val streamHandler = RecordingStateStreamHandler()
                    stateChannel.setStreamHandler(streamHandler)
                    eventChannels[actualCameraId] = stateChannel
                    streamHandlers[actualCameraId] = streamHandler

                    val audioChannel = EventChannel(
                        pluginBinding.binaryMessenger,
                        "pretty_awesome_camera/audio_device_${actualCameraId}"
                    )
                    val audioStreamHandler = AudioDeviceStreamHandler(activity.applicationContext)
                    audioChannel.setStreamHandler(audioStreamHandler)
                    audioEventChannels[actualCameraId] = audioChannel
                    audioStreamHandlers[actualCameraId] = audioStreamHandler

                    val audioLevelChannel = EventChannel(
                        pluginBinding.binaryMessenger,
                        "pretty_awesome_camera/audio_level_${actualCameraId}"
                    )
                    val audioLevelStreamHandler = AudioLevelStreamHandler()
                    audioLevelChannel.setStreamHandler(audioLevelStreamHandler)
                    audioLevelEventChannels[actualCameraId] = audioLevelChannel
                    audioLevelStreamHandlers[actualCameraId] = audioLevelStreamHandler
                }

                val textureId = textureEntry.id()
                result.success(
                    mapOf(
                        "textureId" to textureId,
                        "previewSize" to mapOf(
                            "width" to preview.resolutionInfo?.resolution?.width,
                            "height" to preview.resolutionInfo?.resolution?.height
                        )
                    )
                )
            } catch (e: Exception) {
                result.error("INIT_ERROR", e.message, null)
            }
        }, ContextCompat.getMainExecutor(activity))
    }

    private fun createSurfaceProvider(textureEntry: TextureRegistry.SurfaceTextureEntry): Preview.SurfaceProvider {
        return Preview.SurfaceProvider { request ->
            val resolution = request.resolution
            val surfaceTexture = textureEntry.surfaceTexture()
            surfaceTexture.setDefaultBufferSize(resolution.width, resolution.height)
            val surface = Surface(surfaceTexture)
            request.provideSurface(surface, executor) {
                surface.release()
            }
        }
    }

    private fun isSupportedResolutionPreset(preset: String): Boolean {
        return when (preset) {
            "low", "medium", "high", "veryHigh", "max" -> true
            else -> false
        }
    }

    private fun buildPreview(cameraInstance: CameraInstance): Preview {
        return Preview.Builder()
            .setResolutionSelector(resolutionSelectorForPreset(cameraInstance.resolutionPreset))
            .build()
    }

    private fun buildRecorder(cameraInstance: CameraInstance): Recorder {
        val builder = Recorder.Builder()
            .setExecutor(executor)
            .setQualitySelector(qualitySelectorForPreset(cameraInstance.resolutionPreset))

        cameraInstance.videoBitrate?.let { bitrate ->
            builder.setTargetVideoEncodingBitRate(bitrate)
        }

        return builder.build()
    }

    @OptIn(ExperimentalMirrorMode::class)
    private fun buildVideoCapture(recorder: Recorder): VideoCapture<Recorder> {
        return VideoCapture.Builder(recorder)
            .setMirrorMode(MirrorMode.MIRROR_MODE_ON_FRONT_ONLY)
            .setTargetFrameRate(Range(TARGET_FRAME_RATE_FPS, TARGET_FRAME_RATE_FPS))
            .build()
    }

    private fun getRecordingSettings(call: MethodCall, result: Result) {
        val cameraId = call.argument<Int>("cameraId")
        val cameraInstance = cameras[cameraId] ?: run {
            result.error("INVALID_CAMERA", "Camera not found or not initialized", null)
            return
        }
        // Best-effort snapshot: while the pipeline is (re)binding — e.g. during
        // a camera switch, when use cases are temporarily unbound — the video
        // use case has no resolved resolution yet. Report what is known instead
        // of erroring so callers never race the bind window.
        val resolution = cameraInstance.videoCapture?.resolutionInfo?.resolution

        result.success(
            mapOf(
                "requested_bitrate" to cameraInstance.videoBitrate,
                "resolved_resolution" to resolution?.let { "${it.width}x${it.height}" },
                "capture_preset" to cameraInstance.resolutionPreset
            )
        )
    }

    private fun qualitySelectorForPreset(preset: String): QualitySelector {
        val quality = when (preset) {
            "low" -> Quality.LOWEST
            "medium" -> Quality.SD
            "high" -> Quality.HD
            "veryHigh" -> Quality.FHD
            "max" -> Quality.UHD
            else -> Quality.HD
        }
        return QualitySelector.from(
            quality,
            FallbackStrategy.higherQualityOrLowerThan(quality)
        )
    }

    private fun resolutionSelectorForPreset(preset: String): ResolutionSelector {
        val resolutionStrategy = when (preset) {
            "low" -> boundedResolutionStrategy(Size(426, 240))
            "medium" -> boundedResolutionStrategy(Size(854, 480))
            "high" -> boundedResolutionStrategy(Size(1280, 720))
            "veryHigh" -> boundedResolutionStrategy(Size(1920, 1080))
            "max" -> ResolutionStrategy.HIGHEST_AVAILABLE_STRATEGY
            else -> boundedResolutionStrategy(Size(1280, 720))
        }

        return ResolutionSelector.Builder()
            .setAspectRatioStrategy(AspectRatioStrategy.RATIO_16_9_FALLBACK_AUTO_STRATEGY)
            .setResolutionStrategy(resolutionStrategy)
            .build()
    }

    private fun boundedResolutionStrategy(size: Size): ResolutionStrategy {
        return ResolutionStrategy(
            size,
            ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER
        )
    }

    private fun disposeCamera(call: MethodCall, result: Result) {
        val cameraId = call.argument<Int>("cameraId")
        val cameraInstance = cameras[cameraId] ?: run {
            result.success(null)
            return
        }
        val actualCameraId = cameraInstance.cameraId

        if (cameraInstance.pendingDispose != null) {
            result.error(
                "DISPOSE_IN_PROGRESS",
                "Camera dispose is already in progress",
                recordingDiagnostics(cameraInstance, "dispose_camera")
            )
            return
        }

        if (cameraInstance.pendingStop != null) {
            result.error(
                "STOP_IN_PROGRESS",
                "Recording stop is already in progress",
                recordingDiagnostics(cameraInstance, "dispose_camera")
            )
            return
        }

        if (cameraInstance.isSwitching) {
            result.error(
                "SWITCH_IN_PROGRESS",
                "Camera switch is already in progress",
                recordingDiagnostics(cameraInstance, "dispose_camera")
            )
            return
        }

        failPendingPauseResume(cameraInstance, "DISPOSED")
        failPendingStart(cameraInstance, "DISPOSED", "Camera disposed before start confirmation")

        val activeRecording = cameraInstance.recording
        if (activeRecording != null) {
            val timeoutRunnable = Runnable {
                if (cameraInstance.pendingDispose?.result == result) {
                    cameraInstance.pendingDispose = null
                    cameraInstance.recording = null
                    cameraInstance.recordingURL?.let { deleteQuietly(File(it)) }
                    cameraInstance.recordingURL = null
                    cameraInstance.isPaused = false
                    finishDisposeCamera(actualCameraId, cameraInstance, result)
                }
            }
            cameraInstance.pendingDispose = PendingDispose(result, timeoutRunnable)
            mainHandler.postDelayed(timeoutRunnable, STOP_FINALIZE_TIMEOUT_MS)
            try {
                activeRecording.stop()
                cameraInstance.recording = null
            } catch (_: Exception) {
                mainHandler.removeCallbacks(timeoutRunnable)
                cameraInstance.pendingDispose = null
                cameraInstance.recording = null
                cameraInstance.recordingURL?.let { deleteQuietly(File(it)) }
                cameraInstance.recordingURL = null
                cameraInstance.isPaused = false
                finishDisposeCamera(actualCameraId, cameraInstance, result)
            }
            return
        }

        finishDisposeCamera(actualCameraId, cameraInstance, result)
    }

    private fun finishDisposeCamera(cameraId: Int, cameraInstance: CameraInstance, result: Result) {
        teardownBluetoothRouting(cameraInstance)

        eventChannels[cameraId]?.setStreamHandler(null)
        eventChannels.remove(cameraId)
        streamHandlers.remove(cameraId)

        audioEventChannels[cameraId]?.setStreamHandler(null)
        audioEventChannels.remove(cameraId)
        audioStreamHandlers.remove(cameraId)?.dispose()

        audioLevelEventChannels[cameraId]?.setStreamHandler(null)
        audioLevelEventChannels.remove(cameraId)
        audioLevelStreamHandlers.remove(cameraId)

        val activity = this.activity
        if (activity != null && cameraInstance.camera != null) {
            val cameraProviderFuture = ProcessCameraProvider.getInstance(activity)
            cameraProviderFuture.addListener({
                try {
                    val cameraProvider = cameraProviderFuture.get()
                    cameraProvider.unbindAll()
                } catch (_: Exception) {}

                cameraInstance.textureEntry?.release()
                cameras.remove(cameraId)
                result.success(null)
            }, ContextCompat.getMainExecutor(activity))
        } else {
            cameraInstance.textureEntry?.release()
            cameras.remove(cameraId)
            result.success(null)
        }
    }

    private fun setZoom(call: MethodCall, result: Result) {
        val cameraId = call.argument<Int>("cameraId")
        val zoom = (call.argument<Any>("zoom") as? Number)?.toDouble()

        if (zoom == null) {
            result.error("INVALID_ARGUMENT", "Zoom factor is required", null)
            return
        }

        val cameraInstance = cameras[cameraId] ?: run {
            result.error("INVALID_CAMERA", "Camera not found", null)
            return
        }

        val camera = cameraInstance.camera ?: run {
            result.error("NOT_INITIALIZED", "Camera not initialized", null)
            return
        }

        val activity = this.activity ?: run {
            result.error("NO_ACTIVITY", "Activity not available", null)
            return
        }

        try {
            val zoomState = camera.cameraInfo.zoomState.value
            if (zoomState == null) {
                result.error("ZOOM_NOT_READY", "Zoom state not yet available", null)
                return
            }

            val minZoom = maxOf(1.0f, zoomState.minZoomRatio)
            val maxZoom = maxOf(
                minZoom,
                minOf(zoomState.maxZoomRatio, 8.0f)
            )
            val appliedZoom = zoom.toFloat().coerceIn(minZoom, maxZoom)
            val zoomFuture = camera.cameraControl.setZoomRatio(appliedZoom)

            zoomFuture.addListener({
                try {
                    zoomFuture.get()
                    result.success(appliedZoom.toDouble())
                } catch (e: ExecutionException) {
                    val cause = e.cause ?: e
                    result.error("ZOOM_ERROR", cause.message, null)
                } catch (e: Exception) {
                    result.error("ZOOM_ERROR", e.message, null)
                }
            }, ContextCompat.getMainExecutor(activity))
        } catch (e: Exception) {
            result.error("ZOOM_ERROR", e.message, null)
        }
    }

    private fun startRecording(call: MethodCall, result: Result) {
        val cameraId = call.argument<Int>("cameraId")
        val cameraInstance = cameras[cameraId] ?: run {
            result.error("INVALID_CAMERA", "Camera not found", null)
            return
        }
        val videoCapture = cameraInstance.videoCapture ?: run {
            result.error("NOT_INITIALIZED", "Camera not initialized", null)
            return
        }
        val activity = this.activity ?: run {
            result.error("NO_ACTIVITY", "Activity not available", null)
            return
        }

        if (cameraInstance.pendingDispose != null) {
            result.error(
                "DISPOSE_IN_PROGRESS",
                "Camera dispose is already in progress",
                recordingDiagnostics(cameraInstance, "start_recording")
            )
            return
        }

        if (cameraInstance.pendingStart != null) {
            result.error(
                "START_IN_PROGRESS",
                "Recording start is already in progress",
                recordingDiagnostics(cameraInstance, "start_recording")
            )
            return
        }

        if (
            cameraInstance.recording != null ||
            cameraInstance.pendingStop != null ||
            cameraInstance.completedFinalize != null
        ) {
            result.error(
                "RECORDING_IN_PROGRESS",
                "Camera is already recording",
                recordingDiagnostics(cameraInstance, "start_recording")
            )
            return
        }

        resetRecordingState(cameraInstance)

        if (cameraInstance.preferBluetoothMic) {
            engageBluetoothRouting(cameraInstance, activity) { routeResult ->
                cameraInstance.btRouteResult = routeResult
                startRecordingInternal(cameraInstance, videoCapture, activity, result)
            }
        } else {
            cameraInstance.btRouteResult = "disabled"
            startRecordingInternal(cameraInstance, videoCapture, activity, result)
        }
    }

    @OptIn(ExperimentalPersistentRecording::class)
    private fun startRecordingInternal(
        cameraInstance: CameraInstance,
        videoCapture: VideoCapture<Recorder>,
        activity: Activity,
        result: Result
    ) {
        try {
            // UUID, not epoch millis: two recordings in the same clock tick
            // must never overwrite each other (matches iOS).
            val file = File(activity.cacheDir, "recording_${UUID.randomUUID()}.mp4")
            cameraInstance.recordingURL = file.absolutePath

            val outputOptions = FileOutputOptions.Builder(file).build()

            val rotation = orientationListener?.getRotation() ?: Surface.ROTATION_0
            videoCapture.targetRotation = rotation

            // Hold the MethodChannel result until VideoRecordEvent.Start so
            // Dart gets positive confirmation the recorder engaged (previously
            // start-failures only surfaced as delayed spontaneous finalizes).
            val requestedAtMs = SystemClock.uptimeMillis()
            val timeoutRunnable = Runnable {
                val pendingStart = cameraInstance.pendingStart ?: return@Runnable
                cameraInstance.pendingStart = null
                teardownBluetoothRouting(cameraInstance)
                try {
                    cameraInstance.recording?.stop()
                } catch (_: Exception) {
                }
                cameraInstance.recording = null
                cameraInstance.recordingURL?.let { deleteQuietly(File(it)) }
                cameraInstance.recordingURL = null
                cameraInstance.isPaused = false
                pendingStart.result.error(
                    "START_TIMEOUT",
                    "Timed out waiting for CameraX to confirm recording start",
                    recordingDiagnostics(cameraInstance, "start_confirm_timeout")
                )
            }
            cameraInstance.pendingStart = PendingStart(result, timeoutRunnable, requestedAtMs)
            mainHandler.postDelayed(timeoutRunnable, START_CONFIRM_TIMEOUT_MS)

            val recording = videoCapture.output
                .prepareRecording(activity, outputOptions)
                .withAudioEnabled()
                .asPersistentRecording()
                .start(ContextCompat.getMainExecutor(activity)) { event ->
                    when (event) {
                        is VideoRecordEvent.Start -> completeStart(cameraInstance)
                        is VideoRecordEvent.Status -> handleStatus(cameraInstance, event)
                        is VideoRecordEvent.Pause -> completePause(cameraInstance)
                        is VideoRecordEvent.Resume -> completeResume(cameraInstance)
                        is VideoRecordEvent.Finalize -> handleFinalize(cameraInstance, event)
                        else -> {}
                    }
                }

            cameraInstance.recording = recording
        } catch (e: Exception) {
            val pendingStart = cameraInstance.pendingStart
            cameraInstance.pendingStart = null
            pendingStart?.let { mainHandler.removeCallbacks(it.timeoutRunnable) }
            teardownBluetoothRouting(cameraInstance)
            resetRecordingState(cameraInstance)
            result.error(
                "RECORDING_ERROR",
                e.message,
                recordingDiagnostics(cameraInstance, "start_recording")
            )
        }
    }

    private fun completeStart(cameraInstance: CameraInstance) {
        // Late Start after timeout (or any other terminal path) — no-op.
        val pendingStart = cameraInstance.pendingStart ?: return
        mainHandler.removeCallbacks(pendingStart.timeoutRunnable)
        cameraInstance.pendingStart = null

        // Ground truth for Bluetooth capture: the communication-device request
        // only proves the *request* was honored. What the active recording is
        // actually capturing from comes from AudioRecordingConfiguration.
        val activeDevice = AudioDeviceIntrospection.activeRecordingInputDevice(audioManagerOrNull())
        val availableDevice = AudioDeviceIntrospection.preferredInputDevice(audioManagerOrNull())
        val activeIsBluetooth = AudioDeviceIntrospection.isBluetoothDevice(activeDevice)
        if (cameraInstance.btRouteEngaged && cameraInstance.btRouteResult == "granted") {
            cameraInstance.btRouteResult =
                if (activeIsBluetooth) "active" else "request_honored_capture_builtin"
        }

        val reportedDevice = activeDevice ?: availableDevice
        pendingStart.result.success(
            mapOf(
                "audioPortType" to AudioDeviceIntrospection.typeName(reportedDevice?.type),
                "audioDeviceName" to AudioDeviceIntrospection.deviceName(reportedDevice),
                "isBluetoothInput" to activeIsBluetooth,
                "isBluetoothAvailable" to AudioDeviceIntrospection.isBluetoothDevice(availableDevice),
                "btRouteResult" to cameraInstance.btRouteResult,
                "engagementElapsedMs" to (SystemClock.uptimeMillis() - pendingStart.requestedAtMs)
            )
        )
    }

    private fun failPendingStart(cameraInstance: CameraInstance, code: String, message: String) {
        val pendingStart = cameraInstance.pendingStart ?: return
        mainHandler.removeCallbacks(pendingStart.timeoutRunnable)
        cameraInstance.pendingStart = null
        pendingStart.result.error(
            code,
            message,
            recordingDiagnostics(cameraInstance, "start_recording")
        )
    }

    private fun handleStatus(cameraInstance: CameraInstance, event: VideoRecordEvent.Status) {
        val handler = audioLevelStreamHandlers[cameraInstance.cameraId] ?: return
        val audioStats = event.recordingStats.audioStats
        handler.send(
            mapOf(
                "amplitude" to audioStats.audioAmplitude,
                "audioState" to audioStateName(audioStats.audioState),
                // Monotonic clock — the Dart side uses this for staleness
                // detection across the stream.
                "timestampMs" to SystemClock.uptimeMillis()
            )
        )
    }

    private fun audioStateName(state: Int): String {
        return when (state) {
            AudioStats.AUDIO_STATE_ACTIVE -> "active"
            AudioStats.AUDIO_STATE_DISABLED -> "disabled"
            AudioStats.AUDIO_STATE_MUTED -> "muted"
            AudioStats.AUDIO_STATE_SOURCE_SILENCED -> "sourceSilenced"
            AudioStats.AUDIO_STATE_ENCODER_ERROR -> "encoderError"
            AudioStats.AUDIO_STATE_SOURCE_ERROR -> "sourceError"
            else -> "unknown"
        }
    }

    private fun audioManagerOrNull(): AudioManager? {
        // Fall back to the application context so Bluetooth-routing teardown
        // still works after the activity has detached (engine teardown).
        val context: Context? = activity ?: flutterPluginBinding?.applicationContext
        return context?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
    }

    /**
     * Requests Bluetooth-mic routing before the recording starts, then always
     * calls [onComplete] with a route result — never fails the recording for
     * Bluetooth. API 31+ uses setCommunicationDevice with a device taken from
     * getAvailableCommunicationDevices() (the only valid arguments per the
     * AudioManager contract); older APIs use legacy SCO with an
     * ACTION_SCO_AUDIO_STATE_UPDATED confirmation. Both paths are bounded by
     * BT_ROUTE_TIMEOUT_MS.
     */
    private fun engageBluetoothRouting(
        cameraInstance: CameraInstance,
        activity: Activity,
        onComplete: (String) -> Unit
    ) {
        val audioManager = activity.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        if (audioManager == null) {
            onComplete("unavailable")
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val target = audioManager.availableCommunicationDevices.firstOrNull {
                AudioDeviceIntrospection.isBluetoothDevice(it)
            }
            if (target == null) {
                onComplete("unavailable")
                return
            }

            var finished = false
            var listenerHolder: AudioManager.OnCommunicationDeviceChangedListener? = null
            val finish: (String) -> Unit = { routeResult ->
                if (!finished) {
                    finished = true
                    listenerHolder?.let {
                        audioManager.removeOnCommunicationDeviceChangedListener(it)
                    }
                    onComplete(routeResult)
                }
            }
            val timeoutRunnable = Runnable {
                if (!finished) {
                    try {
                        audioManager.clearCommunicationDevice()
                    } catch (_: Exception) {
                    }
                    cameraInstance.btRouteEngaged = false
                    finish("timeout")
                }
            }
            val listener = AudioManager.OnCommunicationDeviceChangedListener { device ->
                if (device != null && device.id == target.id) {
                    mainHandler.removeCallbacks(timeoutRunnable)
                    finish("granted")
                }
            }
            listenerHolder = listener

            try {
                audioManager.addOnCommunicationDeviceChangedListener(
                    ContextCompat.getMainExecutor(activity),
                    listener
                )
                val accepted = audioManager.setCommunicationDevice(target)
                if (!accepted) {
                    finish("rejected")
                    return
                }
                cameraInstance.btRouteEngaged = true
                // The request may have been applied synchronously.
                if (audioManager.communicationDevice?.id == target.id) {
                    finish("granted")
                    return
                }
                mainHandler.postDelayed(timeoutRunnable, BT_ROUTE_TIMEOUT_MS)
            } catch (_: Exception) {
                cameraInstance.btRouteEngaged = false
                finish("rejected")
            }
            return
        }

        // Legacy SCO path (API < 31; <5% of fleet). Best-effort with an
        // ACTION_SCO_AUDIO_STATE_UPDATED confirmation.
        val hasBluetoothInput = AudioDeviceIntrospection.isBluetoothDevice(
            AudioDeviceIntrospection.preferredInputDevice(audioManager)
        )
        if (!hasBluetoothInput) {
            onComplete("unavailable")
            return
        }

        var finished = false
        var receiverHolder: BroadcastReceiver? = null
        val finish: (String) -> Unit = { routeResult ->
            if (!finished) {
                finished = true
                receiverHolder?.let {
                    try {
                        activity.unregisterReceiver(it)
                    } catch (_: Exception) {
                    }
                }
                onComplete(routeResult)
            }
        }
        val timeoutRunnable = Runnable {
            if (!finished) {
                try {
                    audioManager.stopBluetoothSco()
                    audioManager.isBluetoothScoOn = false
                } catch (_: Exception) {
                }
                cameraInstance.btRouteEngaged = false
                finish("timeout")
            }
        }
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val state = intent?.getIntExtra(
                    AudioManager.EXTRA_SCO_AUDIO_STATE,
                    AudioManager.SCO_AUDIO_STATE_ERROR
                ) ?: AudioManager.SCO_AUDIO_STATE_ERROR
                if (state == AudioManager.SCO_AUDIO_STATE_CONNECTED) {
                    mainHandler.removeCallbacks(timeoutRunnable)
                    finish("granted")
                }
            }
        }
        receiverHolder = receiver

        try {
            activity.registerReceiver(
                receiver,
                IntentFilter(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED)
            )
            audioManager.startBluetoothSco()
            audioManager.isBluetoothScoOn = true
            cameraInstance.btRouteEngaged = true
            mainHandler.postDelayed(timeoutRunnable, BT_ROUTE_TIMEOUT_MS)
        } catch (_: Exception) {
            cameraInstance.btRouteEngaged = false
            finish("rejected")
        }
    }

    /**
     * Releases any communication-device/SCO request this plugin owns. Called
     * on every recording exit path (stop finalize, stop timeout, spontaneous
     * finalize, dispose, start failure, engine/activity detach). Idempotent.
     */
    private fun teardownBluetoothRouting(cameraInstance: CameraInstance) {
        if (!cameraInstance.btRouteEngaged) {
            return
        }
        cameraInstance.btRouteEngaged = false
        val audioManager = audioManagerOrNull() ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                audioManager.clearCommunicationDevice()
            } else {
                audioManager.stopBluetoothSco()
                audioManager.isBluetoothScoOn = false
            }
        } catch (_: Exception) {
        }
    }

    private fun pauseRecording(call: MethodCall, result: Result) {
        val cameraId = call.argument<Int>("cameraId")
        val cameraInstance = cameras[cameraId] ?: run {
            result.error("INVALID_CAMERA", "Camera not found", null)
            return
        }

        if (cameraInstance.pendingDispose != null) {
            result.error(
                "DISPOSE_IN_PROGRESS",
                "Camera dispose is already in progress",
                recordingDiagnostics(cameraInstance, "pause_recording")
            )
            return
        }

        if (cameraInstance.pendingStop != null) {
            result.error(
                "STOP_IN_PROGRESS",
                "Recording stop is already in progress",
                recordingDiagnostics(cameraInstance, "pause_recording")
            )
            return
        }

        if (cameraInstance.pendingStart != null) {
            result.error(
                "START_IN_PROGRESS",
                "Recording start is not confirmed yet",
                recordingDiagnostics(cameraInstance, "pause_recording")
            )
            return
        }

        if (cameraInstance.isSwitching) {
            result.error(
                "SWITCH_IN_PROGRESS",
                "Camera switch is already in progress",
                recordingDiagnostics(cameraInstance, "pause_recording")
            )
            return
        }

        if (cameraInstance.recording == null) {
            result.error(
                "NOT_RECORDING",
                "No active recording",
                recordingDiagnostics(cameraInstance, "pause_recording")
            )
            return
        }

        if (cameraInstance.pendingPauseResult != null) {
            result.error(
                "PAUSE_IN_PROGRESS",
                "Recording pause is already in progress",
                recordingDiagnostics(cameraInstance, "pause_recording")
            )
            return
        }

        if (cameraInstance.pendingResumeResult != null) {
            result.error(
                "RESUME_IN_PROGRESS",
                "Recording resume is already in progress",
                recordingDiagnostics(cameraInstance, "pause_recording")
            )
            return
        }

        if (cameraInstance.isPaused) {
            result.success(null)
            return
        }

        try {
            cameraInstance.pendingPauseResult = result
            cameraInstance.recording!!.pause()
        } catch (e: Exception) {
            cameraInstance.pendingPauseResult = null
            result.error(
                "PAUSE_ERROR",
                e.message,
                recordingDiagnostics(cameraInstance, "pause_recording")
            )
        }
    }

    private fun resumeRecording(call: MethodCall, result: Result) {
        val cameraId = call.argument<Int>("cameraId")
        val cameraInstance = cameras[cameraId] ?: run {
            result.error("INVALID_CAMERA", "Camera not found", null)
            return
        }

        if (cameraInstance.pendingDispose != null) {
            result.error(
                "DISPOSE_IN_PROGRESS",
                "Camera dispose is already in progress",
                recordingDiagnostics(cameraInstance, "resume_recording")
            )
            return
        }

        if (cameraInstance.pendingStop != null) {
            result.error(
                "STOP_IN_PROGRESS",
                "Recording stop is already in progress",
                recordingDiagnostics(cameraInstance, "resume_recording")
            )
            return
        }

        if (cameraInstance.pendingStart != null) {
            result.error(
                "START_IN_PROGRESS",
                "Recording start is not confirmed yet",
                recordingDiagnostics(cameraInstance, "resume_recording")
            )
            return
        }

        if (cameraInstance.isSwitching) {
            result.error(
                "SWITCH_IN_PROGRESS",
                "Camera switch is already in progress",
                recordingDiagnostics(cameraInstance, "resume_recording")
            )
            return
        }

        if (cameraInstance.recording == null) {
            result.error(
                "NOT_RECORDING",
                "No active recording",
                recordingDiagnostics(cameraInstance, "resume_recording")
            )
            return
        }

        if (cameraInstance.pendingResumeResult != null) {
            result.error(
                "RESUME_IN_PROGRESS",
                "Recording resume is already in progress",
                recordingDiagnostics(cameraInstance, "resume_recording")
            )
            return
        }

        if (cameraInstance.pendingPauseResult != null) {
            result.error(
                "PAUSE_IN_PROGRESS",
                "Recording pause is already in progress",
                recordingDiagnostics(cameraInstance, "resume_recording")
            )
            return
        }

        if (!cameraInstance.isPaused) {
            result.error(
                "NOT_PAUSED",
                "Recording is not paused",
                recordingDiagnostics(cameraInstance, "resume_recording")
            )
            return
        }

        try {
            cameraInstance.pendingResumeResult = result
            cameraInstance.recording!!.resume()
        } catch (e: Exception) {
            cameraInstance.pendingResumeResult = null
            result.error(
                "RESUME_ERROR",
                e.message,
                recordingDiagnostics(cameraInstance, "resume_recording")
            )
        }
    }

    private fun stopRecording(call: MethodCall, result: Result) {
        val cameraId = call.argument<Int>("cameraId")
        val cameraInstance = cameras[cameraId] ?: run {
            result.error("INVALID_CAMERA", "Camera not found", null)
            return
        }

        if (cameraInstance.pendingDispose != null) {
            result.error(
                "DISPOSE_IN_PROGRESS",
                "Camera dispose is already in progress",
                recordingDiagnostics(cameraInstance, "stop_recording")
            )
            return
        }

        if (cameraInstance.isSwitching) {
            result.error(
                "SWITCH_IN_PROGRESS",
                "Camera switch is already in progress",
                recordingDiagnostics(cameraInstance, "stop_recording")
            )
            return
        }

        if (cameraInstance.pendingStop != null) {
            result.error(
                "STOP_IN_PROGRESS",
                "Recording stop is already in progress",
                recordingDiagnostics(cameraInstance, "stop_recording")
            )
            return
        }

        if (cameraInstance.pendingStart != null) {
            result.error(
                "START_IN_PROGRESS",
                "Recording start is not confirmed yet",
                recordingDiagnostics(cameraInstance, "stop_recording")
            )
            return
        }

        cameraInstance.completedFinalize?.let { completedFinalize ->
            completeStopFromFinalize(
                cameraInstance = cameraInstance,
                result = result,
                outputFile = completedFinalize.outputFile,
                finalizeError = completedFinalize.error,
                hasValidData = completedFinalize.hasValidData,
                hasCause = completedFinalize.hasCause,
                stage = "stop_after_finalize"
            )
            return
        }

        val recording = cameraInstance.recording ?: run {
            result.error(
                "NO_RECORDING",
                "No active recording",
                recordingDiagnostics(cameraInstance, "stop_recording")
            )
            return
        }

        val outputFile = cameraInstance.recordingURL
            ?.takeIf { it.isNotEmpty() }
            ?.let { File(it) }
        if (outputFile == null) {
            result.error(
                "STOP_OUTPUT_MISSING",
                "Recording output path is missing",
                recordingDiagnostics(cameraInstance, "stop_recording")
            )
            return
        }

        val timeoutRunnable = Runnable {
            if (cameraInstance.pendingStop?.result == result) {
                val outputExists = outputFile.exists()
                val outputHasData = outputFileHasData(outputFile)
                cameraInstance.pendingStop = null
                failPendingPauseResume(cameraInstance, RecordingFinalizeContract.STOP_TIMEOUT)
                teardownBluetoothRouting(cameraInstance)
                cameraInstance.recording = null
                // The stop already failed to Dart — a file nobody will consume
                // must not linger in cacheDir (a late finalize caches nothing
                // once recordingURL is null).
                deleteQuietly(outputFile)
                cameraInstance.recordingURL = null
                cameraInstance.isPaused = false
                result.error(
                    RecordingFinalizeContract.STOP_TIMEOUT,
                    "Timed out waiting for CameraX finalize",
                    recordingDiagnostics(
                        cameraInstance,
                        "stop_finalize_timeout",
                        mapOf(
                            "native_output_exists" to outputExists,
                            "native_output_has_data" to outputHasData
                        )
                    )
                )
            }
        }

        cameraInstance.pendingStop = PendingStop(result, outputFile, timeoutRunnable)
        mainHandler.postDelayed(timeoutRunnable, STOP_FINALIZE_TIMEOUT_MS)

        try {
            recording.stop()
            cameraInstance.recording = null
        } catch (e: Exception) {
            mainHandler.removeCallbacks(timeoutRunnable)
            cameraInstance.pendingStop = null
            cameraInstance.recording = null
            cameraInstance.recordingURL = null
            cameraInstance.isPaused = false
            deleteQuietly(outputFile)
            result.error(
                "STOP_ERROR",
                e.message,
                recordingDiagnostics(cameraInstance, "stop_recording")
            )
        }
    }

    private fun completePause(cameraInstance: CameraInstance) {
        cameraInstance.isPaused = true
        cameraInstance.pauseCount += 1
        cameraInstance.pendingPauseResult?.success(null)
        cameraInstance.pendingPauseResult = null
    }

    private fun completeResume(cameraInstance: CameraInstance) {
        cameraInstance.isPaused = false
        cameraInstance.resumeCount += 1
        cameraInstance.pendingResumeResult?.success(null)
        cameraInstance.pendingResumeResult = null
    }

    private fun handleFinalize(
        cameraInstance: CameraInstance,
        event: VideoRecordEvent.Finalize
    ) {
        teardownBluetoothRouting(cameraInstance)

        cameraInstance.pendingDispose?.let { pendingDispose ->
            mainHandler.removeCallbacks(pendingDispose.timeoutRunnable)
            cameraInstance.pendingDispose = null
            cameraInstance.recordingURL?.let { deleteQuietly(File(it)) }
            cameraInstance.recording = null
            cameraInstance.recordingURL = null
            cameraInstance.isPaused = false
            finishDisposeCamera(cameraInstance.cameraId, cameraInstance, pendingDispose.result)
            return
        }

        // Finalize-before-Start: the recording died before ever engaging. The
        // held start result resolves immediately with a typed error instead of
        // waiting out the confirm timeout.
        cameraInstance.pendingStart?.let { pendingStart ->
            mainHandler.removeCallbacks(pendingStart.timeoutRunnable)
            cameraInstance.pendingStart = null
            val finalizeErrorName = RecordingFinalizeContract.errorName(event.error)
            cameraInstance.recordingURL?.let { deleteQuietly(File(it)) }
            cameraInstance.recording = null
            cameraInstance.recordingURL = null
            cameraInstance.isPaused = false
            pendingStart.result.error(
                "START_FAILED",
                "Recording finalized before start confirmation ($finalizeErrorName)",
                recordingDiagnostics(
                    cameraInstance,
                    "finalize_before_start",
                    mapOf(
                        "native_finalize_code" to event.error,
                        "native_finalize_error" to finalizeErrorName
                    )
                )
            )
            return
        }

        val pendingStop = cameraInstance.pendingStop ?: run {
            cacheSpontaneousFinalize(cameraInstance, event)
            return
        }
        mainHandler.removeCallbacks(pendingStop.timeoutRunnable)
        cameraInstance.pendingStop = null
        failPendingPauseResume(cameraInstance, RecordingFinalizeContract.STOP_FINALIZED)

        completeStopFromFinalize(
            cameraInstance = cameraInstance,
            result = pendingStop.result,
            outputFile = pendingStop.outputFile,
            finalizeError = event.error,
            hasValidData = outputHasValidData(event, pendingStop.outputFile),
            hasCause = event.cause != null,
            stage = "stop_finalize"
        )
    }

    private fun cacheSpontaneousFinalize(
        cameraInstance: CameraInstance,
        event: VideoRecordEvent.Finalize
    ) {
        val outputFile = cameraInstance.recordingURL
            ?.takeIf { it.isNotEmpty() }
            ?.let { File(it) }
        if (outputFile != null) {
            cameraInstance.completedFinalize = CompletedFinalize(
                outputFile = outputFile,
                error = event.error,
                hasValidData = outputHasValidData(event, outputFile),
                hasCause = event.cause != null
            )
        }
        failPendingPauseResume(cameraInstance, RecordingFinalizeContract.STOP_FINALIZED)
        cameraInstance.recording = null
        cameraInstance.recordingURL = null
        cameraInstance.isPaused = false
    }

    private fun completeStopFromFinalize(
        cameraInstance: CameraInstance,
        result: Result,
        outputFile: File,
        finalizeError: Int,
        hasValidData: Boolean,
        hasCause: Boolean,
        stage: String
    ) {
        val decision = RecordingFinalizeContract.decide(finalizeError, hasValidData)
        val details = recordingDiagnostics(
            cameraInstance,
            stage,
            mapOf(
                "native_finalize_code" to finalizeError,
                "native_finalize_error" to RecordingFinalizeContract.errorName(finalizeError),
                "native_output_has_data" to hasValidData,
                "native_has_cause" to hasCause
            )
        )

        cameraInstance.recording = null
        cameraInstance.recordingURL = null
        cameraInstance.completedFinalize = null
        cameraInstance.isPaused = false

        when (decision.action) {
            FinalizeAction.RETURN_PATH -> result.success(outputFile.absolutePath)
            FinalizeAction.RETURN_NULL -> {
                if (decision.deletePartial) {
                    deleteQuietly(outputFile)
                }
                result.success(null)
            }
            FinalizeAction.THROW_ERROR -> {
                if (decision.deletePartial) {
                    deleteQuietly(outputFile)
                }
                result.error(
                    decision.errorCode ?: "STOP_FINALIZE_ERROR",
                    decision.message ?: "CameraX failed to finalize recording",
                    details
                )
            }
        }
    }

    private fun failPendingPauseResume(cameraInstance: CameraInstance, code: String) {
        cameraInstance.pendingPauseResult?.error(
            code,
            "Recording stopped before pause completed",
            recordingDiagnostics(cameraInstance, "pause_recording")
        )
        cameraInstance.pendingPauseResult = null
        cameraInstance.pendingResumeResult?.error(
            code,
            "Recording stopped before resume completed",
            recordingDiagnostics(cameraInstance, "resume_recording")
        )
        cameraInstance.pendingResumeResult = null
    }

    private fun resetRecordingState(cameraInstance: CameraInstance) {
        cameraInstance.recording = null
        cameraInstance.recordingURL = null
        cameraInstance.isSwitching = false
        cameraInstance.isPaused = false
        cameraInstance.pendingPauseResult = null
        cameraInstance.pendingResumeResult = null
        cameraInstance.pendingStart = null
        cameraInstance.pendingStop = null
        cameraInstance.completedFinalize = null
        cameraInstance.pendingDispose = null
        cameraInstance.pauseCount = 0
        cameraInstance.resumeCount = 0
        cameraInstance.switchCount = 0
        cameraInstance.btRouteResult = "disabled"
    }

    private fun outputFileHasData(file: File): Boolean = file.exists() && file.length() > 0L

    private fun outputHasValidData(event: VideoRecordEvent.Finalize, file: File): Boolean {
        val stats = event.recordingStats
        return RecordingFinalizeContract.hasValidData(
            outputExists = file.exists(),
            outputLengthBytes = file.length(),
            recordedBytes = stats.numBytesRecorded,
            recordedDurationNanos = stats.recordedDurationNanos
        )
    }

    private fun deleteQuietly(file: File) {
        try {
            if (file.exists()) {
                file.delete()
            }
        } catch (_: Exception) {
        }
    }

    private fun recordingDiagnostics(
        cameraInstance: CameraInstance,
        stage: String,
        extra: Map<String, Any?> = emptyMap()
    ): Map<String, Any?> {
        val audioManager = audioManagerOrNull()
        val inputDevice = AudioDeviceIntrospection.activeRecordingInputDevice(audioManager)
            ?: AudioDeviceIntrospection.preferredInputDevice(audioManager)
        return mapOf(
            "native_stage" to stage,
            "native_has_recording" to (cameraInstance.recording != null),
            "native_has_pending_start" to (cameraInstance.pendingStart != null),
            "native_has_pending_stop" to (cameraInstance.pendingStop != null),
            "native_has_completed_finalize" to (cameraInstance.completedFinalize != null),
            "native_has_pending_dispose" to (cameraInstance.pendingDispose != null),
            "native_is_paused" to cameraInstance.isPaused,
            "native_is_switching" to cameraInstance.isSwitching,
            "native_audio_device_type" to AudioDeviceIntrospection.typeName(inputDevice?.type),
            "native_bt_route_result" to cameraInstance.btRouteResult,
            "native_pause_count" to cameraInstance.pauseCount,
            "native_resume_count" to cameraInstance.resumeCount,
            "native_switch_count" to cameraInstance.switchCount
        ) + extra
    }

    private fun isMultiCamSupported(result: Result) {
        result.success(false)
    }

    private fun canSwitchCamera(call: MethodCall, result: Result) {
        val cameraId = call.argument<Int>("cameraId")
        val cameraInstance = cameras[cameraId]
        if (cameraInstance == null) {
            result.error("INVALID_CAMERA", "Camera not found", null)
            return
        }

        result.success(canSwitchCameraInstance(cameraInstance))
    }

    private fun canSwitchCurrentCamera(result: Result) {
        result.success(cameras.values.any { canSwitchCameraInstance(it) })
    }

    private fun switchCamera(call: MethodCall, result: Result) {
        val cameraId = call.argument<Int>("cameraId")
        val cameraInstance = cameras[cameraId] ?: run {
            result.error("INVALID_CAMERA", "Camera not found", null)
            return
        }

        if (cameraInstance.pendingDispose != null) {
            result.error(
                "DISPOSE_IN_PROGRESS",
                "Camera dispose is already in progress",
                recordingDiagnostics(cameraInstance, "switch_camera")
            )
            return
        }

        if (cameraInstance.pendingStop != null) {
            result.error(
                "STOP_IN_PROGRESS",
                "Recording stop is already in progress",
                recordingDiagnostics(cameraInstance, "switch_camera")
            )
            return
        }

        if (cameraInstance.isSwitching) {
            result.error(
                "SWITCH_IN_PROGRESS",
                "Camera switch already in progress",
                recordingDiagnostics(cameraInstance, "switch_camera")
            )
            return
        }

        if (cameraInstance.pendingStart != null) {
            result.error(
                "START_IN_PROGRESS",
                "Recording start is not confirmed yet",
                recordingDiagnostics(cameraInstance, "switch_camera")
            )
            return
        }

        if (cameraInstance.pendingPauseResult != null) {
            result.error(
                "PAUSE_IN_PROGRESS",
                "Recording pause is already in progress",
                recordingDiagnostics(cameraInstance, "switch_camera")
            )
            return
        }

        if (cameraInstance.pendingResumeResult != null) {
            result.error(
                "RESUME_IN_PROGRESS",
                "Recording resume is already in progress",
                recordingDiagnostics(cameraInstance, "switch_camera")
            )
            return
        }

        if (cameraInstance.isPaused) {
            result.error(
                "PAUSED_FLIP_UNSUPPORTED",
                "Android does not support switching cameras while recording is paused",
                recordingDiagnostics(cameraInstance, "switch_camera")
            )
            return
        }

        // CameraX creates a NEW video encoder for each camera rebind during a
        // persistent recording (Recorder.SetupVideoTask), and the replacement
        // encoder starts with an empty pause ledger (EncoderImpl
        // mTotalPausedDurationUs = 0) while the audio encoder keeps its pause
        // adjustment. Switching after any completed pause therefore desyncs
        // audio and video by the total prior paused duration. Present through
        // CameraX 1.7.0-alpha02.
        if (cameraInstance.recording != null && cameraInstance.pauseCount > 0) {
            result.error(
                "PAUSE_HISTORY_FLIP_UNSUPPORTED",
                "Android does not support switching cameras after a recording has been paused",
                recordingDiagnostics(cameraInstance, "switch_camera")
            )
            return
        }

        val activity = this.activity ?: run {
            result.error(
                "NO_ACTIVITY",
                "Activity not available",
                recordingDiagnostics(cameraInstance, "switch_camera")
            )
            return
        }

        val newLensDirection = oppositeLensDirection(currentLensDirection(cameraInstance))
        if (!hasCameraLens(activity, lensFacingForDirection(newLensDirection))) {
            result.error(
                "SWITCH_UNAVAILABLE",
                "No $newLensDirection camera is available",
                recordingDiagnostics(cameraInstance, "switch_camera")
            )
            return
        }

        val videoCapture = cameraInstance.videoCapture ?: run {
            result.error(
                "NOT_INITIALIZED",
                "Camera not initialized",
                recordingDiagnostics(cameraInstance, "switch_camera")
            )
            return
        }

        val textureEntry = cameraInstance.textureEntry ?: run {
            result.error(
                "TEXTURE_ERROR",
                "No texture entry available",
                recordingDiagnostics(cameraInstance, "switch_camera")
            )
            return
        }

        val zoomRatio = cameraInstance.camera
            ?.cameraInfo
            ?.zoomState
            ?.value
            ?.zoomRatio
            ?: 1.0f
        cameraInstance.isSwitching = true
        performCameraSwitch(
            cameraInstance = cameraInstance,
            newLensDirection = newLensDirection,
            activity = activity,
            videoCapture = videoCapture,
            textureEntry = textureEntry,
            zoomRatio = zoomRatio,
            result = result
        )
    }

    // Reports the MID-RECORDING switch capability only, matching iOS
    // (canSwitchCamera returns isRecording there). Preview switches are
    // always supported and intentionally NOT reflected here — gate preview
    // flip UI on camera availability, not on this method.
    private fun canSwitchCameraInstance(cameraInstance: CameraInstance): Boolean {
        val activity = this.activity ?: return false
        if (cameraInstance.recording == null) {
            return false
        }
        if (
            cameraInstance.pendingDispose != null ||
            cameraInstance.pendingStop != null ||
            cameraInstance.pendingPauseResult != null ||
            cameraInstance.pendingResumeResult != null ||
            cameraInstance.isSwitching ||
            cameraInstance.isPaused ||
            cameraInstance.pauseCount > 0
        ) {
            return false
        }
        val newLensDirection = oppositeLensDirection(currentLensDirection(cameraInstance))
        return hasCameraLens(activity, lensFacingForDirection(newLensDirection))
    }

    private fun currentLensDirection(cameraInstance: CameraInstance): String {
        return cameraInstance.cameraDescription?.get("lensDirection") as? String ?: "back"
    }

    private fun oppositeLensDirection(lensDirection: String): String {
        return if (lensDirection == "front") "back" else "front"
    }

    private fun lensFacingForDirection(lensDirection: String): Int {
        return if (lensDirection == "front") {
            CameraCharacteristics.LENS_FACING_FRONT
        } else {
            CameraCharacteristics.LENS_FACING_BACK
        }
    }

    private fun hasCameraLens(activity: Activity, lensFacing: Int): Boolean {
        return try {
            val cameraManager = activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            cameraManager.cameraIdList.any { cameraId ->
                val characteristics = cameraManager.getCameraCharacteristics(cameraId)
                characteristics.get(CameraCharacteristics.LENS_FACING) == lensFacing
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun performCameraSwitch(
        cameraInstance: CameraInstance,
        newLensDirection: String,
        activity: Activity,
        videoCapture: VideoCapture<Recorder>,
        textureEntry: TextureRegistry.SurfaceTextureEntry,
        zoomRatio: Float,
        result: Result
    ) {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(activity)
        cameraProviderFuture.addListener({
            try {
                val cameraProvider = cameraProviderFuture.get()

                val cameraSelector = when (newLensDirection) {
                    "front" -> CameraSelector.DEFAULT_FRONT_CAMERA
                    else -> CameraSelector.DEFAULT_BACK_CAMERA
                }

                val preview = buildPreview(cameraInstance)
                    .also {
                        it.setSurfaceProvider(createSurfaceProvider(textureEntry))
                    }

                videoCapture.targetRotation = orientationListener?.getRotation() ?: Surface.ROTATION_0
                val useCaseGroup = UseCaseGroup.Builder()
                    .addUseCase(preview)
                    .addUseCase(videoCapture)
                    .build()

                cameraProvider.unbindAll()
                cameraInstance.camera = null
                cameraInstance.preview = null
                val camera = cameraProvider.bindToLifecycle(
                    activity as LifecycleOwner,
                    cameraSelector,
                    useCaseGroup
                )

                cameraInstance.cameraDescription = cameraInstance.cameraDescription?.toMutableMap()?.apply {
                    put("lensDirection", newLensDirection)
                }
                cameraInstance.preview = preview
                cameraInstance.camera = camera
                cameraInstance.switchCount += 1
                cameraInstance.isSwitching = false

                restoreZoomRatio(camera, zoomRatio)

                result.success(
                    mapOf(
                        "textureId" to textureEntry.id(),
                        "previewSize" to mapOf(
                            "width" to preview.resolutionInfo?.resolution?.width,
                            "height" to preview.resolutionInfo?.resolution?.height
                        )
                    )
                )
            } catch (e: Exception) {
                cameraInstance.isSwitching = false
                result.error(
                    "SWITCH_ERROR",
                    e.message,
                    recordingDiagnostics(cameraInstance, "switch_camera")
                )
            }
        }, ContextCompat.getMainExecutor(activity))
    }

    private fun restoreZoomRatio(camera: Camera, requestedZoomRatio: Float, attempt: Int = 0) {
        try {
            val zoomState = camera.cameraInfo.zoomState.value
            if (zoomState == null) {
                if (attempt < 3) {
                    mainHandler.postDelayed({
                        restoreZoomRatio(camera, requestedZoomRatio, attempt + 1)
                    }, 100L)
                }
                return
            }
            val minZoom = maxOf(1.0f, zoomState.minZoomRatio)
            val maxZoom = maxOf(minZoom, minOf(zoomState.maxZoomRatio, 8.0f))
            val clampedZoom = requestedZoomRatio.coerceIn(minZoom, maxZoom)
            camera.cameraControl.setZoomRatio(clampedZoom)
        } catch (_: Exception) {
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Symmetric cleanup: every registry the plugin fills gets emptied, any
        // owned Bluetooth routing is released, and the single-thread executor
        // is shut down (a detached plugin instance is never re-attached).
        cameras.values.forEach { cameraInstance ->
            failPendingStart(cameraInstance, "DETACHED", "Engine detached before start confirmation")
            teardownBluetoothRouting(cameraInstance)
        }
        cameras.clear()
        eventChannels.values.forEach { it.setStreamHandler(null) }
        eventChannels.clear()
        streamHandlers.clear()
        audioEventChannels.values.forEach { it.setStreamHandler(null) }
        audioEventChannels.clear()
        audioStreamHandlers.values.forEach { it.dispose() }
        audioStreamHandlers.clear()
        audioLevelEventChannels.values.forEach { it.setStreamHandler(null) }
        audioLevelEventChannels.clear()
        audioLevelStreamHandlers.clear()
        channel.setMethodCallHandler(null)
        flutterPluginBinding = null
        executor.shutdown()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        orientationListener = OrientationListener(binding.activity)
        orientationListener?.start()
    }

    override fun onDetachedFromActivityForConfigChanges() {
        orientationListener?.stop()
        orientationListener = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        orientationListener = OrientationListener(binding.activity)
        orientationListener?.start()
    }

    override fun onDetachedFromActivity() {
        // Release any owned Bluetooth routing while a context still exists.
        cameras.values.forEach { teardownBluetoothRouting(it) }
        orientationListener?.stop()
        orientationListener = null
        activity = null
    }
}

/**
 * Shared audio-device introspection used by the plugin (diagnostics, start
 * route stamp, Bluetooth routing) and the audio-device stream handler.
 *
 * Two distinct notions, kept deliberately separate:
 * - [preferredInputDevice] is an *availability heuristic* (a Bluetooth input
 *   merely exists) — it says nothing about what capture actually uses.
 * - [activeRecordingInputDevice] is *routed-capture ground truth* from
 *   AudioRecordingConfiguration while a recording is live.
 */
internal object AudioDeviceIntrospection {
    fun preferredInputDevice(audioManager: AudioManager?): AudioDeviceInfo? {
        if (audioManager == null) {
            return null
        }
        val inputDevices = audioManager
            .getDevices(AudioManager.GET_DEVICES_INPUTS)
            .filter { it.isSource }

        return inputDevices.firstOrNull { isBluetoothDevice(it) }
            ?: inputDevices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC }
            ?: inputDevices.firstOrNull()
    }

    fun activeRecordingInputDevice(audioManager: AudioManager?): AudioDeviceInfo? {
        if (audioManager == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            return null
        }
        return try {
            audioManager.activeRecordingConfigurations.firstNotNullOfOrNull { it.audioDevice }
        } catch (_: Exception) {
            null
        }
    }

    fun deviceName(device: AudioDeviceInfo?): String {
        val productName = device?.productName?.toString()
        if (!productName.isNullOrBlank()) {
            return productName
        }
        return if (device == null) {
            "Android Microphone"
        } else {
            typeName(device.type)
        }
    }

    fun typeName(type: Int?): String {
        return when (type) {
            AudioDeviceInfo.TYPE_BUILTIN_MIC -> "BuiltInMic"
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "BluetoothSCO"
            AudioDeviceInfo.TYPE_WIRED_HEADSET -> "WiredHeadset"
            AudioDeviceInfo.TYPE_USB_DEVICE -> "UsbDevice"
            AudioDeviceInfo.TYPE_USB_HEADSET -> "UsbHeadset"
            AudioDeviceInfo.TYPE_BLE_HEADSET -> "BluetoothLEHeadset"
            AudioDeviceInfo.TYPE_BLE_BROADCAST -> "BluetoothLEBroadcast"
            null -> "BuiltInMic"
            else -> "AndroidAudioDevice$type"
        }
    }

    fun isBluetoothDevice(device: AudioDeviceInfo?): Boolean {
        return when (device?.type) {
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
            AudioDeviceInfo.TYPE_BLE_BROADCAST -> true
            else -> false
        }
    }
}

/**
 * Stream handler for the per-camera audio-level EventChannel. All calls
 * (onListen/onCancel from the platform thread, send from the main-executor
 * VideoRecordEvent listener) run on the main thread.
 */
class AudioLevelStreamHandler : EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun send(event: Map<String, Any>) {
        eventSink?.success(event)
    }
}

class AudioDeviceStreamHandler(context: Context) : EventChannel.StreamHandler {
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var eventSink: EventChannel.EventSink? = null
    private var callback: AudioDeviceCallback? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        events?.success(currentAudioDeviceEvent("initial"))

        val audioCallback = object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
                emitAudioDeviceChanged()
            }

            override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
                emitAudioDeviceChanged()
            }
        }
        callback = audioCallback
        audioManager.registerAudioDeviceCallback(
            audioCallback,
            Handler(Looper.getMainLooper())
        )
    }

    override fun onCancel(arguments: Any?) {
        dispose()
    }

    fun dispose() {
        callback?.let { audioManager.unregisterAudioDeviceCallback(it) }
        callback = null
        eventSink = null
    }

    private fun emitAudioDeviceChanged() {
        eventSink?.success(currentAudioDeviceEvent("audioRouteChanged"))
    }

    private fun currentAudioDeviceEvent(event: String): Map<String, Any> {
        // Truthful detection: `isBluetooth` reflects what capture is ACTUALLY
        // using while a recording is live (AudioRecordingConfiguration); the
        // availability heuristic is reported separately so the two can never
        // be conflated again. Pre-recording (no active capture) the legacy
        // key falls back to the availability heuristic.
        val availableDevice = AudioDeviceIntrospection.preferredInputDevice(audioManager)
        val activeDevice = AudioDeviceIntrospection.activeRecordingInputDevice(audioManager)
        val reportedDevice = activeDevice ?: availableDevice
        val isBluetoothAvailable = AudioDeviceIntrospection.isBluetoothDevice(availableDevice)
        return mapOf(
            "event" to event,
            "deviceName" to AudioDeviceIntrospection.deviceName(reportedDevice),
            "portType" to AudioDeviceIntrospection.typeName(reportedDevice?.type),
            "isBluetooth" to if (activeDevice != null) {
                AudioDeviceIntrospection.isBluetoothDevice(activeDevice)
            } else {
                isBluetoothAvailable
            },
            "isBluetoothActive" to AudioDeviceIntrospection.isBluetoothDevice(activeDevice),
            "isBluetoothAvailable" to isBluetoothAvailable,
            "hasActiveRecording" to (activeDevice != null)
        )
    }
}

class RecordingStateStreamHandler : EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        events?.success("idle")
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}

class OrientationListener(private val activity: Activity) {
    private var orientationEventListener: OrientationEventListener? = null
    private var currentOrientation: Int = 0

    fun start() {
        orientationEventListener = object : OrientationEventListener(activity, SensorManager.SENSOR_DELAY_NORMAL) {
            override fun onOrientationChanged(orientation: Int) {
                currentOrientation = when (orientation) {
                    in 45..134 -> Surface.ROTATION_270
                    in 135..224 -> Surface.ROTATION_180
                    in 225..314 -> Surface.ROTATION_90
                    else -> Surface.ROTATION_0
                }
            }
        }
        orientationEventListener?.enable()
    }

    fun stop() {
        orientationEventListener?.disable()
        orientationEventListener = null
    }

    fun getRotation(): Int {
        return currentOrientation
    }
}
