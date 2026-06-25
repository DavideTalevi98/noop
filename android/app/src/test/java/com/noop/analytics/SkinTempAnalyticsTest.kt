package com.noop.analytics

import com.noop.data.HrSample
import com.noop.data.SkinTempSample
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the WHOOP 5.0/MG skin-temperature pipeline added in AnalyticsEngine/IntelligenceEngine.
 *
 * Two parts, mirroring the codebase's "test the building block" convention (see BaselineSeedingTest):
 *  1. [AnalyticsEngine.wornNightlySkinTempC] — the new wear-gated nightly-mean logic (the part that
 *     turns raw skin_temp_raw@73 samples into a trustworthy per-night value).
 *  2. The seed→deviation flow over [Baselines.foldHistory]/[Baselines.deviation] with the standard
 *     `skin_temp` config — pinning the honest cold-start gate (<4 nights ⇒ no skinTempDevC) and that a
 *     real elevation surfaces as a positive deviation once seeded. All values APPROXIMATE.
 *
 * Skin-temp raw is u16 centi-°C (°C = raw/100); worn nightly values seen on real hardware were ~33–35 °C,
 * off-wrist/charging ~22–27 °C — which is exactly the contamination the wear-gate excludes.
 */
class SkinTempAnalyticsTest {

    private val dev = "my-whoop"

    private fun session(start: Long, durSec: Long) = DetectedSleep(
        start = start, end = start + durSec, efficiency = 0.9,
        stages = emptyList(), restingHR = 50, avgHRV = 60.0,
    )

    private fun hr(ts: Long, bpm: Int = 55) = HrSample(deviceId = dev, ts = ts, bpm = bpm)
    private fun skin(ts: Long, rawCentiC: Int) = SkinTempSample(deviceId = dev, ts = ts, raw = rawCentiC)

    // ── wornNightlySkinTempC ────────────────────────────────────────────────

    @Test
    fun meanOverWornInBedSamples() {
        val start = 1_000_000L
        val sess = listOf(session(start, 600))
        val hrs = (0 until 600).map { hr(start + it) }
        val temps = (0 until 600).map { skin(start + it, 3400) } // 34.00 °C
        val mean = AnalyticsEngine.wornNightlySkinTempC(sess, hrs, temps).mean
        assertEquals(34.0, mean!!, 1e-9)
    }

    @Test
    fun excludesSamplesWithoutConcurrentWornHr() {
        // The strap streams HR only on-wrist; skin-temp samples with no concurrent worn BPM are dropped.
        val start = 2_000_000L
        val sess = listOf(session(start, 600))
        val temps = (0 until 600).map { skin(start + it, 3400) }
        assertNull(AnalyticsEngine.wornNightlySkinTempC(sess, emptyList(), temps).mean)
    }

    @Test
    fun excludesDaytimeSamplesOutsideTheSleepSession() {
        // Daytime samples are in worn range (36 °C) AND have worn HR, but fall OUTSIDE the in-bed
        // session window, so only the in-bed 34 °C samples count. Isolates the session-window gate.
        val night = 3_000_000L
        val sess = listOf(session(night, 600))
        val inBedHr = (0 until 600).map { hr(night + it) }
        val inBedTemp = (0 until 600).map { skin(night + it, 3400) }
        val day = night + 10_000
        val dayHr = (0 until 600).map { hr(day + it) }
        val dayTemp = (0 until 600).map { skin(day + it, 3600) } // 36 °C, worn-range, but daytime
        val mean = AnalyticsEngine.wornNightlySkinTempC(sess, inBedHr + dayHr, inBedTemp + dayTemp).mean
        assertEquals(34.0, mean!!, 1e-9)
    }

    @Test
    fun excludesOnChargerAmbientEvenInBed() {
        // Mid-night on charger: HR still has stray worn-range values but skin temp drifts to ambient
        // (~22 °C) — which passes the strap's looser 20–45 decode gate but is below the worn floor.
        val start = 4_000_000L
        val sess = listOf(session(start, 600))
        val hrs = (0 until 600).map { hr(start + it) }
        val temps = (0 until 600).map { skin(start + it, 2200) } // 22 °C ambient
        assertNull(AnalyticsEngine.wornNightlySkinTempC(sess, hrs, temps).mean)
    }

    @Test
    fun belowMinSamplesIsNull() {
        val start = 5_000_000L
        val sess = listOf(session(start, 100))
        val hrs = (0 until 100).map { hr(start + it) }
        val temps = (0 until 100).map { skin(start + it, 3400) } // only 100 < MIN_SKIN_TEMP_SAMPLES
        assertNull(AnalyticsEngine.wornNightlySkinTempC(sess, hrs, temps).mean)
    }

    @Test
    fun emptyInputsAreNull() {
        assertNull(AnalyticsEngine.wornNightlySkinTempC(emptyList(), emptyList(), emptyList()).mean)
    }

    // #727: the funnel counts must expose which gate dropped the samples. 600 in-bed samples all have
    // worn HR; 200 of them drift to on-charger ambient (22 °C, below the 28 °C floor), so worn=inSession=600
    // but only plausible=400 feed the mean — the exact breakdown a strap log needs. Mirrors the Swift test.
    @Test
    fun funnelCountsExposeEachGate() {
        val start = 6_000_000L
        val sess = listOf(session(start, 600))
        val hrs = (0 until 600).map { hr(start + it) }
        val temps = (0 until 600).map { skin(start + it, if (it < 400) 3400 else 2200) } // 400 worn, 200 ambient
        val f = AnalyticsEngine.wornNightlySkinTempC(sess, hrs, temps)
        assertEquals(600, f.raw)
        assertEquals(600, f.worn)
        assertEquals(600, f.inSession)
        assertEquals(400, f.plausible)
        assertEquals(34.0, f.mean!!, 1e-9)
    }

    // ── skinTempFunnelLogLine (the diagnostic line, pure + tested like rhrFloorMeanLogLine) ───
    // #727: pinning the EXACT string locks the format AND the Swift/Android parity (the Swift
    // skinTempFunnelLogLine is byte-identical; StrandAnalytics can't compile on Linux CI, so this is
    // the verifiable half of that guarantee).

    @Test
    fun skinTempFunnelLogLine_healthyNight() {
        val f = SkinTempFunnel(mean = 30.6, raw = 412, worn = 380, inSession = 360, plausible = 355, minSamples = 300)
        assertEquals(
            "skintemp day=2026-06-24 raw=412 worn=380 inSession=360 plausible=355/300 " +
                "mean=30.6°C baseline=4/4 dev=+0.30",
            IntelligenceEngine.skinTempFunnelLogLine("2026-06-24", f, 0.30, 4),
        )
    }

    @Test
    fun skinTempFunnelLogLine_strapBankedNothing_isNilNotZero() {
        val f = SkinTempFunnel(mean = null, raw = 0, worn = 0, inSession = 0, plausible = 0, minSamples = 300)
        assertEquals(
            "skintemp day=2026-06-22 raw=0 worn=0 inSession=0 plausible=0/300 mean=nil baseline=2/4 dev=nil",
            IntelligenceEngine.skinTempFunnelLogLine("2026-06-22", f, null, 2),
        )
    }

    // ── seed → deviation (skin_temp baseline) ───────────────────────────────

    private val skinCfg = Baselines.metricCfg.getValue("skin_temp")

    @Test
    fun coldStart_belowSeed_baselineNotUsable() {
        // 3 nightly means (< minNightsSeed = 4): still CALIBRATING → skinTempDevC stays null.
        val nights: List<Double?> = listOf(33.5, 33.6, 33.4)
        assertFalse(Baselines.foldHistory(nights, skinCfg).usable)
    }

    @Test
    fun atSeed_usable_elevationShowsPositiveDeviation() {
        // 4 baseline nights ~33.5 °C; a +0.8 °C night surfaces as a clearly positive deviation —
        // the signal IllnessWatch reads as its skin-temp flag (fires at ≥ +0.6 °C).
        val nights: List<Double?> = listOf(33.5, 33.4, 33.6, 33.5)
        val base = Baselines.foldHistory(nights, skinCfg)
        assertTrue("4 valid nights must seed a usable skin-temp baseline", base.usable)
        val dev = Baselines.deviation(34.3, base).delta
        assertTrue("a +0.8 °C night must read as a clear positive deviation, was $dev", dev > 0.5)
    }
}
