package com.noop.analytics

import com.noop.data.DailyMetric
import com.noop.data.HrSample
import com.noop.data.RrInterval
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.sin

class ANSEarlySleepEngineTest {

    private fun snap(hr: Double, hrv: Double, resp: Double) =
        ANSEarlySleepEngine.NightSnapshot(hr, hrv, resp)

    private fun baselineHistory(
        count: Int = 10,
        hr: Double = 52.0,
        hrv: Double = 60.0,
        resp: Double = 14.0,
    ) = (0 until count).map { i ->
        val jitter = (i % 3) - 1.0
        snap(hr + jitter, hrv + jitter, resp + jitter * 0.1)
    }

    @Test
    fun insufficientHistory() {
        val tonight = snap(50.0, 65.0, 13.0)
        assertNull(ANSEarlySleepEngine.evaluate(tonight, baselineHistory(5)))
    }

    @Test
    fun goodChargeWhenAllSignalsBetter() {
        val history = baselineHistory(hr = 55.0, hrv = 55.0, resp = 15.0)
        val tonight = snap(48.0, 70.0, 13.0)
        val r = ANSEarlySleepEngine.evaluate(tonight, history)!!
        assertTrue(r.charge >= 67.0)
        assertEquals(ANSEarlySleepEngine.Level.GOOD, r.level)
        assertTrue(r.compositeZ > 0)
    }

    @Test
    fun compromisedWhenHRAndHRVWorse() {
        val history = baselineHistory(hr = 50.0, hrv = 65.0, resp = 14.0)
        val tonight = snap(60.0, 45.0, 16.0)
        val r = ANSEarlySleepEngine.evaluate(tonight, history)!!
        assertTrue(r.charge < 34.0)
        assertEquals(ANSEarlySleepEngine.Level.COMPROMISED, r.level)
        assertTrue(r.compositeZ < 0)
    }

    @Test
    fun snapshotFromSyntheticStreams() {
        val dev = "test"
        val onset = 1_700_000_000L
        val start = onset + ANSEarlySleepEngine.onsetDelaySec
        val hr = mutableListOf<HrSample>()
        val rr = mutableListOf<RrInterval>()
        for (i in 0 until 4 * 3600) {
            val ts = start + i
            hr.add(HrSample(dev, ts.toLong(), 50 + (i % 4)))
            val mod = (40 * sin(i / 4.0)).toInt()
            rr.add(RrInterval(dev, ts.toLong(), 1000 + mod))
        }
        assertNotNull(ANSEarlySleepEngine.snapshot(onset, hr, rr))
    }
}
