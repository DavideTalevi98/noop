package com.noop.ble

import com.noop.data.InsertCounts
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins the success-side observability the log forensics flagged as the blind spot (#150): NOOP logged
 * FAILURES (decoded-to-0) but never SUCCESSES, so a strap log couldn't tell a banking strap from a
 * broken one. Covers the pure tally + summary helpers driving the new
 * "Backfill: session persisted N rows (M with motion) across K night(s)" line. Mirrors the Swift
 * BackfillerSessionTallyTests.
 */
class BackfillerSessionTallyTest {

    // rows = biometric streams only (HR, R-R, SpO2, skin-temp, resp, gravity); events/battery/steps are
    // housekeeping and must NOT inflate the count (matches the Swift tuple, which has no steps). motion = gravity.
    @Test fun chunkTallySumsBiometricRowsAndGravityOnly() {
        val counts = InsertCounts(hr = 10, rr = 4, events = 99, battery = 7, spo2 = 3, skinTemp = 2, steps = 50, resp = 1, gravity = 5)
        val (rows, motion, nights) = Backfiller.chunkTally(counts, emptyList())
        assertEquals(10 + 4 + 3 + 2 + 1 + 5, rows) // 25 — events(99)/battery(7)/steps(50) excluded
        assertEquals(5, motion)
        assertTrue(nights.isEmpty())
    }

    // nights collapse timestamps to distinct day-keys (ts / 86400): a chunk crossing a day boundary
    // counts two nights; same-day samples count once.
    @Test fun chunkTallyNightsAreDistinctDayKeys() {
        val day0 = 1_700_000_000L
        val sameDay = day0 + 3_600L
        val nextDay = day0 + 86_400L
        val (_, _, nights) = Backfiller.chunkTally(InsertCounts(), listOf(day0, sameDay, nextDay))
        assertEquals(setOf(day0 / 86_400L, nextDay / 86_400L), nights)
        assertEquals(2, nights.size)
    }

    // Silent when nothing persisted, so a console-only / caught-up session doesn't claim a false success.
    @Test fun sessionSummaryNullWhenNoRows() {
        assertNull(Backfiller.sessionSummaryLine(0, 0, 0, 0))
    }

    @Test fun sessionSummaryFormat() {
        assertEquals(
            "Backfill: session persisted 240 rows (180 with motion, 12 skin-temp) across 3 night(s).",
            Backfiller.sessionSummaryLine(240, 180, 12, 3),
        )
    }

    // #727: a strap banking HR/RR-only records (no DSP sleep block) persists rows but ZERO skin-temp,
    // so the line surfaces that 0 and "skin temp never appears" reports are self-diagnosing from the log.
    @Test fun sessionSummaryShowsZeroSkinTemp() {
        assertEquals(
            "Backfill: session persisted 872 rows (172 with motion, 0 skin-temp) across 1 night(s).",
            Backfiller.sessionSummaryLine(872, 172, 0, 1),
        )
    }

    // #783: trim=0xFFFFFFFF on a connection that banked NOTHING keeps the "fully charge it" advice.
    @Test fun noCursorChargeAdviceWhenConnectionBankedNothing() {
        assertEquals(
            "Backfill: strap reported no flash cursor (trim=0xFFFFFFFF) — it has no banked history to " +
                "offload. This is a clock/charge state on the strap, not a decode problem; fully charge " +
                "it and reconnect so it starts banking.",
            Backfiller.noCursorLine(0),
        )
    }

    // #783: the SAME sentinel after a real drain (the #364 auto-continuation's normal terminal state) is
    // neutral end-of-data, NOT a charge warning — the false-alarm the issue reported.
    @Test fun noCursorNeutralWhenConnectionBankedRows() {
        assertEquals(
            "Backfill: end-of-data (trim=0xFFFFFFFF) — cursor caught up after offloading 692 " +
                "row(s); the normal terminal state of a healthy drain, not a charge problem.",
            Backfiller.noCursorLine(692),
        )
    }
}
