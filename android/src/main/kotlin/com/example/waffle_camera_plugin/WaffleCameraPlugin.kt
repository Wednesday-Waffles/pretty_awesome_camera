package com.example.waffle_camera_plugin

import android.app.Activity
import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.Preview
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
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import java.io.File
import java.util.concurrent.Executors

class WaffleCameraPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding? = null
    private val cameras = mutableMapOf<Int, CameraInstance>()
    private var nextCameraId = 0
    private val executor = Executors.newSingleThreadExecutor()

    data class CameraInstance(
        val cameraId: Int,
        var cameraDescription: Map<String, Any>? = null,
        var textureEntry: TextureRegistry.SurfaceTextureEntry? = null,
        var camera: Camera? = null,
        var videoCapture: VideoCapture<Recorder>? = null,
        var preview: Preview? = null,
        var recording: Recording? = null,
        var segmentFiles: MutableList<File> = mutableListOf(),
        var currentSegmentIndex: Int = 0,
        var isSwitching: Boolean = false
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
                
                val preview = Preview.Builder()
                    .setTargetRotation(android.view.Surface.ROTATION_0)
                    .build()
                    .also {
                        it.setSurfaceProvider { request ->
                            val surface = android.view.Surface(textureEntry.surfaceTexture())
                            request.provideSurface(surface, executor) {}
                        }
                    }
                cameraInstance.preview = preview
                
                val recorder = Recorder.Builder()
                    .setExecutor(executor)
                    .build()
                val videoCapture = VideoCapture.withOutput(recorder)
                cameraInstance.videoCapture = videoCapture
                
                val camera = cameraProvider.bindToLifecycle(
                    activity as LifecycleOwner,
                    cameraSelector,
                    preview,
                    videoCapture
                )
                cameraInstance.camera = camera
                
                val textureId = cameraInstance.textureEntry?.id()
                if (textureId != null) {
                    result.success(textureId)
                } else {
                    result.error("TEXTURE_ERROR", "Failed to create texture", null)
                }
            } catch (e: Exception) {
                result.error("INIT_ERROR", e.message, null)
            }
        }, ContextCompat.getMainExecutor(activity))
    }

     private fun disposeCamera(call: MethodCall, result: Result) {
         val cameraId = call.argument<Int>("cameraId")
         val cameraInstance = cameras[cameraId] ?: run {
             result.success(null)
             return
         }
         
         cameraInstance.camera?.let { camera ->
             val activity = this.activity
             if (activity != null) {
                 val cameraProvider = ProcessCameraProvider.getInstance(activity).get()
                 cameraProvider.unbind(cameraInstance.preview, cameraInstance.videoCapture)
             }
         }
         
         cameraInstance.textureEntry?.release()
         cameras.remove(cameraId)
         
         result.success(null)
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
            cameraInstance.segmentFiles.add(file)
            cameraInstance.currentSegmentIndex = 1
            
            val outputOptions = FileOutputOptions.Builder(file).build()

            val recording = videoCapture.output
                .prepareRecording(activity, outputOptions)
                .withAudioEnabled()
                .start(ContextCompat.getMainExecutor(activity)) { event -> }

            cameraInstance.recording = recording
            result.success(null)
        } catch (e: Exception) {
            result.error("RECORDING_ERROR", e.message, null)
        }
    }

    private fun pauseRecording(call: MethodCall, result: Result) {
        val cameraId = call.argument<Int>("cameraId")
        val cameraInstance = cameras[cameraId]

        if (cameraInstance?.recording != null) {
            try {
                cameraInstance.recording?.pause()
                result.success(null)
            } catch (e: Exception) {
                result.error("PAUSE_ERROR", e.message, null)
            }
        } else {
            result.error("NOT_RECORDING", "No active recording", null)
        }
    }

    private fun resumeRecording(call: MethodCall, result: Result) {
        val cameraId = call.argument<Int>("cameraId")
        val cameraInstance = cameras[cameraId]

        if (cameraInstance?.recording != null) {
            try {
                cameraInstance.recording?.resume()
                result.success(null)
            } catch (e: Exception) {
                result.error("RESUME_ERROR", e.message, null)
            }
        } else {
            result.error("NOT_RECORDING", "No active recording", null)
        }
    }

    private fun stopRecording(call: MethodCall, result: Result) {
        val cameraId = call.argument<Int>("cameraId")
        val cameraInstance = cameras[cameraId]
        val recording = cameraInstance?.recording

        if (recording != null) {
            try {
                recording.stop()
                cameraInstance?.recording = null
                
                if (cameraInstance?.segmentFiles?.isEmpty() == true) {
                    result.error("NO_RECORDING", "No recording segments found", null)
                    return
                }
                
                if (cameraInstance?.segmentFiles?.size == 1) {
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
            } catch (e: Exception) {
                cleanupSegmentFiles(cameraInstance?.segmentFiles ?: mutableListOf())
                cameraInstance?.segmentFiles?.clear()
                cameraInstance?.currentSegmentIndex = 0
                result.error("STOP_ERROR", e.message, null)
            }
        } else {
            result.error("NOT_RECORDING", "No active recording", null)
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
        
        val canSwitch = cameraInstance.recording != null && !cameraInstance.isSwitching
        result.success(canSwitch)
    }

    private fun canSwitchCurrentCamera(result: Result) {
        for (instance in cameras.values) {
            if (instance.recording != null && !instance.isSwitching) {
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

        val activity = this.activity ?: run {
            result.error("NO_ACTIVITY", "Activity not available", null)
            return
        }

        cameraInstance.isSwitching = true

        val recording = cameraInstance.recording!!
        cameraInstance.recording = null

        val newLensDirection = if ((cameraInstance.cameraDescription?.get("lensDirection") as? String) == "front") "back" else "front"

        recording.start(ContextCompat.getMainExecutor(activity)) { event ->
            if (event is VideoRecordEvent.Finalize) {
                performCameraSwitch(cameraId, cameraInstance, newLensDirection, activity, result)
            }
        }
        recording.stop()
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
                val preview = Preview.Builder()
                    .setTargetRotation(android.view.Surface.ROTATION_0)
                    .build()
                    .also {
                        if (textureEntry != null) {
                            it.setSurfaceProvider { request ->
                                val surface = android.view.Surface(textureEntry.surfaceTexture())
                                request.provideSurface(surface, executor) {}
                            }
                        }
                    }
                cameraInstance.preview = preview

                val recorder = Recorder.Builder()
                    .setExecutor(executor)
                    .build()
                val videoCapture = VideoCapture.withOutput(recorder)
                cameraInstance.videoCapture = videoCapture

                val camera = cameraProvider.bindToLifecycle(
                    activity as LifecycleOwner,
                    cameraSelector,
                    preview,
                    videoCapture
                )
                cameraInstance.camera = camera

                val segmentFile = File(activity.cacheDir, "segment_${System.currentTimeMillis()}_${cameraInstance.currentSegmentIndex}.mp4")
                cameraInstance.currentSegmentIndex++
                cameraInstance.segmentFiles.add(segmentFile)

                val outputOptions = FileOutputOptions.Builder(segmentFile).build()
                val recording = videoCapture.output
                    .prepareRecording(activity, outputOptions)
                    .withAudioEnabled()
                    .start(ContextCompat.getMainExecutor(activity)) { event -> }

                cameraInstance.recording = recording
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
            var totalDuration = 0L
            var muxerStarted = false
            
            for (segmentFile in segmentFiles) {
                val extractor = MediaExtractor()
                extractor.setDataSource(segmentFile.absolutePath)
                
                val trackCount = extractor.trackCount
                for (i in 0 until trackCount) {
                    val format = extractor.getTrackFormat(i)
                    val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                    
                    if (mime.startsWith("video/")) {
                        if (videoTrackIndex < 0) {
                            videoTrackIndex = muxer.addTrack(format)
                        }
                    } else if (mime.startsWith("audio/")) {
                        if (audioTrackIndex < 0) {
                            audioTrackIndex = muxer.addTrack(format)
                        }
                    }
                }
                
                if (!muxerStarted && (videoTrackIndex >= 0 || audioTrackIndex >= 0)) {
                    muxer.start()
                    muxerStarted = true
                }
                
                for (i in 0 until trackCount) {
                    val format = extractor.getTrackFormat(i)
                    val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                    
                    if ((mime.startsWith("video/") && videoTrackIndex >= 0) ||
                        (mime.startsWith("audio/") && audioTrackIndex >= 0)) {
                        extractor.selectTrack(i)
                        val trackIndex = if (mime.startsWith("video/")) videoTrackIndex else audioTrackIndex
                        copyTrack(extractor, muxer, trackIndex)
                    }
                }
                
                extractor.release()
                totalDuration += (segmentFile.length() / 1000)
            }
            
            muxer.stop()
            muxer.release()
            
            return outputFile
        } catch (e: Exception) {
            try {
                muxer.stop()
            } catch (e2: Exception) {
            }
            try {
                muxer.release()
            } catch (e2: Exception) {
            }
            if (outputFile.exists()) {
                outputFile.delete()
            }
            throw e
        }
    }

    private fun copyTrack(extractor: MediaExtractor, muxer: MediaMuxer, trackIndex: Int) {
        val bufferSize = 256 * 1024
        val buffer = android.media.MediaCodec.BufferInfo()
        val byteBuffer = android.nio.ByteBuffer.allocate(bufferSize)
        
        while (true) {
            val sampleSize = extractor.readSampleData(byteBuffer, 0)
            
            if (sampleSize < 0) {
                break
            }
            
            buffer.presentationTimeUs = extractor.sampleTime
            buffer.size = sampleSize
            buffer.offset = 0
            buffer.flags = extractor.sampleFlags
            
            byteBuffer.position(0)
            byteBuffer.limit(sampleSize)
            muxer.writeSampleData(trackIndex, byteBuffer, buffer)
            extractor.advance()
        }
    }

    private fun cleanupSegmentFiles(segmentFiles: List<File>) {
        for (file in segmentFiles) {
            try {
                if (file.exists()) {
                    file.delete()
                }
            } catch (e: Exception) {
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
