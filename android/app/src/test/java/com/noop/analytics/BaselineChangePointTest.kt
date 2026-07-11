package com.noop.analytics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BaselineChangePointTest {

    @Test
    fun detectsStepUp() {
        val xs = MutableList(20) { 55.0 } + List(15) { 75.0 }
        val r = BaselineChangePoint.detect(xs)
        assertFalse(r.events.isEmpty())
        assertEquals(BaselineChangePoint.Direction.INCREASE, r.mostRecent?.direction)
        assertNotNull(r.summary)
    }

    @Test
    fun noDetectionOnFlatSeries() {
        val r = BaselineChangePoint.detect(List(30) { 60.0 })
        assertTrue(r.events.isEmpty())
    }
}
