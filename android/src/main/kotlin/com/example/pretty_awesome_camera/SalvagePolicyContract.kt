package com.example.pretty_awesome_camera

/**
 * Decides whether native may seal the in-flight segment by itself.
 *
 * The policy is chosen by Dart once per take and sent with the start call.
 * Native never infers it from pause state, because that would race Dart's own
 * lifecycle handling — the recorder and the plugin would each think they owned
 * the interruption.
 *
 * Pulled out as a plain object, like [RecordingFinalizeContract], so the gate
 * that decides whether this feature does anything at all is table-testable
 * without an Activity or a live CameraX recording.
 */
internal object SalvagePolicyContract {
    /** Seal nothing; behave exactly as the plugin did before salvage existed. */
    const val OFF = "off"

    /** Seal on interruption and on backgrounding. */
    const val SEAL = "seal"

    /**
     * Seal on genuine device contention only. Backgrounding stays with the
     * caller, which keeps an existing pause-on-background implementation in
     * charge — turning a working silent pause into a prompt on every app
     * switch would be a regression.
     */
    const val SEAL_INTERRUPT_ONLY = "seal_interrupt_only"

    /**
     * Anything unrecognised degrades to [OFF].
     *
     * This is the fail-closed half of the kill switch: an older or newer Dart
     * layer sending a policy this build does not know must not accidentally
     * enable sealing.
     */
    fun normalize(raw: String?): String = when (raw) {
        SEAL, SEAL_INTERRUPT_ONLY -> raw
        else -> OFF
    }

    /**
     * Whether [policy] admits a seal for this trigger.
     *
     * [isBackgroundTrigger] separates the two cases that differ: device
     * contention is always ours to handle when salvage is on at all, whereas
     * backgrounding is ours only under [SEAL].
     */
    fun allowsSeal(policy: String?, isBackgroundTrigger: Boolean): Boolean {
        return when (normalize(policy)) {
            OFF -> false
            SEAL -> true
            SEAL_INTERRUPT_ONLY -> !isBackgroundTrigger
            else -> false
        }
    }
}
