package com.noop.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.roundToInt
import kotlin.math.sin

/** Spot HRV from v26 PPG bursts — synthetic sine + median GOOD helper. Twin of Swift PpgSpotHrvTests. */
class PpgSpotHrvTest {

    @Test
    fun cleanSineBurstYieldsSpot() {
        val records = sineRecords(bpm = 60.0, seconds = 40)
        val spots = PpgSpotHrv.derive(records)
        assertEquals(1, spots.size)
        val s = spots.first()
        assertTrue(s.rmssdMs > 0)
        assertEquals(60.0, s.hrBpm, 8.0)
        assertTrue(s.quality in setOf("GOOD", "COARSE", "POOR"))
    }

    @Test
    fun shortBurstDropped() {
        assertTrue(PpgSpotHrv.derive(sineRecords(bpm = 70.0, seconds = 12)).isEmpty())
    }

    @Test
    fun medianGoodIgnoresCoarseAndPoor() {
        val samples = listOf(
            PpgSpotHrv.Sample(1, 40.0, 60.0, 5, "POOR"),
            PpgSpotHrv.Sample(2, 80.0, 55.0, 30, "GOOD"),
            PpgSpotHrv.Sample(3, 100.0, 58.0, 28, "GOOD"),
            PpgSpotHrv.Sample(4, 50.0, 62.0, 15, "COARSE"),
        )
        assertEquals(90.0, PpgSpotHrv.medianGoodRmssd(samples)!!, 1e-9)
        assertNull(PpgSpotHrv.medianGoodRmssd(samples.filter { it.quality != "GOOD" }))
    }

    private fun sineRecords(bpm: Double, seconds: Int): List<Pair<Long, IntArray>> {
        val fs = PpgSpotHrv.SAMPLE_RATE_HZ
        val base = 1_780_000_000L
        return (0 until seconds).map { s ->
            val samples = IntArray(fs) { i ->
                val t = s + i / fs.toDouble()
                val phase = 2 * PI * (bpm / 60.0) * t
                (1000.0 * sin(phase)).roundToInt()
            }
            (base + s) to samples
        }
    }
}
