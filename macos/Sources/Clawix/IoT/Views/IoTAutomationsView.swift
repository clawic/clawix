import SwiftUI

/// Automations tab. List + enable / disable / run controls. Visual
/// authoring (block-based trigger / condition / action editor) lands
/// in Phase 4 once the trigger taxonomy stabilises; for Phase 3 the
/// agent and CLI own the create path (via `iot.automations.create`).
struct IoTAutomationsView: View {
    @EnvironmentObject private var manager: IoTManager
    @State private var inFlightId: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(manager.automations) { automation in
                    AutomationRow(
                        automation: automation,
                        isBusy: inFlightId == automation.id,
                        onToggle: { Task { await toggle(automation) } },
                        onRun: { Task { await run(automation) } },
                    )
                }
                if manager.automations.isEmpty {
                    Text(verbatim: "No automations yet.")
                        .font(BodyFont.system(size: 13))
                        .foregroundColor(Palette.textTertiary)
                        .padding(.top, 80)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .thinScrollers()
    }

    private func toggle(_ automation: AutomationRecord) async {
        inFlightId = automation.id
        defer { inFlightId = nil }
        try? await manager.setAutomationEnabled(automation, enabled: !automation.enabled)
    }

    private func run(_ automation: AutomationRecord) async {
        inFlightId = automation.id
        defer { inFlightId = nil }
        try? await manager.runAutomation(automation)
    }
}

private struct AutomationRow: View {
    let automation: AutomationRecord
    let isBusy: Bool
    var onToggle: () -> Void
    var onRun: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(automation.enabled ? Color.green.opacity(0.30) : Color.white.opacity(0.08))
                    .frame(width: 10, height: 10)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: automation.label)
                    .font(BodyFont.system(size: 13, weight: .medium))
                    .foregroundColor(Palette.textPrimary)
                Text(verbatim: triggerSummary)
                    .font(BodyFont.system(size: 10))
                    .foregroundColor(Palette.textTertiary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { automation.enabled }, set: { _ in onToggle() }))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Color.accentColor)
            Button(action: onRun) {
                HStack(spacing: 4) {
                    if isBusy {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.mini)
                            .tint(Palette.textPrimary)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                    }
                    Text(verbatim: "Run")
                }
                .font(BodyFont.system(size: 11, weight: .medium))
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    private var triggerSummary: String {
        let actions = automation.actions.count
        return "\(actions) action\(actions == 1 ? "" : "s") · trigger: \(automation.trigger.asDictionary?.keys.first ?? "manual")"
    }
}
