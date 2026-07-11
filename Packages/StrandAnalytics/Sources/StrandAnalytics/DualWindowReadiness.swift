import Foundation
import WhoopStore

// DualWindowReadiness.swift — acute (7-night) vs normal (60-night) personal band readiness.
//
// Pure, deterministic, DB-free. Implements the HRV4Training / AI Endurance pattern: compare a
// short acute window to a longer "normal" band (mean ± 1 SD) so a sustained dip/rise is flagged
// even when a single night looks borderline. Complements single-night z-scores in ReadinessEngine.
//
// References: Plews et al. 2013; Buchheit 2014; Marco Altini HRV4Training methodology.
// APPROXIMATE — wellness only, not medical advice.

public enum DualWindowReadiness {

    // MARK: - Tunables (pinned by test; mirror Kotlin twin)

    public static let normalWindowNights: Int = 60
    public static let acuteWindowNights: Int = 7
    public static let minNormalNights: Int = 14
    public static let minAcuteNights: Int = 4
    /// Normal band = mean ± bandSigma × SD (1σ ≈ ~68% of your historical nights).
    public static let bandSigma: Double = 1.0

    // MARK: - Types

    public enum State: String, Equatable, Sendable {
        case insufficient
        case withinNormal
        case suppressed   // acute worse than normal band (fatigue / stress)
        case elevated     // acute better than normal band (positive adaptation)
    }

    public struct MetricResult: Equatable, Sendable {
        public let key: String
        public let label: String
        public let state: State
        public let acuteMean: Double
        public let normalMean: Double
        public let normalLower: Double
        public let normalUpper: Double
        public let nNormal: Int
        public let nAcute: Int
        public let summary: String

        public init(key: String, label: String, state: State,
                    acuteMean: Double, normalMean: Double,
                    normalLower: Double, normalUpper: Double,
                    nNormal: Int, nAcute: Int, summary: String) {
            self.key = key; self.label = label; self.state = state
            self.acuteMean = acuteMean; self.normalMean = normalMean
            self.normalLower = normalLower; self.normalUpper = normalUpper
            self.nNormal = nNormal; self.nAcute = nAcute; self.summary = summary
        }
    }

    public struct Summary: Equatable, Sendable {
        public let hrv: MetricResult?
        public let rhr: MetricResult?
        /// Worst actionable state across metrics (suppressed > elevated > within > insufficient).
        public let overall: State

        public init(hrv: MetricResult?, rhr: MetricResult?, overall: State) {
            self.hrv = hrv; self.rhr = rhr; self.overall = overall
        }
    }

    // MARK: - Entry points

    /// Evaluate HRV + resting HR dual-window readiness from daily metric history.
    /// `days` oldest→newest; the most recent row is "today" unless `today` day-key is given.
    public static func evaluate(days: [DailyMetric], today: String? = nil) -> Summary {
        let sorted = days.sorted { $0.day < $1.day }
        let todayKey = today ?? sorted.last?.day
        guard let todayKey, let idx = sorted.firstIndex(where: { $0.day == todayKey }) else {
            return Summary(hrv: nil, rhr: nil, overall: .insufficient)
        }

        let history = Array(sorted.prefix(idx))
        let todayRow = sorted[idx]

        let hrvHist = history.map(\.avgHrv)
        let rhrHist = history.map { $0.restingHr.map(Double.init) }

        let hrv = evaluate(key: "hrv", label: "HRV",
                           history: hrvHist, today: todayRow.avgHrv,
                           higherIsBetter: true, cfg: Baselines.hrvCfg)
        let rhr = evaluate(key: "rhr", label: "Resting HR",
                           history: rhrHist, today: todayRow.restingHr.map(Double.init),
                           higherIsBetter: false, cfg: Baselines.restingHRCfg)

        let overall = worst(hrv?.state, rhr?.state)
        return Summary(hrv: hrv, rhr: rhr, overall: overall)
    }

    /// Generic dual-window evaluation for one nightly scalar series.
    ///
    /// - Parameters:
    ///   - history: nightly values oldest→newest, **excluding** today.
    ///   - today: tonight's value.
    public static func evaluate(key: String, label: String,
                                history: [Double?], today: Double?,
                                higherIsBetter: Bool, cfg: MetricCfg) -> MetricResult? {
        guard let today else { return nil }

        let normalVals = validTrailing(history, cfg: cfg, window: normalWindowNights)
        guard normalVals.count >= minNormalNights,
              let nStats = meanSD(normalVals) else {
            return insufficient(key: key, label: label)
        }

        var acuteSeries = history
        acuteSeries.append(today)
        let acuteVals = validTrailing(acuteSeries, cfg: cfg, window: acuteWindowNights)
        guard acuteVals.count >= minAcuteNights,
              let aMean = mean(acuteVals) else {
            return insufficient(key: key, label: label)
        }

        let lower = nStats.mean - bandSigma * nStats.sd
        let upper = nStats.mean + bandSigma * nStats.sd

        let state: State
        if higherIsBetter {
            if aMean < lower { state = .suppressed }
            else if aMean > upper { state = .elevated }
            else { state = .withinNormal }
        } else {
            if aMean > upper { state = .suppressed }
            else if aMean < lower { state = .elevated }
            else { state = .withinNormal }
        }

        let summary = summaryFor(label: label, state: state,
                                 acute: aMean, normal: nStats.mean,
                                 lower: lower, upper: upper, unit: unitFor(key: key),
                                 higherIsBetter: higherIsBetter)
        return MetricResult(key: key, label: label, state: state,
                            acuteMean: aMean, normalMean: nStats.mean,
                            normalLower: lower, normalUpper: upper,
                            nNormal: normalVals.count, nAcute: acuteVals.count,
                            summary: summary)
    }

    // MARK: - Helpers

    private struct MeanSD { let mean: Double; let sd: Double }

    private static func validTrailing(_ values: [Double?], cfg: MetricCfg, window: Int) -> [Double] {
        let valid = values.compactMap { v -> Double? in
            guard let v, cfg.minVal <= v && v <= cfg.maxVal else { return nil }
            return v
        }
        return Array(valid.suffix(window))
    }

    private static func mean(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        return xs.reduce(0, +) / Double(xs.count)
    }

    private static func meanSD(_ xs: [Double]) -> MeanSD? {
        guard xs.count >= 2, let m = mean(xs) else { return nil }
        let n = Double(xs.count)
        let varSum = xs.reduce(0.0) { $0 + ($1 - m) * ($1 - m) }
        let sd = sqrt(varSum / (n - 1))
        guard sd > 1e-9 else { return nil }
        return MeanSD(mean: m, sd: sd)
    }

    private static func insufficient(key: String, label: String) -> MetricResult {
        MetricResult(key: key, label: label, state: .insufficient,
                     acuteMean: 0, normalMean: 0, normalLower: 0, normalUpper: 0,
                     nNormal: 0, nAcute: 0,
                     summary: "Wear a few more nights for a \(label) trend read")
    }

    private static func unitFor(key: String) -> String {
        switch key {
        case "hrv": return "ms"
        case "rhr": return "bpm"
        default: return ""
        }
    }

    private static func summaryFor(label: String, state: State,
                                   acute: Double, normal: Double,
                                   lower: Double, upper: Double, unit: String,
                                   higherIsBetter: Bool) -> String {
        let a = Int(acute.rounded())
        let n = Int(normal.rounded())
        switch state {
        case .insufficient:
            return "Wear a few more nights for a \(label) trend read"
        case .withinNormal:
            return String(format: "%@ acute %.0f %@ sits inside your normal band (%.0f–%.0f %@)",
                          label, Double(a), unit, lower.rounded(), upper.rounded(), unit)
        case .suppressed:
            let dir = higherIsBetter ? "below" : "above"
            return String(format: "%@ acute %.0f %@ is %@ your normal band (mean %.0f %@) — recovery may be taxed",
                          label, Double(a), unit, dir, Double(n), unit)
        case .elevated:
            let dir = higherIsBetter ? "above" : "below"
            return String(format: "%@ acute %.0f %@ is %@ your normal band (mean %.0f %@) — a positive stretch",
                          label, Double(a), unit, dir, Double(n), unit)
        }
    }

    private static func worst(_ a: State?, _ b: State?) -> State {
        let rank: [State: Int] = [.insufficient: 0, .withinNormal: 1, .elevated: 2, .suppressed: 3]
        let sa = a.flatMap { rank[$0] } ?? 0
        let sb = b.flatMap { rank[$0] } ?? 0
        let m = max(sa, sb)
        return rank.first(where: { $0.value == m })?.key ?? .insufficient
    }
}
