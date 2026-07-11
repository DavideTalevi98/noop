package com.noop.analytics

import java.util.Locale
import kotlin.math.max
import kotlin.math.sqrt

/*
 * BaselineChangePoint.kt — two-sided CUSUM mean-shift detection on nightly metrics.
 *
 * Faithful Kotlin mirror of StrandAnalytics/BaselineChangePoint.swift.
 */

object BaselineChangePoint {

    const val slackK: Double = 0.5
    const val thresholdH: Double = 4.0
    const val initWindow: Int = 14
    const val minSeriesLength: Int = 21

    enum class Direction { INCREASE, DECREASE }

    data class Event(
        val index: Int,
        val direction: Direction,
        val shiftZ: Double,
    )

    data class Result(
        val events: List<Event>,
        val mostRecent: Event?,
        val summary: String?,
    )

    fun detect(
        values: List<Double>,
        k: Double = slackK,
        h: Double = thresholdH,
        seedWindow: Int = initWindow,
    ): Result {
        if (values.size < minSeriesLength || seedWindow < 2 || seedWindow >= values.size) {
            return Result(emptyList(), null, null)
        }

        var mu = mean(values.take(seedWindow))
        var sigma = max(sd(values.take(seedWindow)), 1e-6)

        val events = mutableListOf<Event>()
        var sPos = 0.0
        var sNeg = 0.0
        var resumeAt = seedWindow

        for (i in seedWindow until values.size) {
            if (i < resumeAt) continue
            val z = (values[i] - mu) / sigma
            sPos = max(0.0, sPos + z - k)
            sNeg = max(0.0, sNeg - z - k)

            if (sPos > h) {
                events.add(Event(i, Direction.INCREASE, z))
                val end = kotlin.math.min(i + seedWindow, values.size)
                val slice = values.subList(i, end)
                if (slice.size >= 2) {
                    mu = mean(slice)
                    sigma = max(sd(slice), 1e-6)
                }
                sPos = 0.0; sNeg = 0.0
                resumeAt = end
            } else if (sNeg > h) {
                events.add(Event(i, Direction.DECREASE, z))
                val end = kotlin.math.min(i + seedWindow, values.size)
                val slice = values.subList(i, end)
                if (slice.size >= 2) {
                    mu = mean(slice)
                    sigma = max(sd(slice), 1e-6)
                }
                sPos = 0.0; sNeg = 0.0
                resumeAt = end
            }
        }

        val recent = events.lastOrNull()
        return Result(events, recent, summaryFor(events, values))
    }

    fun detect(series: List<Double?>, cfg: MetricCfg): Result {
        val valid = series.mapNotNull { v -> v?.takeIf { it in cfg.minVal..cfg.maxVal } }
        return detect(valid)
    }

    private fun mean(xs: List<Double>): Double = xs.average()

    private fun sd(xs: List<Double>): Double {
        if (xs.size < 2) return 0.0
        val m = mean(xs)
        val n = xs.size.toDouble()
        return sqrt(xs.sumOf { (it - m) * (it - m) } / (n - 1.0))
    }

    private fun summaryFor(events: List<Event>, values: List<Double>): String? {
        val last = events.lastOrNull() ?: return null
        val nightsAgo = values.size - 1 - last.index
        val dir = if (last.direction == Direction.INCREASE) "rose" else "fell"
        return if (nightsAgo == 0) {
            String.format(Locale.US, "Your baseline likely %s on the most recent night", dir)
        } else {
            String.format(Locale.US, "Your baseline likely %s about %d nights ago", dir, nightsAgo)
        }
    }
}
