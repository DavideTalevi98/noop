import Foundation

/// Spot HRV (RMSSD) from sparse WHOOP 5/MG **v26** optical PPG bursts.
///
/// The historical offload's packed R-R field saturates/underestimates overnight HRV on 5/MG, but the
/// strap also banks a real 24 Hz PPG waveform in sparse optical bursts (~40 s every ~18 min). That
/// waveform is genuine cardiac PPG — beats can be detected and RMSSD computed directly from it.
/// Mirrors `tools/linux-capture/whoop_spot_hrv.py` (byte-for-byte algorithm intent; Kotlin twin must
/// stay locked). Pure + Foundation-only so it is unit-testable from synthetic and captured waveforms.
///
/// Honesty limits (surface in UI, never invent quality):
/// - **SPARSE** — a window only gets HRV if a burst lands in it; this is spot HRV, not continuous.
/// - **COARSE** — 24 Hz quantises beat timing (~42 ms/sample); treat RMSSD as approximate.
/// - **Quality** — GOOD (≥25 clean successive RR), COARSE (10…24), POOR (<10 or no RMSSD).
/// - **Not SpO₂** — the PPG is AC-coupled; no DC red/IR for blood oxygen.

public struct PpgSpotHrvSample: Equatable, Codable, Sendable {
    public let ts: Int              // wall-clock unix seconds (burst start)
    public let rmssdMs: Double      // RMSSD in milliseconds
    public let hrBpm: Double        // median-RR heart rate for the burst
    public let beats: Int           // clean successive RR pairs used (n_clean)
    public let quality: String      // "GOOD" | "COARSE" | "POOR"
    public init(ts: Int, rmssdMs: Double, hrBpm: Double, beats: Int, quality: String) {
        self.ts = ts; self.rmssdMs = rmssdMs; self.hrBpm = hrBpm
        self.beats = beats; self.quality = quality
    }
}

public enum PpgSpotHrv {
    public static let sampleRateHz = 24
    /// Minimum contiguous seconds in a burst before we attempt a spot reading (python: ≥20).
    public static let minBurstSeconds = 20
    public static let glitchThreshold = 0.30   // successive RR jump fraction → ectopic

    /// Derive one spot HRV sample per contiguous v26 PPG burst (≥ `minBurstSeconds`).
    /// Records may be unsorted / gappy; duplicates at the same ts keep the last write.
    public static func derive(records: [(ts: Int, samples: [Int])],
                              fs: Int = sampleRateHz) -> [PpgSpotHrvSample] {
        guard !records.isEmpty, fs > 0 else { return [] }
        var secs = [Int: [Int]]()
        for r in records { secs[r.ts] = r.samples }
        let order = secs.keys.sorted()
        var runs = [[Int]]()
        var cur = [order[0]]
        for u in order.dropFirst() {
            if u - cur.last! == 1 { cur.append(u) }
            else { runs.append(cur); cur = [u] }
        }
        runs.append(cur)

        var out = [PpgSpotHrvSample]()
        for run in runs where run.count >= minBurstSeconds {
            var values = [Double]()
            var times = [Double]()
            let base = run[0]
            for u in run {
                guard let samples = secs[u], !samples.isEmpty else { continue }
                let n = Double(samples.count)
                for (i, s) in samples.enumerated() {
                    times.append(Double(u - base) + Double(i) / n)
                    values.append(Double(s))
                }
            }
            if let spot = spotHrv(times: times, values: values, fs: Double(fs)) {
                out.append(PpgSpotHrvSample(
                    ts: base,
                    rmssdMs: spot.rmssd,
                    hrBpm: spot.hr,
                    beats: spot.nClean,
                    quality: spot.quality
                ))
            }
        }
        return out
    }

    /// Median of GOOD-quality RMSSD values, or nil when none. Used as the overnight HRV fallback /
    /// preference when the packed R-R path is empty or weaker on WHOOP 5/MG.
    public static func medianGoodRmssd(_ samples: [PpgSpotHrvSample]) -> Double? {
        let good = samples.filter { $0.quality == "GOOD" }.map(\.rmssdMs).sorted()
        guard !good.isEmpty else { return nil }
        let mid = good.count / 2
        if good.count % 2 == 0 {
            return (good[mid - 1] + good[mid]) / 2
        }
        return good[mid]
    }

    // MARK: - DSP (mirrors whoop_spot_hrv.py)

    struct Spot {
        let hr: Double
        let rmssd: Double
        let nClean: Int
        let quality: String
    }

    static func spotHrv(times: [Double], values: [Double], fs: Double) -> Spot? {
        guard values.count >= 30, fs > 0 else { return nil }
        let vv = detrend(values, win: Int(fs))
        let sd = pstdev(vv) ?? 1.0
        let peaks = findPeaks(vv, minDist: Int(0.4 * fs), minProm: 0.3 * sd)
        let beatTimes = peaks.map { p in times[p] + interp(vv, p) / fs }
        var rr = [Double]()
        for i in 0..<(beatTimes.count - 1) {
            let ms = (beatTimes[i + 1] - beatTimes[i]) * 1000.0
            if (300...2000).contains(ms) { rr.append(ms) }
        }
        guard rr.count >= 2 else { return nil }
        let hr = 60_000.0 / median(rr)
        guard let rmssd = rmssdSequential(rr) else { return nil }
        var nClean = 0
        for i in 1..<rr.count {
            if abs(rr[i] - rr[i - 1]) <= glitchThreshold * rr[i - 1] { nClean += 1 }
        }
        let quality: String
        if nClean < 10 { quality = "POOR" }
        else if nClean >= 25 { quality = "GOOD" }
        else { quality = "COARSE" }
        return Spot(hr: hr, rmssd: rmssd, nClean: nClean, quality: quality)
    }

    /// Centred moving-average detrend (removes PPG baseline wander).
    static func detrend(_ v: [Double], win: Int) -> [Double] {
        let n = v.count
        let h = max(1, win / 2)
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let lo = max(0, i - h)
            let hi = min(n, i + h + 1)
            var sum = 0.0
            for j in lo..<hi { sum += v[j] }
            out[i] = v[i] - sum / Double(hi - lo)
        }
        return out
    }

    /// Local maxima ≥ neighbours and ≥ minProm, spaced ≥ minDist (keep the taller on conflict).
    static func findPeaks(_ v: [Double], minDist: Int, minProm: Double) -> [Int] {
        var cand = [Int]()
        guard v.count >= 3 else { return [] }
        for i in 1..<(v.count - 1) {
            if v[i] > v[i - 1], v[i] >= v[i + 1], v[i] > minProm { cand.append(i) }
        }
        cand.sort { v[$0] > v[$1] }
        var kept = [Int]()
        for i in cand {
            if kept.allSatisfy({ abs(i - $0) >= minDist }) { kept.append(i) }
        }
        return kept.sorted()
    }

    /// Parabolic sub-sample peak offset around index p.
    static func interp(_ v: [Double], _ p: Int) -> Double {
        guard p > 0, p < v.count - 1 else { return 0 }
        let a = v[p - 1], b = v[p], c = v[p + 1]
        let den = a - 2 * b + c
        return den != 0 ? (a - c) / (2 * den) : 0
    }

    /// RMSSD over consecutive RR, skipping pairs where either RR jumped > thr (ectopic/artifact).
    /// Population denominator (n) — matches the python tool; nightly Task-Force (n-1) stays on the RR path.
    static func rmssdSequential(_ rr: [Double], thr: Double = glitchThreshold) -> Double? {
        guard rr.count >= 2 else { return nil }
        var glitch = [Bool](repeating: false, count: rr.count)
        for i in 1..<rr.count {
            if abs(rr[i] - rr[i - 1]) > thr * rr[i - 1] { glitch[i] = true }
        }
        var d = [Double]()
        for i in 1..<rr.count where !glitch[i - 1] && !glitch[i] {
            d.append(rr[i] - rr[i - 1])
        }
        guard d.count >= 2 else { return nil }
        let meanSq = d.reduce(0.0) { $0 + $1 * $1 } / Double(d.count)
        return meanSq.squareRoot()
    }

    static func median(_ x: [Double]) -> Double {
        let s = x.sorted()
        let mid = s.count / 2
        return s.count % 2 == 0 ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }

    static func pstdev(_ x: [Double]) -> Double? {
        guard x.count >= 2 else { return nil }
        let mean = x.reduce(0, +) / Double(x.count)
        let varPop = x.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(x.count)
        return varPop.squareRoot()
    }
}
