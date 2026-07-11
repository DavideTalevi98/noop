package com.noop.protocol

import com.noop.data.BatterySample
import com.noop.data.HrSample
import com.noop.data.RrInterval
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import kotlin.math.abs

/**
 * Kotlin half of the cross-platform `extractStreams` golden guard — mirrors
 * `Packages/WhoopProtocol/Tests/WhoopProtocolTests/StreamsParityTests.swift`.
 *
 * `frames.json` and `streams_golden.json` are byte-identical copies of the Swift test resources;
 * [fixtureCopiesAreIdentical] keeps them in lockstep.
 */
class StreamsParityTest {

    // MUST equal StreamsParityTests.swift / scripts/gen_golden.py.
    private val deviceClockRef = 31_538_447
    private val wallClockRef = 1_736_365_593

    private fun hexToBytes(s: String): ByteArray =
        ByteArray(s.length / 2) { ((s[it * 2].digitToInt(16) shl 4) or s[it * 2 + 1].digitToInt(16)).toByte() }

    private fun loadResource(name: String): String {
        val stream = javaClass.classLoader!!.getResourceAsStream(name)
        assertNotNull("$name missing from test classpath", stream)
        return stream!!.bufferedReader().use { it.readText() }
    }

    @Test
    fun kotlinStreamsMatchGolden() {
        val frames = JSONArray(loadResource("frames.json"))
        val gold = JSONObject(loadResource("streams_golden.json"))

        val parsed = (0 until frames.length()).map { i ->
            Framing.parseFrame(hexToBytes(frames.getJSONObject(i).getString("hex")))
        }
        val s = extractStreams(parsed, deviceClockRef = deviceClockRef, wallClockRef = wallClockRef)

        val hrGold = gold.getJSONArray("hr")
        assertEquals(hrGold.length(), s.hr.size)
        for (i in 0 until hrGold.length()) {
            val g = hrGold.getJSONObject(i)
            assertEquals(HrSample(g.getInt("ts"), g.getInt("bpm")), s.hr[i])
        }

        val rrGold = gold.getJSONArray("rr")
        assertEquals(rrGold.length(), s.rr.size)
        for (i in 0 until rrGold.length()) {
            val g = rrGold.getJSONObject(i)
            assertEquals(RrInterval(g.getInt("ts"), g.getInt("rr_ms")), s.rr[i])
        }

        val batGold = gold.getJSONArray("battery")
        assertEquals(batGold.length(), s.battery.size)
        for (i in 0 until batGold.length()) {
            val g = batGold.getJSONObject(i)
            val wantCharging = if (g.isNull("charging")) null else g.getBoolean("charging")
            assertEquals(
                BatterySample(
                    ts = g.getInt("ts"),
                    soc = if (g.isNull("soc")) null else g.getDouble("soc"),
                    mv = if (g.isNull("mv")) null else g.getInt("mv"),
                    charging = wantCharging,
                ),
                s.battery[i],
            )
        }

        val evGold = gold.getJSONArray("events")
        assertEquals("event count mismatch", evGold.length(), s.events.size)
        for (i in 0 until evGold.length()) {
            val g = evGold.getJSONObject(i)
            val got = s.events[i]
            assertEquals("event ts mismatch #$i", g.getInt("ts"), got.ts)
            assertEquals("event kind mismatch #$i", g.getString("kind"), got.kind)
            assertPayloadEquals("event payload mismatch #$i (${g.getString("kind")})", g.getJSONObject("payload"), got.payload)
        }

        assertTrue(s.hr.isNotEmpty())
        assertTrue(s.events.isNotEmpty())
        assertTrue(s.battery.isNotEmpty())
    }

    private fun assertPayloadEquals(msg: String, want: JSONObject, got: Map<String, Any?>) {
        val keys = want.keys().asSequence().toSet()
        assertEquals("$msg: key count", keys.size, got.size)
        for (key in keys) {
            when (val w = want.get(key)) {
                is Number -> when (val g = got[key]) {
                    is Int, is Long -> assertEquals("$msg.$key", w.toLong(), (g as Number).toLong())
                    is Double, is Float -> assertTrue("$msg.$key: ${g as Number} != ~$w", abs(g.toDouble() - w.toDouble()) < 1e-9)
                    is Boolean -> assertEquals("$msg.$key", w.toInt() != 0, g)
                    else -> throw AssertionError("$msg.$key: unexpected got type ${g?.javaClass}")
                }
                is String -> assertEquals("$msg.$key", w, got[key])
                is JSONObject -> throw AssertionError("$msg.$key: nested JSONObject not expected")
                else -> assertEquals("$msg.$key", w, got[key])
            }
        }
    }

    /** Android and Swift copies of the golden fixtures MUST stay byte-identical. */
    @Test
    fun fixtureCopiesAreIdentical() {
        val loader = javaClass.classLoader!!
        val androidFrames = loader.getResourceAsStream("frames.json")!!.use { it.readBytes() }
        val androidGold = loader.getResourceAsStream("streams_golden.json")!!.use { it.readBytes() }

        val userDir = java.io.File(requireNotNull(System.getProperty("user.dir")))
        val swiftBase = listOf(
            java.io.File(userDir, "Packages/WhoopProtocol/Tests/WhoopProtocolTests/Resources"),
            java.io.File(userDir, "../../Packages/WhoopProtocol/Tests/WhoopProtocolTests/Resources"),
        ).firstOrNull { it.isDirectory }
        assumeTrue("Swift fixture tree not found from user.dir=$userDir", swiftBase != null)

        val swiftFrames = java.io.File(swiftBase, "frames.json")
        val swiftGold = java.io.File(swiftBase, "streams_golden.json")
        assumeTrue(swiftFrames.exists() && swiftGold.exists())

        assertTrue("frames.json copies differ", androidFrames.contentEquals(swiftFrames.readBytes()))
        assertTrue("streams_golden.json copies differ", androidGold.contentEquals(swiftGold.readBytes()))
    }
}
