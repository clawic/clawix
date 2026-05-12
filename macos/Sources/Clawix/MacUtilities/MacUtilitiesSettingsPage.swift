import SwiftUI

struct MacUtilitiesSettingsPage: View {
    @ObservedObject private var controller = MacUtilitiesController.shared
    @State private var pendingAction: MacUtilityActionID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Mac Utilities",
                subtitle: "Run common macOS actions from Clawix and the menu bar."
            )

            ForEach(MacUtilityGroup.allCases) { group in
                SectionLabel(title: LocalizedStringKey(group.title))
                SettingsCard {
                    let actions = MacUtilityActionID.actions(in: group)
                    ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                        MacUtilityActionRow(
                            action: action,
                            keepAwakeEnabled: controller.keepAwakeEnabled,
                            onRun: { request(action) }
                        )
                        if index < actions.count - 1 {
                            CardDivider()
                        }
                    }
                }
            }
        }
        .alert(
            pendingAction?.title ?? "Confirm Action",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            presenting: pendingAction
        ) { action in
            Button(action.title, role: .destructive) {
                controller.perform(action)
                pendingAction = nil
            }
            Button("Cancel", role: .cancel) {
                pendingAction = nil
            }
        } message: { action in
            Text(confirmationMessage(for: action))
        }
    }

    private func request(_ action: MacUtilityActionID) {
        if action.requiresConfirmation {
            pendingAction = action
        } else {
            controller.perform(action)
        }
    }

    private func confirmationMessage(for action: MacUtilityActionID) -> String {
        switch action {
        case .clearClipboard:
            return "This removes all current clipboard contents."
        default:
            return "Run this macOS action now?"
        }
    }
}

private struct MacUtilityActionRow: View {
    let action: MacUtilityActionID
    let keepAwakeEnabled: Bool
    let onRun: () -> Void

    var body: some View {
        SettingsRow {
            HStack(spacing: 10) {
                LucideIcon.auto(action.systemImage, size: 14)
                    .foregroundColor(Palette.textSecondary)
                    .frame(width: 18)
                RowLabel(title: LocalizedStringKey(action.title), detail: LocalizedStringKey(detailText))
            }
        } trailing: {
            Button(actionButtonTitle, action: onRun)
                .buttonStyle(.borderless)
                .controlSize(.small)
        }
    }

    private var detailText: String {
        if action == .toggleKeepAwake {
            return keepAwakeEnabled ? "Currently preventing idle sleep." : action.detail
        }
        return action.detail
    }

    private var actionButtonTitle: String {
        switch action {
        case .openFinder,
             .openTerminal,
             .openShortcuts,
             .openPasswords,
             .openAirDrop,
             .openVPNSettings,
             .openPrivateRelaySettings,
             .openHideMyEmailSettings,
             .openKeyboardSettings,
             .openDisplaySettings,
             .openDesktopDockSettings,
             .openNotificationsSettings,
             .openSoundSettings,
             .openPrivacySettings:
            return "Open"
        case .toggleKeepAwake:
            return keepAwakeEnabled ? "Turn Off" : "Turn On"
        default:
            return "Run"
        }
    }
}
