package com.example.pretty_awesome_camera

import androidx.camera.video.VideoRecordEvent
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

internal class RecordingFinalizeContractTest {
    @Test
    fun decide_errorNoneWithValidData_returnsPath() {
        val decision = RecordingFinalizeContract.decide(
            VideoRecordEvent.Finalize.ERROR_NONE,
            hasValidData = true
        )

        assertEquals(FinalizeAction.RETURN_PATH, decision.action)
    }

    @Test
    fun decide_errorNoneWithoutValidData_throwsMissingOutput() {
        val decision = RecordingFinalizeContract.decide(
            VideoRecordEvent.Finalize.ERROR_NONE,
            hasValidData = false
        )

        assertEquals(FinalizeAction.THROW_ERROR, decision.action)
        assertEquals("STOP_OUTPUT_MISSING", decision.errorCode)
        assertTrue(decision.deletePartial)
    }

    @Test
    fun decide_sourceInactiveWithValidData_returnsPath() {
        val decision = RecordingFinalizeContract.decide(
            VideoRecordEvent.Finalize.ERROR_SOURCE_INACTIVE,
            hasValidData = true
        )

        assertEquals(FinalizeAction.RETURN_PATH, decision.action)
    }

    @Test
    fun decide_durationLimitWithValidData_returnsPath() {
        val decision = RecordingFinalizeContract.decide(
            VideoRecordEvent.Finalize.ERROR_DURATION_LIMIT_REACHED,
            hasValidData = true
        )

        assertEquals(FinalizeAction.RETURN_PATH, decision.action)
    }

    @Test
    fun decide_insufficientStorageWithValidData_returnsPath() {
        val decision = RecordingFinalizeContract.decide(
            VideoRecordEvent.Finalize.ERROR_INSUFFICIENT_STORAGE,
            hasValidData = true
        )

        assertEquals(FinalizeAction.RETURN_PATH, decision.action)
    }

    @Test
    fun decide_fileSizeLimitWithValidData_returnsPath() {
        val decision = RecordingFinalizeContract.decide(
            VideoRecordEvent.Finalize.ERROR_FILE_SIZE_LIMIT_REACHED,
            hasValidData = true
        )

        assertEquals(FinalizeAction.RETURN_PATH, decision.action)
    }

    @Test
    fun decide_validDataWarningsWithoutData_throwMissingOutput() {
        val warningErrors = listOf(
            VideoRecordEvent.Finalize.ERROR_SOURCE_INACTIVE,
            VideoRecordEvent.Finalize.ERROR_DURATION_LIMIT_REACHED,
            VideoRecordEvent.Finalize.ERROR_INSUFFICIENT_STORAGE,
            VideoRecordEvent.Finalize.ERROR_FILE_SIZE_LIMIT_REACHED
        )

        for (error in warningErrors) {
            val decision = RecordingFinalizeContract.decide(error, hasValidData = false)

            assertEquals(FinalizeAction.THROW_ERROR, decision.action)
            assertEquals("STOP_OUTPUT_MISSING", decision.errorCode)
            assertTrue(decision.deletePartial)
        }
    }

    @Test
    fun decide_noValidData_returnsNullAndDeletesPartial() {
        val decision = RecordingFinalizeContract.decide(
            VideoRecordEvent.Finalize.ERROR_NO_VALID_DATA,
            hasValidData = false
        )

        assertEquals(FinalizeAction.RETURN_NULL, decision.action)
        assertTrue(decision.deletePartial)
    }

    @Test
    fun decide_encodingFailed_throwsStructuredError() {
        val decision = RecordingFinalizeContract.decide(
            VideoRecordEvent.Finalize.ERROR_ENCODING_FAILED,
            hasValidData = true
        )

        assertEquals(FinalizeAction.THROW_ERROR, decision.action)
        assertEquals("STOP_ENCODING_FAILED", decision.errorCode)
        assertTrue(decision.deletePartial)
    }

    @Test
    fun decide_recorderError_throwsStructuredError() {
        val decision = RecordingFinalizeContract.decide(
            VideoRecordEvent.Finalize.ERROR_RECORDER_ERROR,
            hasValidData = true
        )

        assertEquals(FinalizeAction.THROW_ERROR, decision.action)
        assertEquals("STOP_RECORDER_ERROR", decision.errorCode)
        assertTrue(decision.deletePartial)
    }

    @Test
    fun decide_invalidOutputOptions_throwsStructuredError() {
        val decision = RecordingFinalizeContract.decide(
            VideoRecordEvent.Finalize.ERROR_INVALID_OUTPUT_OPTIONS,
            hasValidData = true
        )

        assertEquals(FinalizeAction.THROW_ERROR, decision.action)
        assertEquals("STOP_INVALID_OUTPUT_OPTIONS", decision.errorCode)
        assertTrue(decision.deletePartial)
    }

    @Test
    fun decide_recordingGarbageCollected_throwsStructuredError() {
        val decision = RecordingFinalizeContract.decide(
            VideoRecordEvent.Finalize.ERROR_RECORDING_GARBAGE_COLLECTED,
            hasValidData = true
        )

        assertEquals(FinalizeAction.THROW_ERROR, decision.action)
        assertEquals("STOP_RECORDING_GARBAGE_COLLECTED", decision.errorCode)
        assertTrue(decision.deletePartial)
    }

    @Test
    fun decide_unknownError_throwsStructuredError() {
        val decision = RecordingFinalizeContract.decide(
            VideoRecordEvent.Finalize.ERROR_UNKNOWN,
            hasValidData = true
        )

        assertEquals(FinalizeAction.THROW_ERROR, decision.action)
        assertEquals("STOP_FINALIZE_ERROR", decision.errorCode)
        assertTrue(decision.deletePartial)
    }

    @Test
    fun errorName_mapsKnownCameraXConstants() {
        assertEquals(
            "ERROR_NO_VALID_DATA",
            RecordingFinalizeContract.errorName(VideoRecordEvent.Finalize.ERROR_NO_VALID_DATA)
        )
        assertEquals("ERROR_UNKNOWN_VALUE", RecordingFinalizeContract.errorName(999))
    }

    @Test
    fun stopTimeoutCode_matchesPlatformContract() {
        assertEquals("STOP_TIMEOUT", RecordingFinalizeContract.STOP_TIMEOUT)
    }
}
