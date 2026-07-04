package com.example.pretty_awesome_camera

import androidx.camera.video.VideoRecordEvent

internal enum class FinalizeAction {
    RETURN_PATH,
    RETURN_NULL,
    THROW_ERROR
}

internal data class FinalizeDecision(
    val action: FinalizeAction,
    val errorCode: String? = null,
    val message: String? = null,
    val deletePartial: Boolean = false
)

internal object RecordingFinalizeContract {
    const val STOP_TIMEOUT = "STOP_TIMEOUT"
    const val STOP_FINALIZED = "STOP_FINALIZED"

    fun decide(error: Int, hasValidData: Boolean): FinalizeDecision {
        return when (error) {
            VideoRecordEvent.Finalize.ERROR_NONE ->
                if (hasValidData) {
                    FinalizeDecision(FinalizeAction.RETURN_PATH)
                } else {
                    FinalizeDecision(
                        action = FinalizeAction.THROW_ERROR,
                        errorCode = "STOP_OUTPUT_MISSING",
                        message = "CameraX finalized without an output file",
                        deletePartial = true
                    )
                }

            VideoRecordEvent.Finalize.ERROR_SOURCE_INACTIVE,
            VideoRecordEvent.Finalize.ERROR_DURATION_LIMIT_REACHED,
            VideoRecordEvent.Finalize.ERROR_INSUFFICIENT_STORAGE,
            VideoRecordEvent.Finalize.ERROR_FILE_SIZE_LIMIT_REACHED ->
                if (hasValidData) {
                    FinalizeDecision(FinalizeAction.RETURN_PATH)
                } else {
                    FinalizeDecision(
                        action = FinalizeAction.THROW_ERROR,
                        errorCode = "STOP_OUTPUT_MISSING",
                        message = "CameraX finalized with no playable data",
                        deletePartial = true
                    )
                }

            VideoRecordEvent.Finalize.ERROR_NO_VALID_DATA ->
                FinalizeDecision(
                    action = FinalizeAction.RETURN_NULL,
                    deletePartial = true
                )

            VideoRecordEvent.Finalize.ERROR_ENCODING_FAILED ->
                fatalFinalizeError("STOP_ENCODING_FAILED")

            VideoRecordEvent.Finalize.ERROR_RECORDER_ERROR ->
                fatalFinalizeError("STOP_RECORDER_ERROR")

            VideoRecordEvent.Finalize.ERROR_INVALID_OUTPUT_OPTIONS ->
                fatalFinalizeError("STOP_INVALID_OUTPUT_OPTIONS")

            VideoRecordEvent.Finalize.ERROR_RECORDING_GARBAGE_COLLECTED ->
                fatalFinalizeError("STOP_RECORDING_GARBAGE_COLLECTED")

            else ->
                fatalFinalizeError("STOP_FINALIZE_ERROR")
        }
    }

    fun errorName(error: Int): String {
        return when (error) {
            VideoRecordEvent.Finalize.ERROR_NONE -> "ERROR_NONE"
            VideoRecordEvent.Finalize.ERROR_UNKNOWN -> "ERROR_UNKNOWN"
            VideoRecordEvent.Finalize.ERROR_FILE_SIZE_LIMIT_REACHED -> "ERROR_FILE_SIZE_LIMIT_REACHED"
            VideoRecordEvent.Finalize.ERROR_INSUFFICIENT_STORAGE -> "ERROR_INSUFFICIENT_STORAGE"
            VideoRecordEvent.Finalize.ERROR_SOURCE_INACTIVE -> "ERROR_SOURCE_INACTIVE"
            VideoRecordEvent.Finalize.ERROR_INVALID_OUTPUT_OPTIONS -> "ERROR_INVALID_OUTPUT_OPTIONS"
            VideoRecordEvent.Finalize.ERROR_ENCODING_FAILED -> "ERROR_ENCODING_FAILED"
            VideoRecordEvent.Finalize.ERROR_RECORDER_ERROR -> "ERROR_RECORDER_ERROR"
            VideoRecordEvent.Finalize.ERROR_NO_VALID_DATA -> "ERROR_NO_VALID_DATA"
            VideoRecordEvent.Finalize.ERROR_DURATION_LIMIT_REACHED -> "ERROR_DURATION_LIMIT_REACHED"
            VideoRecordEvent.Finalize.ERROR_RECORDING_GARBAGE_COLLECTED -> "ERROR_RECORDING_GARBAGE_COLLECTED"
            else -> "ERROR_UNKNOWN_VALUE"
        }
    }

    fun hasValidData(
        outputExists: Boolean,
        outputLengthBytes: Long,
        recordedBytes: Long,
        recordedDurationNanos: Long
    ): Boolean {
        return outputExists &&
            outputLengthBytes > 0L &&
            recordedBytes > 0L &&
            recordedDurationNanos > 0L
    }

    private fun fatalFinalizeError(code: String): FinalizeDecision {
        return FinalizeDecision(
            action = FinalizeAction.THROW_ERROR,
            errorCode = code,
            message = "CameraX failed to finalize recording",
            deletePartial = true
        )
    }
}
