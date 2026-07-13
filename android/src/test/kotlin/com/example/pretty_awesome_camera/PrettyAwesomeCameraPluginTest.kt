package com.example.pretty_awesome_camera

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import kotlin.test.Test

/*
 * This demonstrates a simple unit test of the Kotlin portion of this plugin's implementation.
 *
 * Once you have built the plugin's example app, you can run these tests from the command
 * line by running `./gradlew testDebugUnitTest` in the `example/android/` directory, or
 * you can run them directly from IDEs that support JUnit such as Android Studio.
 */

internal class PrettyAwesomeCameraPluginTest {
    @Test
    fun onMethodCall_getPlatformVersion_returnsExpectedValue() {
        val plugin = PrettyAwesomeCameraPlugin()

        val call = MethodCall("getPlatformVersion", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success("Android " + android.os.Build.VERSION.RELEASE)
    }

    @Test
    fun onMethodCall_createCamera_acceptsLegacyConfig() {
        val plugin = PrettyAwesomeCameraPlugin()
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)

        val call = MethodCall(
            "createCamera",
            mapOf(
                "camera" to mapOf(
                    "name" to "Back Camera",
                    "lensDirection" to "back",
                    "sensorOrientation" to 90
                )
            )
        )
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success(0)
    }

    @Test
    fun onMethodCall_createCamera_rejectsUnknownPreset() {
        val plugin = PrettyAwesomeCameraPlugin()
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)

        val call = MethodCall(
            "createCamera",
            mapOf(
                "camera" to mapOf(
                    "name" to "Back Camera",
                    "lensDirection" to "back",
                    "sensorOrientation" to 90
                ),
                "preset" to "tiny"
            )
        )
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            "INVALID_ARGUMENT",
            "Unsupported resolution preset: tiny",
            null
        )
    }

    @Test
    fun onMethodCall_createCamera_rejectsInvalidVideoBitrate() {
        val plugin = PrettyAwesomeCameraPlugin()
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)

        val call = MethodCall(
            "createCamera",
            mapOf(
                "camera" to mapOf(
                    "name" to "Back Camera",
                    "lensDirection" to "back",
                    "sensorOrientation" to 90
                ),
                "preset" to "medium",
                "videoBitrate" to 0
            )
        )
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            "INVALID_ARGUMENT",
            "videoBitrate must be greater than zero",
            null
        )
    }

    @Test
    fun onMethodCall_createCamera_rejectsFractionalVideoBitrate() {
        val plugin = PrettyAwesomeCameraPlugin()
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(createCameraCall(videoBitrate = 2_500_000.5), mockResult)

        Mockito.verify(mockResult).error(
            "INVALID_ARGUMENT",
            "videoBitrate must be an integer",
            null
        )
    }

    @Test
    fun onMethodCall_createCamera_rejectsVideoBitrateAboveSanityCeiling() {
        val plugin = PrettyAwesomeCameraPlugin()
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(createCameraCall(videoBitrate = 100_000_001L), mockResult)

        Mockito.verify(mockResult).error(
            "INVALID_ARGUMENT",
            "videoBitrate must be at most 100000000",
            null
        )
    }

    @Test
    fun onMethodCall_createCamera_acceptsVideoBitrateAtSanityCeiling() {
        val plugin = PrettyAwesomeCameraPlugin()
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(createCameraCall(videoBitrate = 100_000_000L), mockResult)

        Mockito.verify(mockResult).success(0)
    }

    private fun createCameraCall(videoBitrate: Any): MethodCall = MethodCall(
        "createCamera",
        mapOf(
            "camera" to mapOf(
                "name" to "Back Camera",
                "lensDirection" to "back",
                "sensorOrientation" to 90
            ),
            "preset" to "medium",
            "videoBitrate" to videoBitrate
        )
    )
}
