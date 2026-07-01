import Foundation

/// How NOOP holds the dense realtime R-R ("Continuous HRV capture") stream open with no Live screen
/// visible. The realtime flood is the single biggest phone-radio + strap-battery cost NOOP incurs, and
/// its whole rationale is *overnight* HRV/recovery/sleep — so `.overnight` limits the always-on stream to
/// the sleep window, roughly halving the realtime duty cycle while keeping the benefit the feature exists
/// for. `.always` preserves the original 24/7 behaviour; `.off` never holds it open. Behaviour twin of the
/// Android `ContinuousCaptureMode`.
public enum ContinuousCaptureMode: Equatable, Sendable { case off, overnight, always }

/// Pure decision for whether continuous capture wants the realtime stream armed right now. Clock-free:
/// the caller passes local minutes-of-day, so this stays unit-testable and is the twin of the Android
/// `ContinuousCapture`.
public enum ContinuousCapture {
    /// Default `.overnight` window: 21:30 -> 09:30 local, as minutes-of-day, wrapping past midnight.
    /// Generous on both edges so a late night / long lie-in isn't clipped. Kept a fixed default for now;
    /// a later pass can refine it from the smart-alarm wake time + wind-down bedtime the app computes.
    public static let windowStartMin = 21 * 60 + 30   // 21:30
    public static let windowEndMin = 9 * 60 + 30       // 09:30

    /// Does continuous capture want the realtime stream armed at `nowMinuteOfDay` (0..1439) under `mode`?
    public static func wantsStreamNow(_ mode: ContinuousCaptureMode, nowMinuteOfDay: Int) -> Bool {
        switch mode {
        case .off: return false
        case .always: return true
        case .overnight: return inOvernightWindow(nowMinuteOfDay)
        }
    }

    /// True when `min` falls in the wrap-around window [windowStartMin, windowEndMin).
    public static func inOvernightWindow(_ min: Int) -> Bool {
        windowStartMin <= windowEndMin
            ? (min >= windowStartMin && min < windowEndMin)
            : (min >= windowStartMin || min < windowEndMin)
    }
}
