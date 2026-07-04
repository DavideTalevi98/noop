package com.noop.analytics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

/**
 * Locks the `detectSleep` memo-key fingerprint (#707 parity). The cache is only safe if a change to ANY
 * keyed input re-keys to a fresh compute — a stale hit would hand back the wrong night's sleep. Each
 * stream fold folds the count and every (ts, quantized value), so this asserts: identical input → identical
 * fingerprint (a genuine hit), and every distinct perturbation (a value, a ts, the count) → a DIFFERENT
 * fingerprint (no false hit). The DetectKey combines these per stream plus tz/wristOff/band/v2, so
 * per-field sensitivity here + the key using every field (see detectSleep) = a complete key.
 */
class SleepStagerDetectFingerprintTest {

    private data class S(val ts: Long, val v: Long)
    private fun fp(list: List<S>) = SleepStager.streamFingerprint(list, { it.ts }) { it.v }

    private val base = (0 until 200).map { S(1_700_000_000L + it, (it % 37).toLong()) }

    @Test fun identical_input_folds_identically() {
        assertEquals(fp(base), fp(base.map { it.copy() }))     // same data, distinct instances → same fp
    }

    @Test fun a_changed_value_re_keys() {
        val perturbed = base.toMutableList().also { it[123] = it[123].copy(v = it[123].v + 1) }
        assertNotEquals(fp(base), fp(perturbed))
    }

    @Test fun a_changed_ts_re_keys() {
        val perturbed = base.toMutableList().also { it[50] = it[50].copy(ts = it[50].ts + 1) }
        assertNotEquals(fp(base), fp(perturbed))
    }

    @Test fun a_changed_count_re_keys() {
        assertNotEquals(fp(base), fp(base.dropLast(1)))        // truncation must not alias
        assertNotEquals(fp(base), fp(base + S(1_700_000_300L, 5L)))
    }

    @Test fun empty_stream_is_stable() {
        assertEquals(fp(emptyList()), fp(emptyList()))
    }
}
