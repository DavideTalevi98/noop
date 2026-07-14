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
}

/// Compact strap-history sync affordance: spins while offloading, tap kicks `syncNow` when ready,
/// tap opens Devices when offline. Mounted on primary tabs + Deep Timeline + macOS detail toolbar.
struct StrapSyncButton: View {
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: NavRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false

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
        .onAppear { updateSpin() }
        .onChange(of: spinning) { _ in updateSpin() }
        .onChange(of: reduceMotion) { _ in updateSpin() }
    }

    private func label() -> some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: liquidStyle ? 14 : 15, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background { chrome }
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(spin ? .linear(duration: 1.1).repeatForever(autoreverses: false) : .default, value: spin)
            .contentShape(Circle())
    }

    private func updateSpin() {
        spin = spinning && !reduceMotion
    }

    private var spinning: Bool { action == .syncing }

    private var foreground: Color {
        switch action {
        case .syncing: StrandPalette.metricCyan
        case .ready: StrandPalette.accent
        default: liquidStyle ? .white.opacity(0.85) : StrandPalette.textSecondary
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
        switch action {
        case .offline: String(localized: "No strap connected")
        case .pairing: String(localized: "Pairing strap")
        case .ready: String(localized: "Sync strap history")
        case .syncing: String(localized: "Syncing strap history")
        }
    }

    private var accessibilityHint: String {
        switch action {
        case .offline: String(localized: "Opens Devices to connect your strap.")
        case .pairing: String(localized: "Finishing pairing. Sync becomes available when the strap is paired.")
        case .ready: String(localized: "Pulls your strap's stored history immediately.")
        case .syncing: String(localized: "A sync is already in progress.")
        }
    }
}
