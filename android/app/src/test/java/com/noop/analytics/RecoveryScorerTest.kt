package com.noop.analytics

import com.noop.data.HrSample
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Tests RecoveryScorer.restingHR — the night's lowest sustained 5-min block-mean HR, with guards that
 * reject lone-beat dips and dropout artifacts. Kotlin twin of the StrandAnalytics RecoveryScorerTests.
 */
class RecoveryScorerTest {

    private fun hs(ts: Long, bpm: Int) = HrSample("dev", ts, bpm)

    @Test
    fun restingHRLowestBlockMean() {
        // Two 5-min blocks: first averages 60, second averages 50 → resting = 50.
        val hr = ArrayList<HrSample>()
        val start = 1000L
        for (i in 0 until 300) hr.add(hs(start + i, 60))
        for (i in 0 until 300) hr.add(hs(start + 300 + i, 50))
        assertEquals(50, RecoveryScorer.restingHR(hr, start, start + 600))
    }

    @Test
    fun restingHRNilWhenNoSamples() {
        assertNull(RecoveryScorer.restingHR(emptyList(), 0L, 1000L))
    }

    @Test
    fun restingHRIgnoresLoneBeatDip() {
        // Two well-sampled blocks (60, 50) plus a single isolated low beat (30) alone in its own 5-min bin.
        // The lone beat must NOT become the floor — its bin has < restingHRMinBinSamples samples, so it is
        // dropped and the floor stays the real 50 (old code would have returned 30).
        val hr = ArrayList<HrSample>()
        val start = 1000L
        for (i in 0 until 300) hr.add(hs(start + i, 60))         // bin 0 → 60
        for (i in 0 until 300) hr.add(hs(start + 300 + i, 50))   // bin 1 → 50
        hr.add(hs(start + 600, 30))                              // bin 2 → lone beat
        assertEquals(50, RecoveryScorer.restingHR(hr, start, start + 900))
    }

    @Test
    fun restingHRRejectsImplausiblyLowBin() {
        // A fully-sampled bin whose mean is below the physiological floor (10 bpm dropout) is an artifact,
        // not a resting level: it is rejected and the floor stays the real 50 (old code would return 10).
        val hr = ArrayList<HrSample>()
        val start = 1000L
        for (i in 0 until 300) hr.add(hs(start + i, 60))         // bin 0 → 60
        for (i in 0 until 300) hr.add(hs(start + 300 + i, 50))   // bin 1 → 50
        for (i in 0 until 300) hr.add(hs(start + 600 + i, 10))   // bin 2 → 10 (< floor)
        assertEquals(50, RecoveryScorer.restingHR(hr, start, start + 900))
    }
}
