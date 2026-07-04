package com.noop.analytics

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate

/**
 * Locks the analyzeDay hot-path optimization: the integer UTC-bounds membership test that replaced the
 * per-sample `dayString(ts, off) == day` DateTimeFormatter must be BYTE-IDENTICAL to it. If they ever
 * diverge, samples would be attributed to the wrong calendar day (wrong step/calorie/Effort totals), so
 * this sweeps timestamps across the midnight boundary at a range of fixed offsets and asserts the two
 * agree at every point.
 */
class AnalyticsEngineDayBoundsTest {

    @Test fun integerBounds_match_dayString_across_midnight_and_offsets() {
        val anchor = 1_700_000_000L // 2023-11-14T…Z
        // UTC, and the fixed-offset extremes NOOP actually threads (west/east of UTC, incl. the ±13h edges).
        for (off in listOf(0L, -4 * 3600L, 5 * 3600L, 13 * 3600L, -12 * 3600L, 14 * 3600L)) {
            val day = AnalyticsEngine.dayString(anchor, off)
            val start = AnalyticsEngine.dayStartUtcSeconds(day)
            // ±28h around the anchor at a prime step, so both midnight edges of `day` are crossed densely.
            var ts = anchor - 100_800L
            while (ts < anchor + 100_800L) {
                val viaFormatter = AnalyticsEngine.dayString(ts, off) == day
                val viaBounds = (ts + off) in start until (start + 86_400L)
                assertEquals("ts=$ts off=$off", viaFormatter, viaBounds)
                ts += 97L
            }
        }
    }

    @Test fun dayStartUtcSeconds_is_utc_midnight() {
        // 2023-11-14 UTC midnight = 1_700_000_000 - (offset into the day). Spot-check a couple of days.
        assertEquals(
            LocalDate.parse("2023-11-14").toEpochDay() * 86_400L,
            AnalyticsEngine.dayStartUtcSeconds("2023-11-14"),
        )
        assertEquals(0L, AnalyticsEngine.dayStartUtcSeconds("1970-01-01"))
    }
}
