package com.noop.analytics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Pins the SpO2 RE dump line format (full-record hex + mapped channels). Twin of the Swift Spo2ReTraceTests. */
class Spo2ReTraceTest {

    @Test fun recordLineFormatsHexAndFields() {
        val frame = byteArrayOf(0x00, 0x0f, 0xff.toByte(), 0x10)
        val decoded = mapOf<String, Any?>(
            "hist_version" to 24, "unix" to 1_700_000_000, "spo2_red" to 512, "spo2_ir" to 480,
            "skin_temp_raw" to 330,
        )
        val line = Spo2ReTrace.recordLine(frame, decoded)
        assertTrue(line.startsWith("spo2re "))
        assertTrue(line.contains("v=24"))
        assertTrue(line.contains("unix=1700000000"))
        assertTrue(line.contains("red=512"))
        assertTrue(line.contains("ir=480"))
        assertTrue(line.contains("skinRaw=330"))
        assertTrue(line.contains("len=4"))
        assertTrue(line.contains("raw=000fff10")) // FULL frame hex, unsigned bytes, no prefix cap
    }

    @Test fun absentChannelsRenderNull() {
        // A record with no SpO2 mapped (e.g. v25 motion-only) must still dump — proving "nothing banked".
        val line = Spo2ReTrace.recordLine(byteArrayOf(1, 2, 3), mapOf("hist_version" to 25, "unix" to 42))
        assertTrue(line.contains("red=null"))
        assertTrue(line.contains("ir=null"))
        assertTrue(line.contains("raw=010203"))
    }

    @Test fun hexRendersUnsignedBytes() {
        // 0xFF must be "ff" (unsigned), never "-1" or a sign-extended "ffffffff".
        assertTrue(Spo2ReTrace.recordLine(byteArrayOf(0xff.toByte()), emptyMap()).endsWith("raw=ff"))
    }

    @Test fun sampleCapIsBoundedAndPositive() {
        assertTrue(Spo2ReTrace.MAX_SAMPLES in 1..32)
        assertEquals(8, Spo2ReTrace.MAX_SAMPLES)
    }
}
