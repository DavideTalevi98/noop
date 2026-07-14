import XCTest
@testable import Strand

/// Mirror of Android `SleepWindowWatcherTest` + wake-window timing pins.
final class SleepWindowWatcherTests: XCTestCase {

    private func watcher(minSamples: Int = 5) -> SleepWindowWatcher {
        var w = SleepWindowWatcher()
        w.minSamples = minSamples
        w.riseBpm = 6
        w.troughCeilingBpm = 90
        return w
    }

    func testStaysQuietBeforeEnoughSamples() {
        var w = watcher()
        for _ in 0..<4 { XCTAssertFalse(w.shouldWake(bpm: 80)) }
    }

    func testFiresOnceOnRiseAboveTrough() {
        var w = watcher()
        for _ in 0..<6 { XCTAssertFalse(w.shouldWake(bpm: 50)) }
        XCTAssertTrue(w.shouldWake(bpm: 58))
        XCTAssertFalse(w.shouldWake(bpm: 60))
        XCTAssertFalse(w.shouldWake(bpm: 58))
    }

    func testSmallWobbleDoesNotFire() {
        var w = watcher()
        for _ in 0..<6 { XCTAssertFalse(w.shouldWake(bpm: 52)) }
        XCTAssertFalse(w.shouldWake(bpm: 56))
    }

    func testResetAllowsSecondFire() {
        var w = watcher()
        for _ in 0..<6 { _ = w.shouldWake(bpm: 50) }
        XCTAssertTrue(w.shouldWake(bpm: 58))
        w.reset()
        for _ in 0..<6 { XCTAssertFalse(w.shouldWake(bpm: 48)) }
        XCTAssertTrue(w.shouldWake(bpm: 56))
    }

    func testWindowContainsAndPreRamp() {
        let deadline = Date(timeIntervalSince1970: 1_000_000)
        let window = 30
        let start = WakeWindowTiming.windowStart(deadline: deadline, windowMinutes: window)
        XCTAssertEqual(deadline.timeIntervalSince(start), 30 * 60, accuracy: 0.1)
        let mid = start.addingTimeInterval(10 * 60)
        XCTAssertTrue(WakeWindowTiming.contains(mid, deadline: deadline, windowMinutes: window))
        XCTAssertFalse(WakeWindowTiming.contains(deadline, deadline: deadline, windowMinutes: window))
        XCTAssertFalse(WakeWindowTiming.contains(start.addingTimeInterval(-1), deadline: deadline, windowMinutes: window))
        let pre = WakeWindowTiming.preRampAt(deadline: deadline, windowMinutes: window)
        XCTAssertEqual(pre.timeIntervalSince1970,
                       deadline.addingTimeInterval(-15 * 60).timeIntervalSince1970,
                       accuracy: 0.1)
        // Narrow window: pre-ramp cannot open before window start.
        let preNarrow = WakeWindowTiming.preRampAt(deadline: deadline, windowMinutes: 10)
        let narrowStart = WakeWindowTiming.windowStart(deadline: deadline, windowMinutes: 10)
        XCTAssertEqual(preNarrow.timeIntervalSince1970, narrowStart.timeIntervalSince1970, accuracy: 0.1)
    }

    func testClampWindow() {
        XCTAssertEqual(WakeWindowTiming.clampWindow(1), 5)
        XCTAssertEqual(WakeWindowTiming.clampWindow(100), 60)
        XCTAssertEqual(WakeWindowTiming.clampWindow(30), 30)
    }
}
