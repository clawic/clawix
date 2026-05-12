import SwiftUI
import KeyboardShortcuts

/// Settings page that lists every customizable keyboard shortcut in the
/// app. Each row wraps `KeyboardShortcuts.Recorder` so the user can pick
/// a new chord or clear the binding entirely. Currently exposes the
/// integrated terminal shortcuts; dictation shortcuts live on the
/// dictation page for now because they're paired with the recorder
/// state UI there.
struct ShortcutsSettingsPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Keyboard Shortcuts")

            SectionLabel(title: "Terminal")
            SettingsCard {
                ShortcutSettingRow(
                    title: "Toggle terminal panel",
                    detail: "Show or hide the integrated terminal at the bottom of the chat.",
                    name: .terminalToggle
                )
                CardDivider()
                ShortcutSettingRow(
                    title: "New terminal tab",
                    detail: "Open a new tab in the integrated terminal.",
                    name: .terminalNewTab
                )
                CardDivider()
                ShortcutSettingRow(
                    title: "Close terminal tab",
                    detail: "Close the active terminal tab.",
                    name: .terminalCloseTab
                )
                CardDivider()
                ShortcutSettingRow(
                    title: "Next terminal tab",
                    detail: "Switch to the next tab in the terminal.",
                    name: .terminalNextTab
                )
                CardDivider()
                ShortcutSettingRow(
                    title: "Previous terminal tab",
                    detail: "Switch to the previous tab in the terminal.",
                    name: .terminalPreviousTab
                )
                CardDivider()
                ShortcutSettingRow(
                    title: "Split pane right",
                    detail: "Split the active pane horizontally into two side-by-side panes.",
                    name: .terminalSplitVertical
                )
                CardDivider()
                ShortcutSettingRow(
                    title: "Split pane down",
                    detail: "Split the active pane vertically into two stacked panes.",
                    name: .terminalSplitHorizontal
                )
            }
        }
    }
}

private struct ShortcutSettingRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let name: KeyboardShortcuts.Name

    var body: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
                Text(detail)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            KeyboardShortcuts.Recorder(for: name)
        }
    }
}
