import Foundation

/// Light-sleep / arousal detector for the iOS/macOS wake window — twin of Android
/// `SleepWindowWatcher` (#207). Pure, so unit-tested without BLE.
///
/// HONEST signal: deep sleep sits near a nightly HR trough; lighter sleep / arousal lifts above it.
/// This is NOT a clinical stage classifier (no REM/deep claim). Advisory only — the strap firmware
/// alarm at the window's hard deadline is the safety floor.
struct SleepWindowWatcher: Sendable {
    /// How far above the nightly trough (bpm) counts as "lighter / stirring".
    var riseBpm: Int = 6
    /// Don't trust the trough until we've seen at least this many samples this night.
    var minSamples: Int = 30
    /// Ignore obviously-awake-high HR as a trough candidate.
    var troughCeilingBpm: Int = 90

    private var troughBpm: Int = .max
    private var sampleCount: Int = 0
    private var fired: Bool = false

    mutating func reset() {
        troughBpm = .max
        sampleCount = 0
        fired = false
    }

    /// Feed one smoothed HR reading. Returns true exactly once when the reading first looks like a
    /// lighter phase — later calls return false until `reset`.
    mutating func shouldWake(bpm: Int) -> Bool {
        guard bpm > 0 else { return false }
        sampleCount += 1
        if bpm <= troughCeilingBpm, bpm < troughBpm { troughBpm = bpm }
        if fired { return false }
        if sampleCount < minSamples || troughBpm == .max { return false }
        if bpm >= troughBpm + riseBpm, bpm > troughBpm {
            fired = true
            return true
        }
        return false
    }
}

/// Pure wake-window timing. `deadlineMinutes` is the hard "wake by" (firmware + backup).
/// `windowMinutes` is how far BEFORE that the soft/early layer may fire.
enum WakeWindowTiming {
    static let windowMin = 5
    static let windowMax = 60
    static let defaultWindow = 30
    /// Soft pre-buzz this many minutes before the hard deadline (clamped into the window).
    static let preRampLeadMinutes = 15

    static func clampWindow(_ minutes: Int) -> Int {
        min(max(minutes, windowMin), windowMax)
    }

    /// Window opens at `deadline - window` (same calendar day math as the deadline instant).
    static func windowStart(deadline: Date, windowMinutes: Int) -> Date {
        deadline.addingTimeInterval(-Double(clampWindow(windowMinutes)) * 60)
    }

    /// Soft pre-ramp instant: `max(windowStart, deadline - preRampLead)`.
    static func preRampAt(deadline: Date, windowMinutes: Int) -> Date {
        let start = windowStart(deadline: deadline, windowMinutes: windowMinutes)
        let lead = deadline.addingTimeInterval(-Double(preRampLeadMinutes) * 60)
        return max(start, lead)
    }

    static func contains(_ now: Date, deadline: Date, windowMinutes: Int) -> Bool {
        let start = windowStart(deadline: deadline, windowMinutes: windowMinutes)
        return now >= start && now < deadline
    }
}
