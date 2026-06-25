import XCTest
@testable import Strand
import StrandAnalytics

/// Pins the WHOOP 4.0 steps-estimate calibration strap-log line (#756). A 4.0 sends no step count over
/// BLE, so steps are ESTIMATED from motion via a coefficient fit against phone steps — and "steps not
/// updating" is almost always "still calibrating, have N of the 3 phone-overlap days needed". This was the
/// one steps signal a strap log had no line for. `stepsCalibrationLogLine` is the pure formatter the loop
/// calls; tested directly. Asserts the SAME strings as the Android `StepsEstimateEngineTest`
/// stepsCalibLine cases, so the two platforms log byte-identical lines (StrandAnalytics doesn't build on
/// Linux CI, so this is the Swift half of that parity guarantee).
@MainActor
final class IntelligenceStepsCalibTests: XCTestCase {

    private typealias IE = IntelligenceEngine
    private let tail = " (WHOOP 4.0 has no BLE step count; estimated from motion calibrated to phone steps)"

    func testCalibrating() {
        // The #756 signature: a 4.0 with motion but not enough phone-overlap days yet → no estimate.
        let line = IE.stepsCalibrationLogLine(status: .needsMoreDays(have: 1, need: 3), estimatedDays: 0)
        XCTAssertEqual(line, "steps calib: calibrating have=1/3, estimated 0 day(s)" + tail)
    }

    func testCalibrated() {
        let line = IE.stepsCalibrationLogLine(
            status: .calibrated(coefficient: 120.0, sampleDays: 5, confidence: 0.78), estimatedDays: 4)
        XCTAssertEqual(line, "steps calib: calibrated coeff=120.0 days=5 conf=0.78, estimated 4 day(s)" + tail)
    }

    func testManual() {
        let line = IE.stepsCalibrationLogLine(
            status: .manual(coefficient: 100.0, sampleDays: 0), estimatedDays: 6)
        XCTAssertEqual(line, "steps calib: manual coeff=100.0 days=0, estimated 6 day(s)" + tail)
    }

    func testLineCarriesNoEmDash() {
        // House style: never an em-dash in shared text.
        let line = IE.stepsCalibrationLogLine(status: .needsMoreDays(have: 0, need: 3), estimatedDays: 0)
        XCTAssertFalse(line.contains("—"))
    }
}
