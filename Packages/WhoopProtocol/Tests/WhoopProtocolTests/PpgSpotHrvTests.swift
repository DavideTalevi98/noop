import XCTest
@testable import WhoopProtocol

/// Spot HRV from v26 PPG bursts — synthetic sine checks + Streams decode tolerance.
final class PpgSpotHrvTests: XCTestCase {

    /// A clean ~60 bpm sine over 40 contiguous seconds at 24 Hz must yield a GOOD (or at least
    /// non-nil) spot with RMSSD in a plausible resting band.
    func testCleanSineBurstYieldsSpot() {
        let records = sineRecords(bpm: 60, seconds: 40)
        let spots = PpgSpotHrv.derive(records: records)
        XCTAssertEqual(spots.count, 1, "one contiguous burst → one spot")
        guard let s = spots.first else { return }
        XCTAssertGreaterThan(s.rmssdMs, 0)
        XCTAssertEqual(s.hrBpm, 60, accuracy: 8)
        XCTAssertTrue(["GOOD", "COARSE", "POOR"].contains(s.quality))
    }

    /// A burst shorter than 20 s is ignored (matches the python tool's covered-window gate).
    func testShortBurstDropped() {
        let records = sineRecords(bpm: 70, seconds: 12)
        XCTAssertTrue(PpgSpotHrv.derive(records: records).isEmpty)
    }

    func testMedianGoodIgnoresCoarseAndPoor() {
        let samples = [
            PpgSpotHrvSample(ts: 1, rmssdMs: 40, hrBpm: 60, beats: 5, quality: "POOR"),
            PpgSpotHrvSample(ts: 2, rmssdMs: 80, hrBpm: 55, beats: 30, quality: "GOOD"),
            PpgSpotHrvSample(ts: 3, rmssdMs: 100, hrBpm: 58, beats: 28, quality: "GOOD"),
            PpgSpotHrvSample(ts: 4, rmssdMs: 50, hrBpm: 62, beats: 15, quality: "COARSE"),
        ]
        XCTAssertEqual(PpgSpotHrv.medianGoodRmssd(samples)!, 90, accuracy: 1e-9)
        XCTAssertNil(PpgSpotHrv.medianGoodRmssd(samples.filter { $0.quality != "GOOD" }))
    }

    func testStreamsDecodeToleratesMissingPpgSpotHrvKey() throws {
        let json = #"{"hr":[],"rr":[]}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(Streams.self, from: json)
        XCTAssertTrue(s.ppgSpotHrv.isEmpty)
    }

    // MARK: - helpers

    private func sineRecords(bpm: Double, seconds: Int) -> [(ts: Int, samples: [Int])] {
        let fs = PpgSpotHrv.sampleRateHz
        let base = 1_780_000_000
        var out = [(ts: Int, samples: [Int])]()
        for s in 0..<seconds {
            var samples = [Int]()
            for i in 0..<fs {
                let t = Double(s) + Double(i) / Double(fs)
                let phase = 2 * Double.pi * (bpm / 60.0) * t
                samples.append(Int((1000.0 * sin(phase)).rounded()))
            }
            out.append((ts: base + s, samples: samples))
        }
        return out
    }
}
