import SwiftUI
import StrandDesign

/// Pure tap routing for the Polar-style strap sync chrome — unit-testable without BLE.
enum StrapSyncAction: Equatable {
    case offline, pairing, ready, syncing

    static func resolve(connected: Bool, bonded: Bool, backfilling: Bool) -> StrapSyncAction {
        if backfilling { return .syncing }
        if !connected { return .offline }
        if !bonded { return .pairing }
        return .ready
    }

    /// Brief green completion ring when an offload session ends without a surfaced error.
    static func shouldFlashComplete(wasBackfilling: Bool, backfilling: Bool, lastSyncError: String?) -> Bool {
        wasBackfilling && !backfilling && lastSyncError == nil
    }
}

/// Compact strap-history sync affordance: a rotating blue arc while offloading, a full green ring that
/// fades on completion, tap kicks `syncNow` when ready, tap opens Devices when offline.
struct StrapSyncButton: View {
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: NavRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false
    @State private var wasBackfilling = false
    @State private var completeOpacity: Double = 0

    var size: CGFloat = 34
    /// Liquid Today uses a translucent disc; scaffold headers use the inset chrome.
    var liquidStyle: Bool = false

    private var action: StrapSyncAction {
        StrapSyncAction.resolve(connected: live.connected, bonded: live.bonded, backfilling: live.backfilling)
    }

    var body: some View {
        Group {
            if liquidStyle {
                Button(action: onTap, label: label).buttonStyle(LiquidPressStyle())
            } else {
                Button(action: onTap, label: label).buttonStyle(.plain)
            }
        }
        .disabled(action == .pairing || action == .syncing)
        .opacity(action == .offline ? 0.45 : 1)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .onAppear {
            wasBackfilling = live.backfilling
            updateSpin()
        }
        .onChange(of: spinning) { _ in updateSpin() }
        .onChange(of: reduceMotion) { _ in updateSpin() }
        .onChange(of: live.backfilling) { backfilling in
            if StrapSyncAction.shouldFlashComplete(wasBackfilling: wasBackfilling,
                                                   backfilling: backfilling,
                                                   lastSyncError: live.lastSyncError) {
                flashComplete()
            }
            wasBackfilling = backfilling
        }
    }

    private func label() -> some View {
        ZStack {
            chrome
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: liquidStyle ? 12 : 13, weight: .semibold))
                .foregroundStyle(centerIconColor)
            if completeOpacity > 0 {
                Circle()
                    .stroke(StrandPalette.statusPositive, lineWidth: 2.5)
                    .padding(2)
                    .opacity(completeOpacity)
            } else if spinning {
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(StrandPalette.metricCyan, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .padding(2)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(spin ? .linear(duration: 1.1).repeatForever(autoreverses: false) : nil, value: spin)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }

    private func flashComplete() {
        completeOpacity = 1
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeOut(duration: 0.5)) { completeOpacity = 0 }
        }
    }

    private func updateSpin() {
        spin = spinning && !reduceMotion
    }

    private var spinning: Bool { action == .syncing }

    private var centerIconColor: Color {
        if completeOpacity > 0 { return StrandPalette.statusPositive }
        switch action {
        case .syncing: return StrandPalette.metricCyan
        case .ready: return StrandPalette.accent
        default: return liquidStyle ? .white.opacity(0.85) : StrandPalette.textSecondary
        }
    }

    @ViewBuilder private var chrome: some View {
        if liquidStyle {
            Circle().fill(.white.opacity(0.16))
        } else {
            Circle().fill(StrandPalette.surfaceInset)
        }
    }

    private func onTap() {
        switch action {
        case .offline: router.openDevices()
        case .ready: model.ble.syncNow()
        case .pairing, .syncing: break
        }
    }

    private var accessibilityLabel: String {
        if completeOpacity > 0 { return String(localized: "Strap history synced") }
        switch action {
        case .offline: return String(localized: "No strap connected")
        case .pairing: return String(localized: "Pairing strap")
        case .ready: return String(localized: "Sync strap history")
        case .syncing: return String(localized: "Syncing strap history")
        }
    }

    private var accessibilityHint: String {
        switch action {
        case .offline: return String(localized: "Opens Devices to connect your strap.")
        case .pairing: return String(localized: "Finishing pairing. Sync becomes available when the strap is paired.")
        case .ready: return String(localized: "Pulls your strap's stored history immediately.")
        case .syncing: return String(localized: "A sync is already in progress.")
        }
    }
}
