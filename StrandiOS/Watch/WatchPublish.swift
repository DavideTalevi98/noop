#if os(iOS)
import Foundation
import StrandDesign

/// iOS-only hook so shared `AppModel` code can push watch snapshots without owning a
/// `WatchSessionBridge` instance. `StrandiOSApp` sets `bridge` once at launch.
@MainActor
enum WatchPublish {
    static weak var bridge: WatchSessionBridge?

    static func pushLatest(from model: AppModel, urgency: WatchPushUrgency) async {
        await bridge?.pushLatest(from: model, urgency: urgency)
    }
}
#endif
