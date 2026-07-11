import Foundation
import WhoopProtocol

// ANSEarlySleepEngine.swift — Polar Nightly Recharge–style ANS charge for the first hours of sleep.
//
// Pure, deterministic, DB-free. Implements the published Polar pattern (white paper + support docs):
// measure heart rate, RMSSD, and breathing rate during a fixed early-sleep window starting 30 min
// after sleep onset, compare each to a personal trailing baseline (~28 nights), and combine with
// explicit weights (HR largest, respiration smallest).
//
// References: Polar Nightly Recharge white paper; Task Force (1996) RMSSD; Plews et al. 2013.
// APPROXIMATE — wellness only, not medical advice. Weights and mapping are NOOP's transparent
// interpretation of the published pattern, not a reverse-engineered Polar formula.

public enum ANSEarlySleepEngine {

    // MARK: - Tunables (pinned by test; mirror Kotlin twin)

    /// Minutes after sleep onset before the ANS window opens (Polar: 30 min).
    public static let onsetDelaySec: Int = 30 * 60
    /// Length of the ANS measurement window (Polar: 4 h).
    public static let windowDurationSec: Int = 4 * 60 * 60
    /// Trailing nights for personal baseline (Polar: 28).
    public static let baselineNights: Int = 28
    /// Minimum prior nights with usable ANS snapshots before scoring.
    public static let minBaselineNights: Int = 7
    /// Minimum HR samples in the window (ponytail: ~2 h at 1 Hz; sparse straps still pass).
    public static let minHRSamples: Int = 120

    /// Polar documents HR as the dominant driver, respiration the smallest.
    public static let wHR: Double = 0.50
    public static let wHRV: Double = 0.35
    public static let wResp: Double = 0.15

    /// Map composite z to 0–100 charge points (~1 SD ≈ 15 pts around 50 at baseline).
    public static let chargeCenter: Double = 50.0
    public static let chargePerZ: Double = 15.0

    // MARK: - Types

    public enum Level: String, Equatable, Sendable {
        case insufficient
        case compromised   // charge < 34
        case ok            // 34–66
        case good          // ≥ 67
    }

    /// One night's early-sleep ANS primitives (stored for baseline history).
    public struct NightSnapshot: Equatable, Sendable {
        public let hrBpm: Double
        public let rmssdMs: Double
        public let respBpm: Double
        public init(hrBpm: Double, rmssdMs: Double, respBpm: Double) {
            self.hrBpm = hrBpm; self.rmssdMs = rmssdMs; self.respBpm = respBpm
        }
    }

    public struct Result: Equatable, Sendable {
        public let charge: Double
        public let level: Level
        public let compositeZ: Double
        public let hrZ: Double?
        public let hrvZ: Double?
        public let respZ: Double?
        public let snapshot: NightSnapshot
        /// Plain-English one-liner for UI.
        public let summary: String

        public init(charge: Double, level: Level, compositeZ: Double,
                    hrZ: Double?, hrvZ: Double?, respZ: Double?,
                    snapshot: NightSnapshot, summary: String) {
            self.charge = charge; self.level = level; self.compositeZ = compositeZ
            self.hrZ = hrZ; self.hrvZ = hrvZ; self.respZ = respZ
            self.snapshot = snapshot; self.summary = summary
        }
    }

    // MARK: - Entry points

    /// Extract tonight's early-sleep primitives from raw streams, or nil when the window is too thin.
    public static func snapshot(sleepOnsetTs: Int, hr: [HRSample], rr: [RRInterval]) -> NightSnapshot? {
        let start = sleepOnsetTs + onsetDelaySec
        let end = start + windowDurationSec
        guard end > start else { return nil }

        let inWindowHR = hr.filter { $0.ts >= start && $0.ts < end }
        guard inWindowHR.count >= minHRSamples else { return nil }

        let hrMean = Double(inWindowHR.map(\.bpm).reduce(0, +)) / Double(inWindowHR.count)

        let inWindowRR = rr.filter { $0.ts >= start && $0.ts < end }
        guard let rmssd = HRVAnalyzer.analyze(inWindowRR).rmssd else { return nil }

        let resp = SleepStager.respRateFromRR(inWindowRR, start: start, end: end)
        guard resp.isFinite, SleepStager.respPlausibleRangeBpm.contains(resp) else { return nil }

        return NightSnapshot(hrBpm: hrMean, rmssdMs: rmssd, respBpm: resp)
    }

    /// Score tonight's ANS charge vs `history` (oldest→newest prior nights, excluding tonight).
    public static func evaluate(sleepOnsetTs: Int, hr: [HRSample], rr: [RRInterval],
                                history: [NightSnapshot]) -> Result? {
        guard let snap = snapshot(sleepOnsetTs: sleepOnsetTs, hr: hr, rr: rr) else { return nil }
        return evaluate(snapshot: snap, history: history)
    }

    /// Score a pre-built tonight snapshot vs personal history.
    public static func evaluate(snapshot: NightSnapshot, history: [NightSnapshot]) -> Result? {
        let trailing = Array(history.suffix(baselineNights))
        guard trailing.count >= minBaselineNights else { return nil }

        let hrBase = stats(trailing.map(\.hrBpm))
        let hrvBase = stats(trailing.map(\.rmssdMs))
        let respBase = stats(trailing.map(\.respBpm))
        guard let hrBase, let hrvBase, let respBase else { return nil }

        let hrZ = signedZ(value: snapshot.hrBpm, mean: hrBase.mean, sd: hrBase.sd, higherIsBetter: false)
        let hrvZ = signedZ(value: snapshot.rmssdMs, mean: hrvBase.mean, sd: hrvBase.sd, higherIsBetter: true)
        let respZ = signedZ(value: snapshot.respBpm, mean: respBase.mean, sd: respBase.sd, higherIsBetter: false)

        var zSum = 0.0
        var wSum = 0.0
        if let z = hrZ { zSum += wHR * z; wSum += wHR }
        if let z = hrvZ { zSum += wHRV * z; wSum += wHRV }
        if let z = respZ { zSum += wResp * z; wSum += wResp }
        guard wSum > 0 else { return nil }

        let compositeZ = zSum / wSum
        let charge = min(100, max(0, (chargeCenter + chargePerZ * compositeZ).rounded()))
        let level = levelFor(charge: charge)
        let summary = summaryFor(charge: charge, compositeZ: compositeZ, snap: snapshot)
        return Result(charge: charge, level: level, compositeZ: compositeZ,
                      hrZ: hrZ, hrvZ: hrvZ, respZ: respZ,
                      snapshot: snapshot, summary: summary)
    }

    // MARK: - Helpers

    private struct SimpleStats { let mean: Double; let sd: Double }

    private static func stats(_ xs: [Double]) -> SimpleStats? {
        guard xs.count >= 2 else { return nil }
        let n = Double(xs.count)
        let m = xs.reduce(0, +) / n
        let varSum = xs.reduce(0.0) { $0 + ($1 - m) * ($1 - m) }
        let sd = sqrt(varSum / (n - 1))
        guard sd > 1e-9 else { return nil }
        return SimpleStats(mean: m, sd: sd)
    }

    /// Recovery-oriented z: positive when the value is "good" for recovery.
    private static func signedZ(value: Double, mean: Double, sd: Double, higherIsBetter: Bool) -> Double? {
        guard sd > 1e-9 else { return nil }
        let raw = (value - mean) / sd
        return higherIsBetter ? raw : -raw
    }

    private static func levelFor(charge: Double) -> Level {
        if charge >= RecoveryScorer.bandYellowMax { return .good }
        if charge >= RecoveryScorer.bandRedMax { return .ok }
        return .compromised
    }

    private static func summaryFor(charge: Double, compositeZ: Double, snap: NightSnapshot) -> String {
        let qual: String
        if charge >= RecoveryScorer.bandYellowMax {
            qual = "ANS relaxed well in early sleep"
        } else if charge >= RecoveryScorer.bandRedMax {
            qual = "Early-sleep ANS near your usual"
        } else {
            qual = "Early-sleep ANS still activated vs your baseline"
        }
        return String(format: "%@ (charge %.0f, HR %.0f, HRV %.0f ms, resp %.1f/min)",
                      qual, charge, snap.hrBpm.rounded(), snap.rmssdMs.rounded(), snap.respBpm)
    }
}
