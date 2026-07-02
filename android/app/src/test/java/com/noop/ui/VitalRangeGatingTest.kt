package com.noop.ui

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate

/**
 * Pins the vital-trend range gating: only offer ranges that reveal more than the next-shorter one, so a
 * short history doesn't show identical charts across W/M/3M/6M/1Y/ALL. WEEK is always offered (the
 * smallest window); each longer range unlocks once the data span exceeds the prior window. Mirrors the
 * Swift MetricDetailView.availableRanges (same order + rule).
 */
class VitalRangeGatingTest {

    /** N daily points ending on a fixed date (values irrelevant to the gate; only the day span matters). */
    private fun daysBack(n: Int): List<Pair<String, Double>> {
        val end = LocalDate.of(2026, 1, 31)
        return (0 until n).map { i -> end.minusDays((n - 1 - i).toLong()).toString() to 60.0 }
    }

    private fun labels(points: List<Pair<String, Double>>) =
        availableVitalRanges(points).map { it.label }

    @Test fun lessThanAWeekOffersOnlyWeek() {
        // 6 days (span 5): every window holds the same points, so only WEEK is offered — which suppresses
        // the toggle in the UI. (This is the reported "<1 week" case.)
        assertEquals(listOf("W"), labels(daysBack(6)))
    }

    @Test fun sevenDaySpanStillOnlyWeek() {
        // 8 points = span 7; MONTH needs span > 7, so it stays hidden at exactly a week.
        assertEquals(listOf("W"), labels(daysBack(8)))
    }

    @Test fun pastAWeekUnlocksMonth() {
        // span 8 (> 7): MONTH now reveals more than WEEK.
        assertEquals(listOf("W", "M"), labels(daysBack(9)))
    }

    @Test fun rangesUnlockAsHistoryGrows() {
        assertEquals(listOf("W", "M"), labels(daysBack(30)))                          // span 29: >7, not >30
        assertEquals(listOf("W", "M", "3M"), labels(daysBack(32)))                    // span 31 > 30
        assertEquals(listOf("W", "M", "3M", "6M"), labels(daysBack(120)))             // span 119 > 90
        assertEquals(listOf("W", "M", "3M", "6M", "1Y"), labels(daysBack(200)))       // span 199 > 180
        assertEquals(listOf("W", "M", "3M", "6M", "1Y", "ALL"), labels(daysBack(400))) // span 399 > 365
    }

    @Test fun emptyOrSinglePointOffersOnlyWeek() {
        assertEquals(listOf("W"), labels(emptyList()))
        assertEquals(listOf("W"), labels(daysBack(1)))
    }

    @Test fun availableRangesIsAlwaysAContiguousPrefix() {
        val full = listOf("W", "M", "3M", "6M", "1Y", "ALL")
        for (n in listOf(1, 6, 8, 9, 30, 32, 120, 200, 400)) {
            val got = labels(daysBack(n))
            assertEquals(got, full.take(got.size))
        }
    }
}
