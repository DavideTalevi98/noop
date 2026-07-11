package com.noop.analytics

import com.noop.data.DailyMetric
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DualWindowReadinessTest {

    private fun d(day: String, hrv: Double?, rhr: Int?) = DailyMetric(
        deviceId = "test",
        day = day,
        totalSleepMin = null,
        efficiency = null,
        deepMin = null,
        remMin = null,
        lightMin = null,
        disturbances = null,
        restingHr = rhr,
        avgHrv = hrv,
        recovery = null,
        strain = null,
        exerciseCount = null,
        spo2Pct = null,
        skinTempDevC = null,
        respRateBpm = null,
    )

    @Test
    fun hrvSuppressedWhenAcuteDips() {
        val hist = (1..20).map { (58.0 + (it % 4)) }
        val r = DualWindowReadiness.evaluate(
            key = "hrv", label = "HRV",
            history = hist, today = 40.0,
            higherIsBetter = true, cfg = Baselines.hrvCfg,
        )!!
        assertEquals(DualWindowReadiness.State.SUPPRESSED, r.state)
        assertTrue(r.acuteMean < r.normalLower)
    }

    @Test
    fun endToEndFromDailyMetrics() {
        val days = mutableListOf<DailyMetric>()
        for (i in 1..25) days.add(d("2024-02-%02d".format(i), 60.0, 50))
        for (i in 26..30) days.add(d("2024-02-%02d".format(i), 42.0, 58))
        val r = DualWindowReadiness.evaluate(days, today = "2024-02-30")
        assertEquals(DualWindowReadiness.State.SUPPRESSED, r.hrv?.state)
        assertEquals(DualWindowReadiness.State.SUPPRESSED, r.rhr?.state)
        assertEquals(DualWindowReadiness.State.SUPPRESSED, r.overall)
    }
}
