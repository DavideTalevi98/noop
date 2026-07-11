package com.noop.analytics

import com.noop.data.HrSample
import com.noop.data.RrInterval
import java.util.Locale
import kotlin.math.max
import kotlin.math.min
import kotlin.math.round
import kotlin.math.roundToInt
import kotlin.math.sqrt

/*
 * ANSEarlySleepEngine.kt — Polar Nightly Recharge–style ANS charge for the first hours of sleep.
 *
 * Faithful Kotlin mirror of StrandAnalytics/ANSEarlySleepEngine.swift. Keep tunables, weights,
 * and scoring byte-identical to Swift — cross-platform parity is the contract.
 */

object ANSEarlySleepEngine {

    const val onsetDelaySec: Int = 30 * 60
    const val windowDurationSec: Int = 4 * 60 * 60
    const val baselineNights: Int = 28
    const val minBaselineNights: Int = 7
    const val minHRSamples: Int = 120

    const val wHR: Double = 0.50
    const val wHRV: Double = 0.35
    const val wResp: Double = 0.15

    const val chargeCenter: Double = 50.0
    const val chargePerZ: Double = 15.0

    enum class Level { INSUFFICIENT, COMPROMISED, OK, GOOD }

    data class NightSnapshot(
        val hrBpm: Double,
        val rmssdMs: Double,
        val respBpm: Double,
    )

    data class Result(
        val charge: Double,
        val level: Level,
        val compositeZ: Double,
        val hrZ: Double?,
        val hrvZ: Double?,
        val respZ: Double?,
        val snapshot: NightSnapshot,
        val summary: String,
    )

    fun snapshot(sleepOnsetTs: Long, hr: List<HrSample>, rr: List<RrInterval>): NightSnapshot? {
        val start = sleepOnsetTs + onsetDelaySec
        val end = start + windowDurationSec
        if (end <= start) return null

        val inWindowHR = hr.filter { it.ts >= start && it.ts < end }
        if (inWindowHR.size < minHRSamples) return null

        val hrMean = inWindowHR.map { it.bpm }.average()

        val inWindowRR = rr.filter { it.ts >= start && it.ts < end }
        val rmssd = HrvAnalyzer.analyze(inWindowRR, windowStart = start, windowEnd = end - 1).rmssd
            ?: return null

        val resp = SleepStager.respRateFromRR(inWindowRR, start, end)
        if (!resp.isFinite() || resp !in SleepStager.respPlausibleRangeBpm) return null

        return NightSnapshot(hrBpm = hrMean, rmssdMs = rmssd, respBpm = resp)
    }

    fun evaluate(
        sleepOnsetTs: Long,
        hr: List<HrSample>,
        rr: List<RrInterval>,
        history: List<NightSnapshot>,
    ): Result? {
        val snap = snapshot(sleepOnsetTs, hr, rr) ?: return null
        return evaluate(snap, history)
    }

    fun evaluate(snapshot: NightSnapshot, history: List<NightSnapshot>): Result? {
        val trailing = history.takeLast(baselineNights)
        if (trailing.size < minBaselineNights) return null

        val hrBase = stats(trailing.map { it.hrBpm }) ?: return null
        val hrvBase = stats(trailing.map { it.rmssdMs }) ?: return null
        val respBase = stats(trailing.map { it.respBpm }) ?: return null

        val hrZ = signedZ(snapshot.hrBpm, hrBase.mean, hrBase.sd, higherIsBetter = false)
        val hrvZ = signedZ(snapshot.rmssdMs, hrvBase.mean, hrvBase.sd, higherIsBetter = true)
        val respZ = signedZ(snapshot.respBpm, respBase.mean, respBase.sd, higherIsBetter = false)

        var zSum = 0.0
        var wSum = 0.0
        hrZ?.let { zSum += wHR * it; wSum += wHR }
        hrvZ?.let { zSum += wHRV * it; wSum += wHRV }
        respZ?.let { zSum += wResp * it; wSum += wResp }
        if (wSum <= 0) return null

        val compositeZ = zSum / wSum
        val charge = min(100.0, max(0.0, round(chargeCenter + chargePerZ * compositeZ)))
        val level = levelFor(charge)
        val summary = summaryFor(charge, snapshot)
        return Result(charge, level, compositeZ, hrZ, hrvZ, respZ, snapshot, summary)
    }

    private data class SimpleStats(val mean: Double, val sd: Double)

    private fun stats(xs: List<Double>): SimpleStats? {
        if (xs.size < 2) return null
        val n = xs.size.toDouble()
        val m = xs.average()
        val varSum = xs.sumOf { (it - m) * (it - m) }
        val sd = sqrt(varSum / (n - 1.0))
        if (sd <= 1e-9) return null
        return SimpleStats(m, sd)
    }

    private fun signedZ(value: Double, mean: Double, sd: Double, higherIsBetter: Boolean): Double? {
        if (sd <= 1e-9) return null
        val raw = (value - mean) / sd
        return if (higherIsBetter) raw else -raw
    }

    private fun levelFor(charge: Double): Level = when {
        charge >= RecoveryScorer.bandYellowMax -> Level.GOOD
        charge >= RecoveryScorer.bandRedMax -> Level.OK
        else -> Level.COMPROMISED
    }

    private fun summaryFor(charge: Double, snap: NightSnapshot): String {
        val qual = when {
            charge >= RecoveryScorer.bandYellowMax -> "ANS relaxed well in early sleep"
            charge >= RecoveryScorer.bandRedMax -> "Early-sleep ANS near your usual"
            else -> "Early-sleep ANS still activated vs your baseline"
        }
        return String.format(
            Locale.US,
            "%s (charge %.0f, HR %.0f, HRV %.0f ms, resp %.1f/min)",
            qual, charge, snap.hrBpm.roundToInt().toDouble(),
            snap.rmssdMs.roundToInt().toDouble(), snap.respBpm,
        )
    }
}
