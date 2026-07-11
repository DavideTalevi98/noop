import Foundation
import StrandAnalytics
import WhoopProtocol
import WhoopStore

// AdvancedReadiness.swift — loads ANS early-sleep, dual-window readiness, and baseline change-point
// results for the Today insight cards. Pure orchestration over Repository + StrandAnalytics engines.

struct AdvancedReadinessSnapshot: Equatable, Sendable {
    var dual: DualWindowReadiness.Summary?
    var hrvShift: BaselineChangePoint.Result?
    var rhrShift: BaselineChangePoint.Result?
    var ans: ANSEarlySleepEngine.Result?

    var hasContent: Bool {
        if let dual, dual.overall != .insufficient { return true }
        if hrvShift?.mostRecent != nil || rhrShift?.mostRecent != nil { return true }
        if ans != nil { return true }
        return false
    }
}

enum AdvancedReadinessLoader {

    /// Compute all advanced readiness reads for the Today surface. `todayKey` is the logical day
    /// being displayed (yyyy-MM-dd); pass nil to use the newest row in `repo.days`.
    @MainActor
    static func load(repo: Repository, todayKey: String?) async -> AdvancedReadinessSnapshot {
        let anchor = todayKey ?? repo.days.last?.day
        let dual = anchor.map { DualWindowReadiness.evaluate(days: repo.days, today: $0) }

        let hrvSeries = repo.days.map(\.avgHrv)
        let rhrSeries = repo.days.map { $0.restingHr.map(Double.init) }
        let hrvShift = BaselineChangePoint.detect(series: hrvSeries, cfg: Baselines.hrvCfg)
        let rhrShift = BaselineChangePoint.detect(series: rhrSeries, cfg: Baselines.restingHRCfg)

        let ans = await loadANS(repo: repo)
        return AdvancedReadinessSnapshot(dual: dual, hrvShift: hrvShift, rhrShift: rhrShift, ans: ans)
    }

    // MARK: - ANS early-sleep

    @MainActor
    private static func loadANS(repo: Repository) async -> ANSEarlySleepEngine.Result? {
        let sessions = await repo.allSleepSessions(days: 60)
        guard let last = sessions.last, last.endTs > last.effectiveStartTs else { return nil }
        guard let store = await repo.storeHandle() else { return nil }

        let deviceId = repo.deviceId
        let noopId = deviceId + "-noop"
        var history: [ANSEarlySleepEngine.NightSnapshot] = []
        for session in sessions.dropLast().suffix(ANSEarlySleepEngine.baselineNights) {
            guard let streams = await nightStreams(store: store, deviceId: deviceId, noopId: noopId,
                                                   session: session) else { continue }
            if let snap = ANSEarlySleepEngine.snapshot(sleepOnsetTs: session.effectiveStartTs,
                                                       hr: streams.hr, rr: streams.rr) {
                history.append(snap)
            }
        }
        guard let tonight = await nightStreams(store: store, deviceId: deviceId, noopId: noopId,
                                               session: last) else { return nil }
        return ANSEarlySleepEngine.evaluate(sleepOnsetTs: last.effectiveStartTs,
                                            hr: tonight.hr, rr: tonight.rr,
                                            history: history)
    }

    private static func nightStreams(store: WhoopStore, deviceId: String, noopId: String,
                                     session: CachedSleepSession) async -> (hr: [HRSample], rr: [RRInterval])? {
        let onset = session.effectiveStartTs
        let lo = onset
        let hi = onset + ANSEarlySleepEngine.onsetDelaySec + ANSEarlySleepEngine.windowDurationSec + 600

        var hr = (try? await store.hrSamples(deviceId: deviceId, from: lo, to: hi, limit: 200_000)) ?? []
        if hr.isEmpty {
            hr = (try? await store.hrSamples(deviceId: noopId, from: lo, to: hi, limit: 200_000)) ?? []
        }
        guard !hr.isEmpty else { return nil }

        var rr = (try? await store.rrIntervals(deviceId: deviceId, from: lo, to: hi, limit: 200_000)) ?? []
        if rr.isEmpty {
            rr = (try? await store.rrIntervals(deviceId: noopId, from: lo, to: hi, limit: 200_000)) ?? []
        }
        return (hr, rr)
    }
}
