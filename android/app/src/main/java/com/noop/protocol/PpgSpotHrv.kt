package com.noop.protocol

import kotlin.math.abs
import kotlin.math.sqrt

/**
 * Spot HRV (RMSSD) from sparse WHOOP 5/MG **v26** optical PPG bursts.
 *
 * Twin of Swift `WhoopProtocol/PpgSpotHrv.swift` / `tools/linux-capture/whoop_spot_hrv.py`.
 * Pure + side-effect-free so it is unit-testable on synthetic signals.
 */
object PpgSpotHrv {
    const val SAMPLE_RATE_HZ = 24
    const val MIN_BURST_SECONDS = 20
    const val GLITCH_THRESHOLD = 0.30

    data class Sample(
        val ts: Long,
        val rmssdMs: Double,
        val hrBpm: Double,
        val beats: Int,
        val quality: String,
    )

    /**
     * One spot per contiguous v26 PPG burst (≥ [MIN_BURST_SECONDS]). [records] are
     * (wall-clock second, 24 ADC samples); unsorted / gappy OK; last write wins on duplicate ts.
     */
    fun derive(records: List<Pair<Long, IntArray>>, fs: Int = SAMPLE_RATE_HZ): List<Sample> {
        if (records.isEmpty() || fs <= 0) return emptyList()
        val secs = LinkedHashMap<Long, IntArray>()
        for ((ts, samples) in records) secs[ts] = samples
        val order = secs.keys.sorted()
        val runs = ArrayList<List<Long>>()
        var cur = arrayListOf(order[0])
        for (i in 1 until order.size) {
            val u = order[i]
            if (u - cur.last() == 1L) cur.add(u)
            else {
                runs.add(cur)
                cur = arrayListOf(u)
            }
        }
        runs.add(cur)

        val out = ArrayList<Sample>()
        for (run in runs) {
            if (run.size < MIN_BURST_SECONDS) continue
            val values = ArrayList<Double>()
            val times = ArrayList<Double>()
            val base = run[0]
            for (u in run) {
                val samples = secs[u] ?: continue
                if (samples.isEmpty()) continue
                val n = samples.size.toDouble()
                for (i in samples.indices) {
                    times.add((u - base).toDouble() + i / n)
                    values.add(samples[i].toDouble())
                }
            }
            spotHrv(times, values, fs.toDouble())?.let { spot ->
                out.add(
                    Sample(
                        ts = base,
                        rmssdMs = spot.rmssd,
                        hrBpm = spot.hr,
                        beats = spot.nClean,
                        quality = spot.quality,
                    ),
                )
            }
        }
        return out
    }

    /** Median of GOOD-quality RMSSD values, or null when none. */
    fun medianGoodRmssd(samples: List<Sample>): Double? {
        val good = samples.filter { it.quality == "GOOD" }.map { it.rmssdMs }.sorted()
        if (good.isEmpty()) return null
        val mid = good.size / 2
        return if (good.size % 2 == 0) (good[mid - 1] + good[mid]) / 2.0 else good[mid]
    }

    internal data class Spot(val hr: Double, val rmssd: Double, val nClean: Int, val quality: String)

    internal fun spotHrv(times: List<Double>, values: List<Double>, fs: Double): Spot? {
        if (values.size < 30 || fs <= 0) return null
        val vv = detrend(values, fs.toInt())
        val sd = pstdev(vv) ?: 1.0
        val peaks = findPeaks(vv, minDist = (0.4 * fs).toInt(), minProm = 0.3 * sd)
        val beatTimes = peaks.map { p -> times[p] + interp(vv, p) / fs }
        val rr = ArrayList<Double>()
        for (i in 0 until beatTimes.size - 1) {
            val ms = (beatTimes[i + 1] - beatTimes[i]) * 1000.0
            if (ms in 300.0..2000.0) rr.add(ms)
        }
        if (rr.size < 2) return null
        val hr = 60_000.0 / median(rr)
        val rmssd = rmssdSequential(rr) ?: return null
        var nClean = 0
        for (i in 1 until rr.size) {
            if (abs(rr[i] - rr[i - 1]) <= GLITCH_THRESHOLD * rr[i - 1]) nClean++
        }
        val quality = when {
            nClean < 10 -> "POOR"
            nClean >= 25 -> "GOOD"
            else -> "COARSE"
        }
        return Spot(hr, rmssd, nClean, quality)
    }

    internal fun detrend(v: List<Double>, win: Int): List<Double> {
        val n = v.size
        val h = maxOf(1, win / 2)
        return List(n) { i ->
            val lo = maxOf(0, i - h)
            val hi = minOf(n, i + h + 1)
            var sum = 0.0
            for (j in lo until hi) sum += v[j]
            v[i] - sum / (hi - lo)
        }
    }

    internal fun findPeaks(v: List<Double>, minDist: Int, minProm: Double): List<Int> {
        if (v.size < 3) return emptyList()
        val cand = (1 until v.size - 1).filter { i ->
            v[i] > v[i - 1] && v[i] >= v[i + 1] && v[i] > minProm
        }.sortedByDescending { v[it] }
        val kept = ArrayList<Int>()
        for (i in cand) {
            if (kept.all { abs(i - it) >= minDist }) kept.add(i)
        }
        return kept.sorted()
    }

    internal fun interp(v: List<Double>, p: Int): Double {
        if (p <= 0 || p >= v.size - 1) return 0.0
        val a = v[p - 1]; val b = v[p]; val c = v[p + 1]
        val den = a - 2 * b + c
        return if (den != 0.0) (a - c) / (2 * den) else 0.0
    }

    internal fun rmssdSequential(rr: List<Double>, thr: Double = GLITCH_THRESHOLD): Double? {
        if (rr.size < 2) return null
        val glitch = BooleanArray(rr.size)
        for (i in 1 until rr.size) {
            if (abs(rr[i] - rr[i - 1]) > thr * rr[i - 1]) glitch[i] = true
        }
        val d = ArrayList<Double>()
        for (i in 1 until rr.size) {
            if (!glitch[i - 1] && !glitch[i]) d.add(rr[i] - rr[i - 1])
        }
        if (d.size < 2) return null
        val meanSq = d.sumOf { it * it } / d.size
        return sqrt(meanSq)
    }

    private fun median(x: List<Double>): Double {
        val s = x.sorted()
        val mid = s.size / 2
        return if (s.size % 2 == 0) (s[mid - 1] + s[mid]) / 2.0 else s[mid]
    }

    private fun pstdev(x: List<Double>): Double? {
        if (x.size < 2) return null
        val mean = x.sum() / x.size
        val varPop = x.sumOf { (it - mean) * (it - mean) } / x.size
        return sqrt(varPop)
    }
}
