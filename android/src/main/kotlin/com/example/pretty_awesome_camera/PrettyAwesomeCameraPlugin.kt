package com.example.pretty_awesome_camera

import android.app.Activity
import android.content.Context
import android.hardware.SensorManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
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
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors

class PrettyAwesomeCameraPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private companion object {
        const val STOP_FINALIZE_TIMEOUT_MS = 10_000L
        const val TARGET_FRAME_RATE_FPS = 30
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
    private var orientationListener: OrientationListener? = null

    data class PendingStop(
        val result: Result,
        val outputFile: File,
        val timeoutRunnable: Runnable
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
        var pendingStop: PendingStop? = null,
        var completedFinalize: CompletedFinalize? = null,
        var pendingDispose: PendingDispose? = null,
        var pauseCount: Int = 0,
        var resumeCount: Int = 0,
        var switchCount: Int = 0
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
        val videoBitrate = when (videoBitrateValue) {
            null -> null
            is Number -> videoBitrateValue.toInt()
            else -> {
                result.error("INVALID_ARGUMENT", "videoBitrate must be an integer", null)
                return
            }
        }
        if (videoBitrate != null && videoBitrate <= 0) {
            result.error("INVALID_ARGUMENT", "videoBitrate must be greater than zero", null)
            return
        }
        
        val cameraId = nextCameraId++
        cameras[cameraId] = CameraInstance(
            cameraId = cameraId,
            cameraDescription = cameraDescription,
            resolutionPreset = resolutionPreset,
            videoBitrate = videoBitrate
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
        val resolution = cameraInstance.videoCapture?.resolutionInfo?.resolution ?: run {
            result.error("NOT_INITIALIZED", "Recording resolution not available", null)
            return
        }

        result.success(
            mapOf(
                "requested_bitrate" to cameraInstance.videoBitrate,
                "resolved_resolution" to "${resolution.width}x${resolution.height}",
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
        eventChannels[cameraId]?.setStreamHandler(null)
        eventChannels.remove(cameraId)
        streamHandlers.remove(cameraId)

        audioEventChannels[cameraId]?.setStreamHandler(null)
        audioEventChannels.remove(cameraId)
        audioStreamHandlers.remove(cameraId)?.dispose()

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

    @OptIn(ExperimentalPersistentRecording::class)
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

        try {
            if (cameraInstance.pendingDispose != null) {
                result.error(
                    "DISPOSE_IN_PROGRESS",
                    "Camera dispose is already in progress",
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

            val file = File(activity.cacheDir, "recording_${System.currentTimeMillis()}.mp4")
            cameraInstance.recordingURL = file.absolutePath

            val outputOptions = FileOutputOptions.Builder(file).build()

            val rotation = orientationListener?.getRotation() ?: Surface.ROTATION_0
            videoCapture.targetRotation = rotation

            val recording = videoCapture.output
                .prepareRecording(activity, outputOptions)
                .withAudioEnabled()
                .asPersistentRecording()
                .start(ContextCompat.getMainExecutor(activity)) { event ->
                    when (event) {
                        is VideoRecordEvent.Pause -> completePause(cameraInstance)
                        is VideoRecordEvent.Resume -> completeResume(cameraInstance)
                        is VideoRecordEvent.Finalize -> handleFinalize(cameraInstance, event)
                        else -> {}
                    }
                }

            cameraInstance.recording = recording
            result.success(null)
        } catch (e: Exception) {
            resetRecordingState(cameraInstance)
            result.error(
                "RECORDING_ERROR",
                e.message,
                recordingDiagnostics(cameraInstance, "start_recording")
            )
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
                cameraInstance.recording = null
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
        cameraInstance.pendingStop = null
        cameraInstance.completedFinalize = null
        cameraInstance.pendingDispose = null
        cameraInstance.pauseCount = 0
        cameraInstance.resumeCount = 0
        cameraInstance.switchCount = 0
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
        return mapOf(
            "native_stage" to stage,
            "native_has_recording" to (cameraInstance.recording != null),
            "native_has_pending_stop" to (cameraInstance.pendingStop != null),
            "native_has_completed_finalize" to (cameraInstance.completedFinalize != null),
            "native_has_pending_dispose" to (cameraInstance.pendingDispose != null),
            "native_is_paused" to cameraInstance.isPaused,
            "native_is_switching" to cameraInstance.isSwitching,
            "native_audio_device_type" to "unknown",
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
        audioEventChannels.values.forEach { it.setStreamHandler(null) }
        audioEventChannels.clear()
        audioStreamHandlers.values.forEach { it.dispose() }
        audioStreamHandlers.clear()
        channel.setMethodCallHandler(null)
        flutterPluginBinding = null
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
        orientationListener?.stop()
        orientationListener = null
        activity = null
    }
}

class AudioDeviceStreamHandler(context: Context) : EventChannel.StreamHandler {
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var eventSink: EventChannel.EventSink? = null
    private var callback: AudioDeviceCallback? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        events?.success(currentAudioDeviceEvent("initial"))

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return
        }

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
        val registeredCallback = callback
        if (registeredCallback != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            audioManager.unregisterAudioDeviceCallback(registeredCallback)
        }
        callback = null
        eventSink = null
    }

    private fun emitAudioDeviceChanged() {
        eventSink?.success(currentAudioDeviceEvent("audioRouteChanged"))
    }

    private fun currentAudioDeviceEvent(event: String): Map<String, Any> {
        val device = preferredInputDevice()
        return mapOf(
            "event" to event,
            "deviceName" to deviceName(device),
            "portType" to audioDeviceTypeName(device?.type),
            "isBluetooth" to isBluetoothDevice(device)
        )
    }

    private fun preferredInputDevice(): AudioDeviceInfo? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return null
        }

        val inputDevices = audioManager
            .getDevices(AudioManager.GET_DEVICES_INPUTS)
            .filter { it.isSource }

        return inputDevices.firstOrNull { isBluetoothDevice(it) }
            ?: inputDevices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC }
            ?: inputDevices.firstOrNull()
    }

    private fun deviceName(device: AudioDeviceInfo?): String {
        val productName = device?.productName?.toString()
        if (!productName.isNullOrBlank()) {
            return productName
        }
        return if (device == null) {
            "Android Microphone"
        } else {
            audioDeviceTypeName(device.type)
        }
    }

    private fun audioDeviceTypeName(type: Int?): String {
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

    private fun isBluetoothDevice(device: AudioDeviceInfo?): Boolean {
        return when (device?.type) {
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
            AudioDeviceInfo.TYPE_BLE_BROADCAST -> true
            else -> false
        }
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
