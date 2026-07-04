package com.noop.analytics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Locks [IntelligenceEngine.daySliceFromNight]: for a PAST day the calendar-day streams (dayHr/daySteps/
 * dayGrav) are a non-truncated subset of the night window already in memory, so re-reading them from the DB
 * is redundant — the slice must equal an in-range filter of the night list. And the shortcut must DECLINE
 * (return null → caller reads directly) for the two unsafe cases: TODAY's day runs past the night cap, and a
 * night read at STREAM_LIMIT may be truncated inside the day span. If any of that drifts, samples would be
 * attributed to the wrong day / dropped, so this is the safety net for the read-skip.
 */
class IntelligenceEngineDaySliceTest {

    private data class S(val ts: Long)

    // A past day's night window: [dayStart - 30h, nextMidnight]; the calendar day [dayStart, dayStart+86400-1]
    // sits strictly inside it. Mirrors the real IntelligenceEngine bounds.
    private val dayStart = 1_700_000_000L
    private val nightLo = dayStart - 30 * 3_600L
    private val nightHi = dayStart + 86_400L            // = nextMidnight (past-day `to`)
    private val dayLo = dayStart
    private val dayHi = dayStart + 86_400L - 1
    private val night = (nightLo..nightHi step 60L).map { S(it) }   // one sample a minute across the window

    @Test fun pastDay_returns_the_in_range_filter_of_the_night_list() {
        val slice = IntelligenceEngine.daySliceFromNight(night, nightLo, nightHi, dayLo, dayHi) { it.ts }
        // Byte-identical to filtering the night list (which, for a complete night, equals the direct read).
        assertEquals(night.filter { it.ts in dayLo..dayHi }, slice)
        // Nothing outside the day leaks in; order is preserved (ascending).
        assertTrue(slice!!.all { it.ts in dayLo..dayHi })
        assertEquals(slice.sortedBy { it.ts }, slice)
    }

    @Test fun today_dayEnd_past_the_night_cap_declines() {
        // TODAY: the night window caps at dayStart+18h, so the calendar day (to +24h) reaches past it.
        val todayNightHi = dayStart + 18 * 3_600L
        assertNull(IntelligenceEngine.daySliceFromNight(night, nightLo, todayNightHi, dayLo, dayHi) { it.ts })
    }

    @Test fun truncated_night_read_declines() {
        // A night read that returned exactly STREAM_LIMIT rows may be truncated inside the day span.
        val truncated = (0 until IntelligenceEngine.STREAM_LIMIT).map { S(it.toLong()) }
        assertNull(
            IntelligenceEngine.daySliceFromNight(truncated, 0L, IntelligenceEngine.STREAM_LIMIT.toLong(), 0L, 100L) { it.ts },
        )
    }

    @Test fun bounds_are_inclusive_on_both_ends() {
        // The DAO range is inclusive [dayLo, dayHi]; the filter must keep the boundary samples.
        val edge = listOf(S(dayLo - 1), S(dayLo), S(dayHi), S(dayHi + 1))
        val slice = IntelligenceEngine.daySliceFromNight(edge, nightLo, nightHi, dayLo, dayHi) { it.ts }
        assertEquals(listOf(S(dayLo), S(dayHi)), slice)
    }
}
