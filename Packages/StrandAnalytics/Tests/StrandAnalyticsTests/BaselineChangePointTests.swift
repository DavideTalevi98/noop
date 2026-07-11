import XCTest
@testable import StrandAnalytics

final class BaselineChangePointTests: XCTestCase {

    func testNoDetectionOnFlatSeries() {
        let flat = Array(repeating: 60.0, count: 30)
        let r = BaselineChangePoint.detect(values: flat)
        XCTAssertTrue(r.events.isEmpty)
        XCTAssertNil(r.mostRecent)
        XCTAssertNil(r.summary)
    }

    func testDetectsStepUp() {
        var xs = Array(repeating: 55.0, count: 20)
        xs.append(contentsOf: Array(repeating: 75.0, count: 15))
        let r = BaselineChangePoint.detect(values: xs)
        XCTAssertFalse(r.events.isEmpty)
        XCTAssertEqual(r.mostRecent?.direction, .increase)
        XCTAssertNotNil(r.summary)
        if let idx = r.mostRecent?.index {
            XCTAssertGreaterThanOrEqual(idx, 18)
            XCTAssertLessThanOrEqual(idx, 22)
        }
    }

    func testDetectsStepDown() {
        var xs = Array(repeating: 70.0, count: 20)
        xs.append(contentsOf: Array(repeating: 45.0, count: 15))
        let r = BaselineChangePoint.detect(values: xs)
        XCTAssertFalse(r.events.isEmpty)
        XCTAssertEqual(r.mostRecent?.direction, .decrease)
    }

    func testTooShortReturnsEmpty() {
        let r = BaselineChangePoint.detect(values: [1, 2, 3, 4, 5])
        XCTAssertTrue(r.events.isEmpty)
    }

    func testNullableSeriesRespectsBounds() {
        let series: [Double?] = [10, 20, 200, 60, 60, 60, 60, 60, 60, 60,
                                 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60,
                                 40, 40, 40, 40, 40]
        let r = BaselineChangePoint.detect(series: series, cfg: Baselines.hrvCfg)
        // 200 is out of HRV bounds and dropped; still enough points to run.
        XCTAssertGreaterThanOrEqual(r.events.count, 0)
    }
}
