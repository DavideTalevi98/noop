package com.noop.analytics

import com.noop.data.DailyMetric
import java.util.Locale
import kotlin.math.max
import kotlin.math.min
import kotlin.math.round
import kotlin.math.roundToInt
import kotlin.math.sqrt

/*
 * DualWindowReadiness.kt — acute (7-night) vs normal (60-night) personal band readiness.
 *
 * Faithful Kotlin mirror of StrandAnalytics/DualWindowReadiness.swift.
 */

object DualWindowReadiness {

    const val normalWindowNights: Int = 60
    const val acuteWindowNights: Int = 7
    const val minNormalNights: Int = 14
    const val minAcuteNights: Int = 4
    const val bandSigma: Double = 1.0

    enum class State { INSUFFICIENT, WITHIN_NORMAL, SUPPRESSED, ELEVATED }

    data class MetricResult(
        val key: String,
        val label: String,
        val state: State,
        val acuteMean: Double,
        val normalMean: Double,
        val normalLower: Double,
        val normalUpper: Double,
        val nNormal: Int,
        val nAcute: Int,
        val summary: String,
    )

    data class Summary(
        val hrv: MetricResult?,
        val rhr: MetricResult?,
        val overall: State,
    )

    fun evaluate(days: List<DailyMetric>, today: String? = null): Summary {
        val sorted = days.sortedBy { it.day }
        val todayKey = today ?: sorted.lastOrNull()?.day
        if (todayKey == null) return Summary(null, null, State.INSUFFICIENT)
        val idx = sorted.indexOfFirst { it.day == todayKey }
        if (idx < 0) return Summary(null, null, State.INSUFFICIENT)

        val history = sorted.take(idx)
        val todayRow = sorted[idx]

        val hrv = evaluate(
            key = "hrv", label = "HRV",
            history = history.map { it.avgHrv },
            today = todayRow.avgHrv,
            higherIsBetter = true,
            cfg = Baselines.hrvCfg,
        )
        val rhr = evaluate(
            key = "rhr", label = "Resting HR",
            history = history.map { it.restingHr?.toDouble() },
            today = todayRow.restingHr?.toDouble(),
            higherIsBetter = false,
            cfg = Baselines.restingHRCfg,
        )
        return Summary(hrv, rhr, worst(hrv?.state, rhr?.state))
    }

    fun evaluate(
        key: String,
        label: String,
        history: List<Double?>,
        today: Double?,
        higherIsBetter: Boolean,
        cfg: MetricCfg,
    ): MetricResult? {
        if (today == null) return null

        val normalVals = validTrailing(history, cfg, normalWindowNights)
        if (normalVals.size < minNormalNights) return insufficient(key, label)
        val nStats = meanSD(normalVals) ?: return insufficient(key, label)

        val acuteSeries = history + today
        val acuteVals = validTrailing(acuteSeries, cfg, acuteWindowNights)
        if (acuteVals.size < minAcuteNights) return insufficient(key, label)
        val aMean = mean(acuteVals) ?: return insufficient(key, label)

        val lower = nStats.mean - bandSigma * nStats.sd
        val upper = nStats.mean + bandSigma * nStats.sd

        val state = when {
            higherIsBetter && aMean < lower -> State.SUPPRESSED
            higherIsBetter && aMean > upper -> State.ELEVATED
            !higherIsBetter && aMean > upper -> State.SUPPRESSED
            !higherIsBetter && aMean < lower -> State.ELEVATED
            else -> State.WITHIN_NORMAL
        }

        val summary = summaryFor(label, state, aMean, nStats.mean, lower, upper, unitFor(key), higherIsBetter)
        return MetricResult(
            key, label, state, aMean, nStats.mean, lower, upper,
            normalVals.size, acuteVals.size, summary,
        )
    }

    private data class MeanSD(val mean: Double, val sd: Double)

    private fun validTrailing(values: List<Double?>, cfg: MetricCfg, window: Int): List<Double> =
        values.mapNotNull { v ->
            v?.takeIf { it in cfg.minVal..cfg.maxVal }
        }.takeLast(window)

    private fun mean(xs: List<Double>): Double? = if (xs.isEmpty()) null else xs.average()

    private fun meanSD(xs: List<Double>): MeanSD? {
        if (xs.size < 2) return null
        val m = xs.average()
        val n = xs.size.toDouble()
        val sd = sqrt(xs.sumOf { (it - m) * (it - m) } / (n - 1.0))
        if (sd <= 1e-9) return null
        return MeanSD(m, sd)
    }

    private fun insufficient(key: String, label: String) = MetricResult(
        key, label, State.INSUFFICIENT,
        0.0, 0.0, 0.0, 0.0, 0, 0,
        "Wear a few more nights for a $label trend read",
    )

    private fun unitFor(key: String) = when (key) {
        "hrv" -> "ms"
        "rhr" -> "bpm"
        else -> ""
    }

    private fun summaryFor(
        label: String, state: State,
        acute: Double, normal: Double,
        lower: Double, upper: Double, unit: String,
        higherIsBetter: Boolean,
    ): String {
        val a = acute.roundToInt()
        val n = normal.roundToInt()
        return when (state) {
            State.INSUFFICIENT -> "Wear a few more nights for a $label trend read"
            State.WITHIN_NORMAL -> String.format(
                Locale.US,
                "%s acute %d %s sits inside your normal band (%.0f–%.0f %s)",
                label, a, unit, round(lower), round(upper), unit,
            )
            State.SUPPRESSED -> {
                val dir = if (higherIsBetter) "below" else "above"
                String.format(
                    Locale.US,
                    "%s acute %d %s is %s your normal band (mean %d %s) — recovery may be taxed",
                    label, a, unit, dir, n, unit,
                )
            }
            State.ELEVATED -> {
                val dir = if (higherIsBetter) "above" else "below"
                String.format(
                    Locale.US,
                    "%s acute %d %s is %s your normal band (mean %d %s) — a positive stretch",
                    label, a, unit, dir, n, unit,
                )
            }
        }
    }

    private fun worst(a: State?, b: State?): State {
        val rank = mapOf(
            State.INSUFFICIENT to 0,
            State.WITHIN_NORMAL to 1,
            State.ELEVATED to 2,
            State.SUPPRESSED to 3,
        )
        val sa = a?.let { rank[it] } ?: 0
        val sb = b?.let { rank[it] } ?: 0
        val m = max(sa, sb)
        return rank.entries.first { it.value == m }.key
    }
}
