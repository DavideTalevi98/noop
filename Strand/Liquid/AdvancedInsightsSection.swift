import SwiftUI
import StrandAnalytics
import StrandDesign

// AdvancedInsightsSection.swift — Today cards for dual-window readiness, baseline shifts, and ANS charge.

struct AdvancedInsightsSection: View {
    let snapshot: AdvancedReadinessSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHead("ADVANCED INSIGHTS", trailing: "on-device")

            if let dual = snapshot.dual, dual.overall != .insufficient {
                insightCard(
                    title: "Trend readiness",
                    tint: tintForDual(dual.overall),
                    lines: dualLines(dual)
                )
            }

            if let line = snapshot.hrvShift?.summary, snapshot.hrvShift?.mostRecent != nil {
                insightCard(title: "HRV baseline shift", tint: StrandPalette.metricCyan, lines: [line])
            } else if let line = snapshot.rhrShift?.summary, snapshot.rhrShift?.mostRecent != nil {
                insightCard(title: "Resting HR baseline shift", tint: StrandPalette.metricRose, lines: [line])
            }

            if let ans = snapshot.ans {
                insightCard(
                    title: "Early-sleep ANS",
                    tint: tintForANS(ans.level),
                    lines: [ans.summary]
                )
            }
        }
    }

    // MARK: - Cards

    private func insightCard(title: String, tint: Color, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased()).font(StrandFont.overline).tracking(1.4)
                    .foregroundStyle(StrandPalette.textSecondary)
                Spacer()
                Circle().fill(tint).frame(width: 8, height: 8)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(LocalizedStringKey(line))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(StrandPalette.surfaceRaised)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(StrandPalette.hairline, lineWidth: 1))
        )
    }

    private func sectionHead(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title).font(StrandFont.overline).tracking(1.6)
                .foregroundStyle(StrandPalette.textSecondary)
            Spacer()
            Text(trailing).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Copy helpers

    private func dualLines(_ dual: DualWindowReadiness.Summary) -> [String] {
        var out: [String] = []
        if let h = dual.hrv, h.state != .withinNormal && h.state != .insufficient { out.append(h.summary) }
        if let r = dual.rhr, r.state != .withinNormal && r.state != .insufficient { out.append(r.summary) }
        if out.isEmpty, let h = dual.hrv { out.append(h.summary) }
        return out
    }

    private func tintForDual(_ state: DualWindowReadiness.State) -> Color {
        switch state {
        case .suppressed: return StrandPalette.statusCritical
        case .elevated: return StrandPalette.chargeColor
        case .withinNormal: return StrandPalette.accent
        case .insufficient: return StrandPalette.textTertiary
        }
    }

    private func tintForANS(_ level: ANSEarlySleepEngine.Level) -> Color {
        switch level {
        case .good: return StrandPalette.chargeColor
        case .ok: return StrandPalette.accent
        case .compromised: return StrandPalette.statusCritical
        case .insufficient: return StrandPalette.textTertiary
        }
    }
}
