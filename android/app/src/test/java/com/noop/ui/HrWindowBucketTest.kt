package com.noop.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Locks the Today HR card's window → bucket contract: the whole point of the window selector is that a
 * SHORTER window is read at a FINER bucket (so recent HR isn't flattened into 5-minute averages), while
 * [HrWindow.TODAY] keeps the established 5-minute day average. If someone changes the ~600-point target or
 * the formula, this catches the resolution shift.
 */
class HrWindowBucketTest {

    @Test fun today_keeps_the_five_minute_day_average() {
        assertEquals(300L, HrWindow.TODAY.bucketSeconds())
    }

    @Test fun rolling_windows_use_the_expected_finer_buckets() {
        // ~600 points across the span: hours*3600/600 = hours*6 seconds.
        assertEquals(6L, HrWindow.H1.bucketSeconds())    // 1h  → 6s
        assertEquals(18L, HrWindow.H3.bucketSeconds())   // 3h  → 18s
        assertEquals(36L, HrWindow.H6.bucketSeconds())   // 6h  → 36s
        assertEquals(72L, HrWindow.H12.bucketSeconds())  // 12h → 72s
        assertEquals(144L, HrWindow.H24.bucketSeconds()) // 24h → 144s
    }

    @Test fun shorter_window_is_never_coarser_than_a_longer_one() {
        val ordered = listOf(HrWindow.H1, HrWindow.H3, HrWindow.H6, HrWindow.H12, HrWindow.H24)
        val buckets = ordered.map { it.bucketSeconds() }
        assertEquals(buckets, buckets.sorted())          // monotonic: finer → coarser as the span grows
    }

    @Test fun every_bucket_stays_within_the_raw_to_day_bounds() {
        HrWindow.entries.forEach { w ->
            val b = w.bucketSeconds()
            assertTrue("$w bucket $b below raw floor", b >= 1L)
            assertTrue("$w bucket $b above the 5-min day cap", b <= 300L)
        }
    }
}
