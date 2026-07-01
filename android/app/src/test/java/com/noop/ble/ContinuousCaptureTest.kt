package com.noop.ble

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirror of the Swift ContinuousCaptureTests: same window, same expectations. */
class ContinuousCaptureTest {

    private val m = ContinuousCaptureMode.OVERNIGHT

    @Test fun offIsNeverArmed() {
        assertFalse(ContinuousCapture.wantsStreamNow(ContinuousCaptureMode.OFF, 3 * 60))
        assertFalse(ContinuousCapture.wantsStreamNow(ContinuousCaptureMode.OFF, 23 * 60))
    }

    @Test fun alwaysIsAlwaysArmed() {
        assertTrue(ContinuousCapture.wantsStreamNow(ContinuousCaptureMode.ALWAYS, 3 * 60))
        assertTrue(ContinuousCapture.wantsStreamNow(ContinuousCaptureMode.ALWAYS, 15 * 60))
    }

    @Test fun overnightWrapsMidnight() {
        assertTrue(ContinuousCapture.wantsStreamNow(m, 23 * 60))          // 23:00 in
        assertTrue(ContinuousCapture.wantsStreamNow(m, 0))               // 00:00 in
        assertTrue(ContinuousCapture.wantsStreamNow(m, 3 * 60))          // 03:00 in
        assertTrue(ContinuousCapture.wantsStreamNow(m, 9 * 60 + 29))     // 09:29 in
    }

    @Test fun overnightExcludesDaytime() {
        assertFalse(ContinuousCapture.wantsStreamNow(m, 9 * 60 + 30))    // 09:30 out (exclusive end)
        assertFalse(ContinuousCapture.wantsStreamNow(m, 12 * 60))        // 12:00 out
        assertFalse(ContinuousCapture.wantsStreamNow(m, 21 * 60 + 29))   // 21:29 out
    }

    @Test fun overnightStartIsInclusive() {
        assertTrue(ContinuousCapture.wantsStreamNow(m, ContinuousCapture.WINDOW_START_MIN))   // 21:30 in
    }
}
