package com.example.waffle_camera_plugin

import android.app.Activity
import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.util.Rational
import android.view.Surface
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.Preview
import androidx.camera.core.UseCaseGroup
import androidx.camera.core.ViewPort
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FileOutputOptions
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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.nio.ByteBuffer

class WaffleCameraPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding? = null
    private val cameras = mutableMapOf<Int, CameraInstance>()
    private var nextCameraId = 0
    private val executor = Executors.newSingleThreadExecutor()
    private val eventChannels = mutableMapOf<Int, EventChannel>()
    private val streamHandlers = mutableMapOf<Int, RecordingStateStreamHandler>()

    data class CameraInstance(
        val cameraId: Int,
        var cameraDescription: Map<String, Any>? = null,
        var textureEntry: TextureRegistry.SurfaceTextureEntry? = null,
        var camera: Camera? = null,
        var videoCapture: VideoCapture<Recorder>? = null,
        var preview: Preview? = null,
        var recording: Recording? = null,
        var recordingURL: String? = null,
        var segmentFiles: MutableList<File> = mutableListOf(),
        var currentSegmentIndex: Int = 0,
        var isSwitching: Boolean = false,
        var switchingHandler: (() -> Unit)? = null,
        var isPaused: Boolean = false,
        var pauseResumeHandler: (() -> Unit)? = null
    )

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "waffle_camera_plugin")
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
            "pauseRecording" -> pauseRecording(call, result)
            "resumeRecording" -> resumeRecording(call, result)
            "stopRecording" -> stopRecording(call, result)
            "isMultiCamSupported" -> isMultiCamSupported(result)
            "canSwitchCamera" -> canSwitchCamera(call, result)
            "switchCamera" -> switchCamera(call, result)
            "canSwitchCurrentCamera" -> canSwitchCurrentCamera(result)
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            else -> result.notImplemented()
        }
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
        val preset = call.argument<String>("preset")
        
        if (cameraDescription == null) {
            result.error("INVALID_ARGUMENT", "Camera description is required", null)
            return
        }
        
        val cameraId = nextCameraId++
        cameras[cameraId] = CameraInstance(
            cameraId = cameraId,
            cameraDescription = cameraDescription
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

                val rotation = activity.display?.rotation ?: Surface.ROTATION_0

                val preview = Preview.Builder()
                    .setTargetRotation(rotation)
                    .build()
                cameraInstance.preview = preview

                val recorder = Recorder.Builder()
                    .setExecutor(executor)
                    .build()
                val videoCapture = VideoCapture.withOutput(recorder)
                cameraInstance.videoCapture = videoCapture

                val useCaseGroup = UseCaseGroup.Builder()
                    .addUseCase(preview)
                    .addUseCase(videoCapture)
                    .setViewPort(ViewPort.Builder(Rational(9, 16), rotation).build())
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
                        "waffle_camera_plugin/recording_state_${actualCameraId}"
                    )
                    val streamHandler = RecordingStateStreamHandler()
                    stateChannel.setStreamHandler(streamHandler)
                    eventChannels[actualCameraId] = stateChannel
                    streamHandlers[actualCameraId] = streamHandler
                }

                val textureId = textureEntry.id()
                result.success(textureId)
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

    private fun disposeCamera(call: MethodCall, result: Result) {
        val cameraId = call.argument<Int>("cameraId")
        val cameraInstance = cameras[cameraId] ?: run {
            result.success(null)
            return
        }

        eventChannels[cameraId]?.setStreamHandler(null)
        eventChannels.remove(cameraId)
        streamHandlers.remove(cameraId)

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
            cameraInstance.segmentFiles.clear()
            cameraInstance.currentSegmentIndex = 0

            val file = File(activity.cacheDir, "segment_${System.currentTimeMillis()}_0.mp4")
            cameraInstance.recordingURL = file.absolutePath
            cameraInstance.segmentFiles.add(file)
            cameraInstance.currentSegmentIndex = 1

            val outputOptions = FileOutputOptions.Builder(file).build()

            val rotation = activity.display?.rotation ?: Surface.ROTATION_0
            videoCapture.targetRotation = rotation

            val recording = videoCapture.output
                .prepareRecording(activity, outputOptions)
                .withAudioEnabled()
                .start(ContextCompat.getMainExecutor(activity)) { event ->
                    when (event) {
                        is VideoRecordEvent.Finalize -> {
                            cameraInstance.switchingHandler?.let { handler ->
                                cameraInstance.switchingHandler = null
                                handler()
                            }
                        }
                        else -> {}
                    }
                }

            cameraInstance.recording = recording
            result.success(null)
        } catch (e: Exception) {
            result.error("RECORDING_ERROR", e.message, null)
        }
    }

    private fun pauseRecording(call: MethodCall, result: Result) {
        val cameraId = call.argument<Int>("cameraId")
        val cameraInstance = cameras[cameraId] ?: run {
            result.error("INVALID_CAMERA", "Camera not found", null)
            return
        }

        if (cameraInstance.recording == null) {
            result.error("NOT_RECORDING", "No active recording", null)
            return
        }

        if (cameraInstance.isPaused) {
            result.success(null)
            return
        }

        val activity = this.activity ?: run {
            result.error("NO_ACTIVITY", "Activity not available", null)
            return
        }

        cameraInstance.isPaused = true
        val recording = cameraInstance.recording!!
        cameraInstance.recording = null

        cameraInstance.recordingURL?.let { url ->
            if (url.isNotEmpty()) {
                cameraInstance.segmentFiles.add(File(url))
            }
        }
        cameraInstance.recordingURL = null

        var hasCompleted = false
        cameraInstance.pauseResumeHandler = {
            if (!hasCompleted) {
                hasCompleted = true
                cameraInstance.pauseResumeHandler = null
                result.success(null)
            }
        }

        recording.stop()

        GlobalScope.launch(Dispatchers.Main) {
            delay(3000)
            if (!hasCompleted) {
                hasCompleted = true
                cameraInstance.pauseResumeHandler = null
                result.success(null)
            }
        }
    }

    private fun resumeRecording(call: MethodCall, result: Result) {
        val cameraId = call.argument<Int>("cameraId")
        val cameraInstance = cameras[cameraId] ?: run {
            result.error("INVALID_CAMERA", "Camera not found", null)
            return
        }

        if (!cameraInstance.isPaused) {
            result.error("NOT_PAUSED", "Recording is not paused", null)
            return
        }

        val activity = this.activity ?: run {
            result.error("NO_ACTIVITY", "Activity not available", null)
            return
        }

        val videoCapture = cameraInstance.videoCapture ?: run {
            result.error("NOT_INITIALIZED", "Camera not initialized", null)
            return
        }

        val lensDirection = cameraInstance.cameraDescription?.get("lensDirection") as? String ?: "back"

        try {
            cameraInstance.isPaused = false

            val segmentFile = File(activity.cacheDir, "segment_${System.currentTimeMillis()}_${cameraInstance.currentSegmentIndex}.mp4")
            cameraInstance.currentSegmentIndex++

            val outputOptions = FileOutputOptions.Builder(segmentFile).build()

            val resumeRotation = activity.display?.rotation ?: Surface.ROTATION_0
            videoCapture.targetRotation = resumeRotation

            val recording = videoCapture.output
                .prepareRecording(activity, outputOptions)
                .withAudioEnabled()
                .start(ContextCompat.getMainExecutor(activity)) { event ->
                    when (event) {
                        is VideoRecordEvent.Finalize -> {
                            cameraInstance.recordingURL?.let { url ->
                                if (url.isNotEmpty() && !cameraInstance.segmentFiles.any { it.absolutePath == url }) {
                                    cameraInstance.segmentFiles.add(File(url))
                                }
                            }
                            cameraInstance.pauseResumeHandler?.let { handler ->
                                cameraInstance.pauseResumeHandler = null
                                handler()
                            }
                        }
                        else -> {}
                    }
                }

            cameraInstance.recording = recording
            cameraInstance.recordingURL = segmentFile.absolutePath

            result.success(null)
        } catch (e: Exception) {
            result.error("RESUME_ERROR", e.message, null)
        }
    }

    private fun stopRecording(call: MethodCall, result: Result) {
        val cameraId = call.argument<Int>("cameraId")
        val cameraInstance = cameras[cameraId] ?: run {
            result.error("INVALID_CAMERA", "Camera not found", null)
            return
        }

        val recording = cameraInstance.recording

        if (recording != null) {
            try {
                recording.stop()
                cameraInstance.recording = null

                cameraInstance.recordingURL?.let { url ->
                    if (url.isNotEmpty()) {
                        cameraInstance.segmentFiles.add(File(url))
                    }
                }
                cameraInstance.recordingURL = null
            } catch (e: Exception) {
                cleanupSegmentFiles(cameraInstance.segmentFiles)
                cameraInstance.segmentFiles.clear()
                cameraInstance.currentSegmentIndex = 0
                cameraInstance.isPaused = false
                result.error("STOP_ERROR", e.message, null)
                return
            }
        }

        if (cameraInstance.segmentFiles.isEmpty()) {
            result.error("NO_RECORDING", "No recording segments found", null)
            return
        }

        cameraInstance.isPaused = false

        if (cameraInstance.segmentFiles.size == 1) {
            val outputFile = cameraInstance.segmentFiles[0]
            cameraInstance.segmentFiles.clear()
            cameraInstance.currentSegmentIndex = 0
            result.success(outputFile.absolutePath)
            return
        }

        GlobalScope.launch(Dispatchers.IO) {
            try {
                val mergedFile = mergeSegments(cameraInstance.segmentFiles)
                cleanupSegmentFiles(cameraInstance.segmentFiles)
                cameraInstance.segmentFiles.clear()
                cameraInstance.currentSegmentIndex = 0
                result.success(mergedFile.absolutePath)
            } catch (e: Exception) {
                cleanupSegmentFiles(cameraInstance.segmentFiles)
                cameraInstance.segmentFiles.clear()
                cameraInstance.currentSegmentIndex = 0
                result.error("MERGE_ERROR", e.message, null)
            }
        }
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

        val activity = this.activity
        if (activity == null) {
            result.success(false)
            return
        }

        val hasFrontCamera = try {
            val cameraManager = activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            cameraManager.cameraIdList.any { id ->
                val characteristics = cameraManager.getCameraCharacteristics(id)
                characteristics.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_FRONT
            }
        } catch (e: Exception) {
            false
        }

        val hasBackCamera = try {
            val cameraManager = activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            cameraManager.cameraIdList.any { id ->
                val characteristics = cameraManager.getCameraCharacteristics(id)
                characteristics.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
            }
        } catch (e: Exception) {
            false
        }

        val canSwitch = cameraInstance.recording != null &&
                        !cameraInstance.isSwitching &&
                        !cameraInstance.isPaused &&
                        hasFrontCamera &&
                        hasBackCamera

        result.success(canSwitch)
    }

    private fun canSwitchCurrentCamera(result: Result) {
        val activity = this.activity
        if (activity == null) {
            result.success(false)
            return
        }

        val cameraManager = activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val hasFront = cameraManager.cameraIdList.any { id ->
            cameraManager.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_FRONT
        }
        val hasBack = cameraManager.cameraIdList.any { id ->
            cameraManager.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
        }

        if (!hasFront || !hasBack) {
            result.success(false)
            return
        }

        for (instance in cameras.values) {
            if (instance.recording != null && !instance.isSwitching && !instance.isPaused) {
                result.success(true)
                return
            }
        }
        result.success(false)
    }

    private fun switchCamera(call: MethodCall, result: Result) {
        val cameraId = call.argument<Int>("cameraId")
        val cameraInstance = cameras[cameraId] ?: run {
            result.error("INVALID_CAMERA", "Camera not found", null)
            return
        }

        if (cameraInstance.recording == null) {
            result.error("NOT_RECORDING", "Camera not currently recording", null)
            return
        }

        if (cameraInstance.isSwitching) {
            result.error("SWITCH_IN_PROGRESS", "Camera switch already in progress", null)
            return
        }

        if (cameraInstance.isPaused) {
            result.error("PAUSED", "Cannot switch camera while paused", null)
            return
        }

        val activity = this.activity ?: run {
            result.error("NO_ACTIVITY", "Activity not available", null)
            return
        }

        cameraInstance.isSwitching = true

        val recording = cameraInstance.recording!!
        cameraInstance.recording = null

        cameraInstance.recordingURL?.let { url ->
            cameraInstance.segmentFiles.add(File(url))
        }
        cameraInstance.recordingURL = null

        val newLensDirection = if ((cameraInstance.cameraDescription?.get("lensDirection") as? String) == "front") "back" else "front"
        val actualCameraId = cameraId!!

        var hasCompleted = false
        cameraInstance.switchingHandler = {
            if (!hasCompleted) {
                hasCompleted = true
                cameraInstance.switchingHandler = null
                performCameraSwitch(actualCameraId, cameraInstance, newLensDirection, activity, result)
            }
        }

        recording.stop()

        GlobalScope.launch(Dispatchers.Main) {
            delay(3000)
            if (!hasCompleted) {
                hasCompleted = true
                cameraInstance.switchingHandler = null
                performCameraSwitch(actualCameraId, cameraInstance, newLensDirection, activity, result)
            }
        }
    }

    private fun performCameraSwitch(
        cameraId: Int,
        cameraInstance: CameraInstance,
        newLensDirection: String,
        activity: Activity,
        result: Result
    ) {
        cameraInstance.cameraDescription = cameraInstance.cameraDescription?.toMutableMap()?.apply {
            put("lensDirection", newLensDirection)
        }

        val cameraProviderFuture = ProcessCameraProvider.getInstance(activity)
        cameraProviderFuture.addListener({
            try {
                val cameraProvider = cameraProviderFuture.get()

                val cameraSelector = when (newLensDirection) {
                    "front" -> CameraSelector.DEFAULT_FRONT_CAMERA
                    else -> CameraSelector.DEFAULT_BACK_CAMERA
                }

                cameraProvider.unbindAll()

                val textureEntry = cameraInstance.textureEntry
                if (textureEntry == null) {
                    cameraInstance.isSwitching = false
                    result.error("TEXTURE_ERROR", "No texture entry available", null)
                    return@addListener
                }

                val switchRotation = activity.display?.rotation ?: Surface.ROTATION_0

                val preview = Preview.Builder()
                    .setTargetRotation(switchRotation)
                    .build()
                    .also {
                        it.setSurfaceProvider(createSurfaceProvider(textureEntry))
                    }
                cameraInstance.preview = preview

                val recorder = Recorder.Builder()
                    .setExecutor(executor)
                    .build()
                val videoCapture = VideoCapture.withOutput(recorder)
                cameraInstance.videoCapture = videoCapture

                val useCaseGroup = UseCaseGroup.Builder()
                    .addUseCase(preview)
                    .addUseCase(videoCapture)
                    .setViewPort(ViewPort.Builder(Rational(9, 16), switchRotation).build())
                    .build()

                val camera = cameraProvider.bindToLifecycle(
                    activity as LifecycleOwner,
                    cameraSelector,
                    useCaseGroup
                )
                cameraInstance.camera = camera

                val segmentFile = File(activity.cacheDir, "segment_${System.currentTimeMillis()}_${cameraInstance.currentSegmentIndex}.mp4")
                cameraInstance.currentSegmentIndex++
                cameraInstance.segmentFiles.add(segmentFile)

                val outputOptions = FileOutputOptions.Builder(segmentFile).build()
                videoCapture.targetRotation = switchRotation
                val recording = videoCapture.output
                    .prepareRecording(activity, outputOptions)
                    .withAudioEnabled()
                    .start(ContextCompat.getMainExecutor(activity)) { event ->
                        when (event) {
                            is VideoRecordEvent.Finalize -> {
                                cameraInstance.recordingURL?.let { url ->
                                    if (url.isNotEmpty() && !cameraInstance.segmentFiles.any { it.absolutePath == url }) {
                                        cameraInstance.segmentFiles.add(File(url))
                                    }
                                }
                                cameraInstance.switchingHandler?.let { handler ->
                                    cameraInstance.switchingHandler = null
                                    handler()
                                }
                            }
                            else -> {}
                        }
                    }

                cameraInstance.recording = recording
                cameraInstance.recordingURL = segmentFile.absolutePath
                cameraInstance.isSwitching = false

                val currentTextureId = cameraInstance.textureEntry?.id()
                result.success(currentTextureId)
            } catch (e: Exception) {
                cameraInstance.isSwitching = false
                result.error("SWITCH_ERROR", e.message, null)
            }
        }, ContextCompat.getMainExecutor(activity))
    }

    private fun mergeSegments(segmentFiles: List<File>): File {
        if (segmentFiles.isEmpty()) {
            throw IllegalArgumentException("No segment files to merge")
        }

        val activity = this.activity ?: throw IllegalStateException("Activity not available")
        val outputFile = File(activity.cacheDir, "merged_${System.currentTimeMillis()}.mp4")

        val muxer = MediaMuxer(outputFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

        try {
            var videoTrackIndex = -1
            var audioTrackIndex = -1
            var muxerStarted = false

            var lastVideoTimestamp: Long = 0
            var lastAudioTimestamp: Long = 0

            for ((segmentIndex, segmentFile) in segmentFiles.withIndex()) {
                val extractor = MediaExtractor()
                extractor.setDataSource(segmentFile.absolutePath)

                val trackCount = extractor.trackCount
                val trackMap = mutableMapOf<Int, Int>()

                for (i in 0 until trackCount) {
                    val format = extractor.getTrackFormat(i)
                    val mime = format.getString(MediaFormat.KEY_MIME) ?: ""

                    if (mime.startsWith("video/")) {
                        if (videoTrackIndex < 0) {
                            videoTrackIndex = muxer.addTrack(format)
                        }
                        trackMap[i] = videoTrackIndex
                    } else if (mime.startsWith("audio/")) {
                        if (audioTrackIndex < 0) {
                            audioTrackIndex = muxer.addTrack(format)
                        }
                        trackMap[i] = audioTrackIndex
                    }
                }

                if (!muxerStarted && (videoTrackIndex >= 0 || audioTrackIndex >= 0)) {
                    muxer.start()
                    muxerStarted = true
                }

                val segmentBaseTimestamp = when {
                    segmentIndex == 0 -> 0L
                    lastVideoTimestamp > lastAudioTimestamp -> lastVideoTimestamp
                    else -> lastAudioTimestamp
                }

                for (i in 0 until trackCount) {
                    val format = extractor.getTrackFormat(i)
                    val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                    val muxerTrackIndex = trackMap[i] ?: continue

                    extractor.selectTrack(i)
                    val isVideo = mime.startsWith("video/")
                    val lastTimestamp = copyTrackWithTimestampOffset(
                        extractor, muxer, muxerTrackIndex, segmentBaseTimestamp, isVideo
                    )

                    if (isVideo) {
                        lastVideoTimestamp = lastTimestamp
                    } else {
                        lastAudioTimestamp = lastTimestamp
                    }
                }

                extractor.release()
            }

            muxer.stop()
            muxer.release()

            return outputFile
        } catch (e: Exception) {
            try { muxer.stop() } catch (_: Exception) {}
            try { muxer.release() } catch (_: Exception) {}
            if (outputFile.exists()) {
                outputFile.delete()
            }
            throw e
        }
    }

    private fun copyTrackWithTimestampOffset(
        extractor: MediaExtractor,
        muxer: MediaMuxer,
        trackIndex: Int,
        timestampOffset: Long,
        isVideo: Boolean
    ): Long {
        val bufferSize = 256 * 1024
        val buffer = android.media.MediaCodec.BufferInfo()
        val byteBuffer = ByteBuffer.allocate(bufferSize)

        var lastTimestamp = timestampOffset

        while (true) {
            val sampleSize = extractor.readSampleData(byteBuffer, 0)

            if (sampleSize < 0) {
                break
            }

            val originalTimestamp = extractor.sampleTime
            val adjustedTimestamp = originalTimestamp + timestampOffset

            buffer.presentationTimeUs = adjustedTimestamp
            buffer.size = sampleSize
            buffer.offset = 0
            buffer.flags = extractor.sampleFlags

            byteBuffer.position(0)
            byteBuffer.limit(sampleSize)
            muxer.writeSampleData(trackIndex, byteBuffer, buffer)

            lastTimestamp = adjustedTimestamp
            extractor.advance()
        }

        return lastTimestamp
    }

    private fun cleanupSegmentFiles(segmentFiles: List<File>) {
        for (file in segmentFiles) {
            try {
                if (file.exists()) {
                    file.delete()
                }
            } catch (_: Exception) {
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        flutterPluginBinding = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
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