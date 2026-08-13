package com.example.pretty_awesome_camera

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * The salvage policy is the kill switch. If it fails open, upgrading the
 * plugin changes recording behavior for everyone regardless of the remote
 * flag, which is the opposite of what a kill switch is for.
 */
internal class SalvagePolicyContractTest {

    @Test
    fun normalize_knownPolicies_arePreserved() {
        assertEquals(SalvagePolicyContract.OFF, SalvagePolicyContract.normalize("off"))
        assertEquals(SalvagePolicyContract.SEAL, SalvagePolicyContract.normalize("seal"))
        assertEquals(
            SalvagePolicyContract.SEAL_INTERRUPT_ONLY,
            SalvagePolicyContract.normalize("seal_interrupt_only")
        )
    }

    @Test
    fun normalize_unknownInput_failsClosed() {
        // Null, empty, a typo, a future policy this build predates, and a
        // near-miss on a real value all have to land on OFF.
        for (raw in listOf(null, "", "SEAL", "seal ", "seal_all", "true", "1")) {
            assertEquals(
                SalvagePolicyContract.OFF,
                SalvagePolicyContract.normalize(raw),
                "expected $raw to fail closed"
            )
        }
    }

    @Test
    fun allowsSeal_off_neverSeals() {
        assertFalse(SalvagePolicyContract.allowsSeal("off", isBackgroundTrigger = false))
        assertFalse(SalvagePolicyContract.allowsSeal("off", isBackgroundTrigger = true))
        assertFalse(SalvagePolicyContract.allowsSeal(null, isBackgroundTrigger = false))
        assertFalse(SalvagePolicyContract.allowsSeal(null, isBackgroundTrigger = true))
    }

    @Test
    fun allowsSeal_seal_sealsBothTriggers() {
        assertTrue(SalvagePolicyContract.allowsSeal("seal", isBackgroundTrigger = false))
        assertTrue(SalvagePolicyContract.allowsSeal("seal", isBackgroundTrigger = true))
    }

    @Test
    fun allowsSeal_sealInterruptOnly_leavesBackgroundingToTheCaller() {
        // This is the non-regression case: with pause-on-background enabled, a
        // two-second app switch must keep resuming silently instead of raising
        // a three-way prompt.
        assertTrue(
            SalvagePolicyContract.allowsSeal("seal_interrupt_only", isBackgroundTrigger = false)
        )
        assertFalse(
            SalvagePolicyContract.allowsSeal("seal_interrupt_only", isBackgroundTrigger = true)
        )
    }
}
