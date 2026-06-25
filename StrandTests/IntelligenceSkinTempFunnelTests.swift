import XCTest
@testable import Strand
import StrandAnalytics

/// Pins the skin-temp derivation funnel strap-log line (#727). The recurring "skin temperature never
/// shows" reports need the WHOLE funnel in the log, not just a final nil: banked `raw` → `worn` (concurrent
/// worn HR) → `inSession` (inside a detected sleep span) → `plausible` (28–42 °C, ≥min for a mean) →
/// `baseline` (≥4 nights) → `dev`. `skinTempFunnelLogLine` is the pure formatter the loop calls; it's
/// tested directly (no store). Asserts the SAME strings as the Android `SkinTempAnalyticsTest`
/// skinTempFunnelLogLine cases, so the two platforms log byte-identical lines (StrandAnalytics doesn't
/// build on Linux CI, so this is the Swift half of that parity guarantee).
@MainActor
final class IntelligenceSkinTempFunnelTests: XCTestCase {

    private typealias IE = IntelligenceEngine

    func testHealthyNight() {
        // Every gate passed: a clean night with a +0.30 °C deviation. The exact line a triager reads.
        let f = AnalyticsEngine.SkinTempFunnel(mean: 30.6, raw: 412, worn: 380, inSession: 360,
                                               plausible: 355, minSamples: 300)
        let line = IE.skinTempFunnelLogLine(day: "2026-06-24", funnel: f, dev: 0.30, baselineNValid: 4)
        XCTAssertEqual(line,
            "skintemp day=2026-06-24 raw=412 worn=380 inSession=360 plausible=355/300 "
            + "mean=30.6°C baseline=4/4 dev=+0.30")
    }

    func testStrapBankedNothing_isNilNotZero() {
        // The #727 signature: the strap banked no DSP sleep samples, so the funnel is all-zero and the
        // mean/dev read "nil" (not 0). The line is still emitted so the night stays visible in the log.
        let f = AnalyticsEngine.SkinTempFunnel(mean: nil, raw: 0, worn: 0, inSession: 0,
                                               plausible: 0, minSamples: 300)
        let line = IE.skinTempFunnelLogLine(day: "2026-06-22", funnel: f, dev: nil, baselineNValid: 2)
        XCTAssertEqual(line,
            "skintemp day=2026-06-22 raw=0 worn=0 inSession=0 plausible=0/300 mean=nil baseline=2/4 dev=nil")
    }

    func testLineCarriesNoEmDash() {
        // House style: never an em-dash in shared text.
        let f = AnalyticsEngine.SkinTempFunnel(mean: 30.6, raw: 1, worn: 1, inSession: 1,
                                               plausible: 1, minSamples: 300)
        let line = IE.skinTempFunnelLogLine(day: "2026-06-24", funnel: f, dev: 0.30, baselineNValid: 4)
        XCTAssertFalse(line.contains("—"))
    }
}
