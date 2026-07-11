import Foundation

// BaselineChangePoint.swift — two-sided CUSUM mean-shift detection on nightly metrics.
//
// Pure, deterministic, DB-free. Flags when a personal baseline (HRV, RHR, etc.) has likely
// shifted — illness, training block, lifestyle change — using the standard CUSUM algorithm
// (k slack, h threshold in σ units). After each detection the reference mean/SD re-estimates
// from the next `initWindow` points (python-fiddle / epidemiological CUSUM best practice).
//
// APPROXIMATE — informational, not a diagnosis.

public enum BaselineChangePoint {

    // MARK: - Tunables (pinned by test; mirror Kotlin twin)

    /// CUSUM slack k (half the minimum shift to detect, in σ units). Standard start: 0.5.
    public static let slackK: Double = 0.5
    /// Decision threshold h (in σ units). Standard start: 4.0.
    public static let thresholdH: Double = 4.0
    /// Nights used to seed μ/σ before accumulation, and to re-baseline after a detection.
    public static let initWindow: Int = 14
    /// Minimum series length before detection runs.
    public static let minSeriesLength: Int = 21

    // MARK: - Types

    public enum Direction: String, Equatable, Sendable {
        case increase
        case decrease
    }

    public struct Event: Equatable, Sendable {
        /// Index in the input `values` array (0 = oldest).
        public let index: Int
        public let direction: Direction
        /// Signed shift at detection in σ units (approximate).
        public let shiftZ: Double

        public init(index: Int, direction: Direction, shiftZ: Double) {
            self.index = index; self.direction = direction; self.shiftZ = shiftZ
        }
    }

    public struct Result: Equatable, Sendable {
        public let events: [Event]
        /// Most recent event, if any.
        public let mostRecent: Event?
        /// Plain-English summary for UI, or nil when nothing detected / insufficient data.
        public let summary: String?

        public init(events: [Event], mostRecent: Event?, summary: String?) {
            self.events = events; self.mostRecent = mostRecent; self.summary = summary
        }
    }

    // MARK: - Entry point

    /// Detect mean shifts in `values` (oldest→newest). Requires at least [minSeriesLength] points.
    public static func detect(values: [Double],
                              k: Double = slackK,
                              h: Double = thresholdH,
                              initWindow: Int = initWindow) -> Result {
        guard values.count >= minSeriesLength, initWindow >= 2, initWindow < values.count else {
            return Result(events: [], mostRecent: nil, summary: nil)
        }

        var mu = mean(Array(values.prefix(initWindow)))
        var sigma = max(sd(Array(values.prefix(initWindow))), 1e-6)

        var events: [Event] = []
        var sPos = 0.0
        var sNeg = 0.0
        var resumeAt = initWindow

        for i in initWindow..<values.count {
            if i < resumeAt { continue }
            let z = (values[i] - mu) / sigma
            sPos = max(0, sPos + z - k)
            sNeg = max(0, sNeg - z - k)

            if sPos > h {
                events.append(Event(index: i, direction: .increase, shiftZ: z))
                let end = min(i + initWindow, values.count)
                let slice = Array(values[i..<end])
                if slice.count >= 2 {
                    mu = mean(slice)
                    sigma = max(sd(slice), 1e-6)
                }
                sPos = 0; sNeg = 0
                resumeAt = end
            } else if sNeg > h {
                events.append(Event(index: i, direction: .decrease, shiftZ: z))
                let end = min(i + initWindow, values.count)
                let slice = Array(values[i..<end])
                if slice.count >= 2 {
                    mu = mean(slice)
                    sigma = max(sd(slice), 1e-6)
                }
                sPos = 0; sNeg = 0
                resumeAt = end
            }
        }

        let recent = events.last
        let summary = summaryFor(events: events, values: values)
        return Result(events: events, mostRecent: recent, summary: summary)
    }

    /// Convenience: extract valid nightly values from a nullable series with physiological bounds.
    public static func detect(series: [Double?], cfg: MetricCfg) -> Result {
        let valid = series.compactMap { v -> Double? in
            guard let v, cfg.minVal <= v && v <= cfg.maxVal else { return nil }
            return v
        }
        return detect(values: valid)
    }

    // MARK: - Helpers

    private static func mean(_ xs: [Double]) -> Double {
        xs.reduce(0, +) / Double(xs.count)
    }

    private static func sd(_ xs: [Double]) -> Double {
        guard xs.count >= 2 else { return 0 }
        let m = mean(xs)
        let n = Double(xs.count)
        let v = xs.reduce(0.0) { $0 + ($1 - m) * ($1 - m) } / (n - 1)
        return sqrt(v)
    }

    private static func summaryFor(events: [Event], values: [Double]) -> String? {
        guard let last = events.last else { return nil }
        let nightsAgo = values.count - 1 - last.index
        let dir = last.direction == .increase ? "rose" : "fell"
        if nightsAgo == 0 {
            return String(format: "Your baseline likely %@ on the most recent night", dir)
        }
        return String(format: "Your baseline likely %@ about %d nights ago", dir, nightsAgo)
    }
}
