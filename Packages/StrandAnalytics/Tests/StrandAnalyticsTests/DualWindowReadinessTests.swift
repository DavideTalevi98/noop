import XCTest
@testable import StrandAnalytics
import WhoopStore

final class DualWindowReadinessTests: XCTestCase {

    private func d(_ day: String, hrv: Double?, rhr: Int?) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: nil, efficiency: nil,
                    deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil,
                    restingHr: rhr, avgHrv: hrv, recovery: nil, strain: nil,
                    exerciseCount: nil, spo2Pct: nil, skinTempDevC: nil, respRateBpm: nil)
    }

    func testInsufficientWithShortHistory() {
        let days = (1...10).map { d(String(format: "2024-01-%02d", $0), hrv: 60, rhr: 50) }
        let r = DualWindowReadiness.evaluate(days: days)
        XCTAssertEqual(r.overall, .insufficient)
    }

    func testHRVSuppressedWhenAcuteDips() {
        let hist = (1...20).map { i in (58.0 + Double(i % 4)) as Double? }
        let today = 40.0
        let r = DualWindowReadiness.evaluate(key: "hrv", label: "HRV",
                                             history: hist, today: today,
                                             higherIsBetter: true, cfg: Baselines.hrvCfg)!
        XCTAssertEqual(r.state, .suppressed)
        XCTAssertLessThan(r.acuteMean, r.normalLower)
    }

    func testRHRSuppressedWhenAcuteElevated() {
        let hist = (1...20).map { i in (49.0 + Double(i % 2)) as Double? }
        let today = 62.0
        let r = DualWindowReadiness.evaluate(key: "rhr", label: "Resting HR",
                                             history: hist, today: today,
                                             higherIsBetter: false, cfg: Baselines.restingHRCfg)!
        XCTAssertEqual(r.state, .suppressed)
        XCTAssertGreaterThan(r.acuteMean, r.normalUpper)
    }

    func testWithinNormalOnStableSeries() {
        let hist = (1...20).map { i in (58.0 + Double(i % 3)) as Double? }
        let r = DualWindowReadiness.evaluate(key: "hrv", label: "HRV",
                                             history: hist, today: 59.0,
                                             higherIsBetter: true, cfg: Baselines.hrvCfg)!
        XCTAssertEqual(r.state, .withinNormal)
    }

    func testEndToEndFromDailyMetrics() {
        var days: [DailyMetric] = []
        for i in 1...25 {
            days.append(d(String(format: "2024-02-%02d", i), hrv: 60, rhr: 50))
        }
        for i in 26...30 {
            days.append(d(String(format: "2024-02-%02d", i), hrv: 42, rhr: 58))
        }
        let r = DualWindowReadiness.evaluate(days: days, today: "2024-02-30")
        XCTAssertEqual(r.hrv?.state, .suppressed)
        XCTAssertEqual(r.rhr?.state, .suppressed)
        XCTAssertEqual(r.overall, .suppressed)
    }
}
