import XCTest
@testable import StrandAnalytics

/// Pins the SpO2 RE dump line format. The OUTPUT must be byte-identical to the Kotlin Spo2ReTraceTest
/// (same `spo2re …` shape), even though the Swift signature takes already-extracted ints.
final class Spo2ReTraceTests: XCTestCase {

    func testRecordLineFormatsHexAndFields() {
        let line = Spo2ReTrace.recordLine(frame: [0x00, 0x0f, 0xff, 0x10],
                                          version: 24, unix: 1_700_000_000,
                                          red: 512, ir: 480, skinRaw: 330)
        XCTAssertTrue(line.hasPrefix("spo2re "))
        XCTAssertTrue(line.contains("v=24"))
        XCTAssertTrue(line.contains("unix=1700000000"))
        XCTAssertTrue(line.contains("red=512"))
        XCTAssertTrue(line.contains("ir=480"))
        XCTAssertTrue(line.contains("skinRaw=330"))
        XCTAssertTrue(line.contains("len=4"))
        XCTAssertTrue(line.contains("raw=000fff10")) // FULL frame hex, unsigned bytes, no prefix cap
    }

    func testAbsentChannelsRenderNull() {
        let line = Spo2ReTrace.recordLine(frame: [1, 2, 3], version: 25, unix: 42,
                                          red: nil, ir: nil, skinRaw: nil)
        XCTAssertTrue(line.contains("red=null"))
        XCTAssertTrue(line.contains("ir=null"))
        XCTAssertTrue(line.contains("raw=010203"))
    }

    func testMaxSamplesBounded() {
        XCTAssertEqual(Spo2ReTrace.maxSamples, 8)
    }
}
