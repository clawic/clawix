import SwiftUI

struct DatabaseWorkbenchSettingsPage: View {
    @ObservedObject private var prefs = DatabaseWorkbenchPreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Database Workbench",
                subtitle: "Connection, query editor, table browser, import/export, and safety defaults."
            )

            SectionLabel(title: "Workspace")
            SettingsCard {
                ToggleRow(
                    title: "Show item list",
                    detail: "Keep the object browser visible by default.",
                    isOn: $prefs.showItemList
                )
                CardDivider()
                ToggleRow(
                    title: "Show console log",
                    detail: "Keep the execution log visible below query results.",
                    isOn: $prefs.showConsoleLog
                )
                CardDivider()
                ToggleRow(
                    title: "Show row detail",
                    detail: "Keep the selected-row inspector visible on the right.",
                    isOn: $prefs.showRowDetail
                )
                CardDivider()
                DropdownRow(
                    title: "Command-T opens",
                    detail: "Default target for a new database tab.",
                    options: DatabaseWorkbenchPreferences.OpenTarget.allCases.map { ($0, $0.label) },
                    selection: $prefs.openTarget,
                    minWidth: 180
                )
            }

            SectionLabel(title: "SQL editor")
            SettingsCard {
                ToggleRow(
                    title: "Automatically save queries",
                    detail: "Persist query drafts while editing.",
                    isOn: $prefs.autoSaveQueries
                )
                CardDivider()
                ToggleRow(
                    title: "Uppercase keywords",
                    detail: "Normalize recognized SQL keywords while typing.",
                    isOn: $prefs.uppercaseKeywords
                )
                CardDivider()
                ToggleRow(
                    title: "Insert matching pairs",
                    detail: "Automatically close braces and quotes.",
                    isOn: $prefs.insertClosingPairs
                )
                CardDivider()
                ToggleRow(
                    title: "Indent with tabs",
                    detail: "Use tabs instead of spaces for indentation.",
                    isOn: $prefs.indentWithTabs
                )
                CardDivider()
                NumberRow(
                    title: "Indent width",
                    detail: "Number of spaces represented by one indentation step.",
                    value: $prefs.indentWidth,
                    range: 1...12,
                    suffix: "spaces"
                )
                CardDivider()
                DropdownRow(
                    title: "Complete key",
                    detail: "Key used to accept an autocomplete suggestion.",
                    options: DatabaseWorkbenchPreferences.CompleteKey.allCases.map { ($0, $0.label) },
                    selection: $prefs.completeKey,
                    minWidth: 160
                )
                CardDivider()
                NumberRow(
                    title: "Query timeout",
                    detail: "Maximum time a query may run before Clawix cancels it.",
                    value: $prefs.queryTimeoutSeconds,
                    range: 1...86_400,
                    suffix: "seconds"
                )
                CardDivider()
                DropdownRow(
                    title: "Default encoding",
                    detail: "Text encoding used when reading result data.",
                    options: DatabaseWorkbenchPreferences.TextEncoding.allCases.map { ($0, $0.label) },
                    selection: $prefs.defaultEncoding,
                    minWidth: 170
                )
            }

            SectionLabel(title: "Table data")
            SettingsCard {
                ToggleRow(
                    title: "Alternating row backgrounds",
                    detail: "Use alternating backgrounds in data grids.",
                    isOn: $prefs.alternatingRows
                )
                CardDivider()
                ToggleRow(
                    title: "Auto-hide table scrollers",
                    detail: "Hide table scrollers until a grid is active.",
                    isOn: $prefs.autoHideTableScrollers
                )
                CardDivider()
                NumberRow(
                    title: "Estimate row count above",
                    detail: "Use estimated counts for very large tables.",
                    value: $prefs.estimateCountThreshold,
                    range: 100...50_000_000,
                    suffix: "rows"
                )
            }

            SectionLabel(title: "CSV defaults")
            SettingsCard {
                DropdownRow(
                    title: "Delimiter",
                    detail: "Default separator for CSV import and export.",
                    options: DatabaseWorkbenchPreferences.CSVDelimiter.allCases.map { ($0, $0.label) },
                    selection: $prefs.csvDelimiter,
                    minWidth: 150
                )
                CardDivider()
                DropdownRow(
                    title: "Line break",
                    detail: "Default line ending for exported CSV files.",
                    options: DatabaseWorkbenchPreferences.CSVLineBreak.allCases.map { ($0, $0.label) },
                    selection: $prefs.csvLineBreak,
                    minWidth: 150
                )
            }

            SectionLabel(title: "Safety")
            SettingsCard {
                DropdownRow(
                    title: "Safe mode",
                    detail: "Default behavior before sending statements to a server.",
                    options: DatabaseWorkbenchPreferences.SafeMode.allCases.map { ($0, $0.label) },
                    selection: $prefs.safeMode,
                    minWidth: 190
                )
                CardDivider()
                ToggleRow(
                    title: "Keep connections alive",
                    detail: "Ping active servers periodically while a workspace is open.",
                    isOn: $prefs.keepConnectionAlive
                )
                CardDivider()
                ToggleRow(
                    title: "Require app passcode",
                    detail: "Lock database workspaces when Clawix starts or returns from the background.",
                    isOn: $prefs.passcodeEnabled
                )
            }

            SectionLabel(title: "Assistant")
            SettingsCard {
                ToggleRow(
                    title: "Assistant sidebar",
                    detail: "Enable a right-sidebar assistant for query drafting.",
                    isOn: $prefs.assistantSidebar
                )
            }

            SectionLabel(title: "Supported engines")
            SettingsCard {
                ForEach(Array(DatabaseWorkbenchPreferences.supportedEngines.enumerated()), id: \.element.id) { index, engine in
                    EngineRow(engine: engine)
                    if index < DatabaseWorkbenchPreferences.supportedEngines.count - 1 {
                        CardDivider()
                    }
                }
            }

            SectionLabel(title: "Defaults")
            SettingsCard {
                SettingsRow {
                    RowLabel(
                        title: "Restore defaults",
                        detail: "Reset all database workbench preferences on this Mac."
                    )
                } trailing: {
                    Button("Restore") {
                        prefs.reset()
                        ToastCenter.shared.show("Database workbench defaults restored")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

private struct NumberRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    @Binding var value: Int
    let range: ClosedRange<Int>
    let suffix: String

    var body: some View {
        SettingsRow {
            RowLabel(title: title, detail: detail)
        } trailing: {
            HStack(spacing: 8) {
                Stepper("", value: $value, in: range)
                    .labelsHidden()
                Text("\(value)")
                    .font(BodyFont.system(size: 12.5, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                    .monospacedDigit()
                    .frame(minWidth: 58, alignment: .trailing)
                Text(suffix)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
        }
    }
}

private struct EngineRow: View {
    let engine: DatabaseWorkbenchEngine

    var body: some View {
        SettingsRow {
            RowLabel(title: LocalizedStringKey(engine.label), detail: LocalizedStringKey(details))
        } trailing: {
            Text(portLabel)
                .font(BodyFont.system(size: 11.5, wght: 600))
                .foregroundColor(Palette.textSecondary)
                .monospacedDigit()
        }
    }

    private var details: String {
        var parts: [String] = []
        if engine.supportsSSH { parts.append("SSH") }
        if engine.supportsSSL { parts.append("SSL") }
        if engine.supportsFileOpen { parts.append("file open") }
        return parts.isEmpty ? "Direct connection" : parts.joined(separator: " · ")
    }

    private var portLabel: String {
        guard let port = engine.defaultPort else { return "No default port" }
        return "Port \(port)"
    }
}
