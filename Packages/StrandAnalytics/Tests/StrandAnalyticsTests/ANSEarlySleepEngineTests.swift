import XCTest
@testable import StrandAnalytics
import WhoopProtocol

final class ANSEarlySleepEngineTests: XCTestCase {

    private func snap(hr: Double, hrv: Double, resp: Double) -> ANSEarlySleepEngine.NightSnapshot {
        ANSEarlySleepEngine.NightSnapshot(hrBpm: hr, rmssdMs: hrv, respBpm: resp)
    }

    private func baselineHistory(count: Int = 10,
                                 hr: Double = 52, hrv: Double = 60, resp: Double = 14) -> [ANSEarlySleepEngine.NightSnapshot] {
        (0..<count).enumerated().map { i, _ in
            let jitter = Double(i % 3) - 1.0
            return snap(hr: hr + jitter, hrv: hrv + jitter, resp: resp + jitter * 0.1)
        }
    }

    func testInsufficientHistory() {
        let tonight = snap(hr: 50, hrv: 65, resp: 13)
        XCTAssertNil(ANSEarlySleepEngine.evaluate(snapshot: tonight, history: baselineHistory(count: 5)))
    }

    func testGoodChargeWhenAllSignalsBetter() {
        let history = baselineHistory(hr: 55, hrv: 55, resp: 15)
        let tonight = snap(hr: 48, hrv: 70, resp: 13)
        let r = ANSEarlySleepEngine.evaluate(snapshot: tonight, history: history)!
        XCTAssertGreaterThanOrEqual(r.charge, 67)
        XCTAssertEqual(r.level, .good)
        XCTAssertGreaterThan(r.compositeZ, 0)
    }

    func testCompromisedWhenHRAndHRVWorse() {
        let history = baselineHistory(hr: 50, hrv: 65, resp: 14)
        let tonight = snap(hr: 60, hrv: 45, resp: 16)
        let r = ANSEarlySleepEngine.evaluate(snapshot: tonight, history: history)!
        XCTAssertLessThan(r.charge, 34)
        XCTAssertEqual(r.level, .compromised)
        XCTAssertLessThan(r.compositeZ, 0)
    }

    func testSnapshotRejectsThinWindow() {
        let onset = 1_700_000_000
        let hr = [HRSample(ts: onset + 3600, bpm: 50)]
        XCTAssertNil(ANSEarlySleepEngine.snapshot(sleepOnsetTs: onset, hr: hr, rr: []))
    }

    func testSnapshotFromSyntheticStreams() {
        let onset = 1_700_000_000
        let start = onset + ANSEarlySleepEngine.onsetDelaySec
        var hr: [HRSample] = []
        var rr: [RRInterval] = []
        for i in 0..<(4 * 3600) {
            let ts = start + i
            hr.append(HRSample(ts: ts, bpm: 50 + (i % 4)))
            // ~15 bpm breathing modulation on ~1000 ms base RR
            let mod = Int(40 * sin(Double(i) / 4.0))
            rr.append(RRInterval(ts: ts, rrMs: 1000 + mod))
        }
        let snap = ANSEarlySleepEngine.snapshot(sleepOnsetTs: onset, hr: hr, rr: rr)
        XCTAssertNotNil(snap)
        XCTAssertGreaterThan(snap!.rmssdMs, 0)
    }
}
