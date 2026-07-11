import Foundation
import Combine
import WatchConnectivity
import WidgetKit
import StrandDesign

// MARK: - WatchScoreStore — the watch side of the phone->watch bridge
//
// Activates WCSession on the watch, receives the latest score snapshot the phone pushed via
// `updateApplicationContext` (latest-state semantics, no queue buildup), persists it into the shared
// App Group so the complication can read the same bytes, and reloads the complication timelines so the
// watch face matches the glance. The phone is the brain; this object never computes a score, it only
// carries the one the phone already earned.
//
// The published `snapshot` is what the glance binds to. It starts from whatever was last persisted to the
// App Group (so a relaunch shows the last-known scores immediately, with an honest "as of" age) and is
// nil only on a truly fresh install, which the glance renders as the "open NOOP on your iPhone" state.
@MainActor
final class WatchScoreStore: NSObject, ObservableObject, @preconcurrency WCSessionDelegate {

    /// The latest snapshot the watch knows about. nil = nothing has ever synced (fresh install).
    @Published private(set) var snapshot: WatchScoreSnapshot?

    /// The shared App Group suite the watch app + its complication both read/write. The watch reads its
    /// own bundle's AppGroupIdentifier Info.plist key (injected from $(APP_GROUP_ID) in project.yml) so
    /// the value is never hard-coded in Swift, then falls back to the canonical group defined ONCE in
    /// the shared contract (StrandDesign) so the writer and readers can't desync on it.
    static let suiteName: String = {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
            ?? WatchScoreSnapshot.appGroupId
    }()

    /// The key the complication also reads. The single source of truth lives in the shared contract.
    static let storageKey = WatchScoreSnapshot.storageKey

    override init() {
        super.init()
        // Show the last-known snapshot straight away (honest about its age via the glance's "as of").
        snapshot = Self.loadPersisted()
        activate()
    }

    /// Bring up the WCSession so the phone can reach us. Guarded because the simulator / an unpaired
    /// state can report the session unsupported, in which case we simply run on the last persisted snapshot.
    private func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Ask the phone to rebuild and push the latest scores now (interactive urgency on the phone side).
    func requestLatestFromPhone() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let payload = [WatchScoreSnapshot.wcRequestLatestKey: true] as [String: Any]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: { [weak self] reply in
                guard let self,
                      let data = reply[WatchScoreSnapshot.wcContextKey] as? Data,
                      let snap = try? JSONDecoder().decode(WatchScoreSnapshot.self, from: data) else { return }
                Task { @MainActor in self.apply(snap) }
            }, errorHandler: { _ in })
        } else {
            // Application context delivers when the phone next wakes; this nudges a rebuild if reachable later.
            session.transferUserInfo(payload)
        }
    }

    // MARK: Persistence (shared with the complication)

    /// Read the last snapshot the phone delivered, if any. The complication uses the same key.
    static func loadPersisted() -> WatchScoreSnapshot? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: storageKey),
              let snap = try? JSONDecoder().decode(WatchScoreSnapshot.self, from: data) else { return nil }
        return snap
    }

    /// Persist a snapshot into the shared group so the complication reads the SAME bytes the glance shows.
    /// They can never disagree because there is one source of truth.
    private func persist(_ snap: WatchScoreSnapshot) {
        guard let defaults = UserDefaults(suiteName: Self.suiteName),
              let data = try? JSONEncoder().encode(snap) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// Apply a freshly received snapshot: store it, publish to the glance, refresh the complication.
    private func apply(_ snap: WatchScoreSnapshot) {
        persist(snap)
        snapshot = snap
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Decode a WatchScoreSnapshot out of a WatchConnectivity payload. The phone encodes the Codable
    /// snapshot to Data under "snapshot"; we tolerate a missing/garbled payload by simply ignoring it.
    private nonisolated func decode(from payload: [String: Any]) -> WatchScoreSnapshot? {
        guard let data = payload[WatchScoreSnapshot.wcContextKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchScoreSnapshot.self, from: data)
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        if let snap = decode(from: session.receivedApplicationContext) {
            Task { @MainActor in apply(snap) }
        }
        Task { @MainActor in requestLatestFromPhone() }
    }

    /// The phone calls `updateApplicationContext` whenever its dashboard refreshes. Latest-state only, so
    /// we always have the freshest scores without a backlog of stale messages.
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let snap = decode(from: applicationContext) {
            Task { @MainActor in apply(snap) }
        }
    }

    // Required by the protocol on watchOS even though they are phone-side concerns. No-ops here.
    #if os(watchOS)
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in requestLatestFromPhone() }
    }
    #endif
}
