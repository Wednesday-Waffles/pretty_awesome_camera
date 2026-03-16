package com.example.waffle_camera_plugin

import android.app.Activity
import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
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
        var recording: Recording? = null
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
                
                val preview = Preview.Builder()
                    .build()
                cameraInstance.preview = preview
                
                val textureEntry = binding.textureRegistry.createSurfaceTexture()
                cameraInstance.textureEntry = textureEntry
                
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
            val file = File(activity.cacheDir, "recording_${System.currentTimeMillis()}.mp4")
            val outputOptions = FileOutputOptions.Builder(file).build()

            val recording = videoCapture.output
                .prepareRecording(activity, outputOptions)
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
                val file = File(activity?.cacheDir, "recording_${System.currentTimeMillis()}.mp4")
                result.success(file.absolutePath)
            } catch (e: Exception) {
                result.error("STOP_ERROR", e.message, null)
            }
        } else {
            result.error("NOT_RECORDING", "No active recording", null)
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
