import SwiftUI

struct DatabaseWorkbenchSettingsPage: View {
    @ObservedObject private var prefs = DatabaseWorkbenchPreferences.shared
    @ObservedObject private var profiles = DatabaseConnectionProfileStore.shared
    @State private var editedProfile: DatabaseConnectionProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Database Workbench",
                subtitle: "Connection, query editor, table browser, import/export, and safety defaults."
            )

            SectionLabel(title: "Connection profiles")
            SettingsCard {
                if profiles.profiles.isEmpty {
                    SettingsRow {
                        RowLabel(
                            title: "No profiles yet",
                            detail: "Create local connection profiles for engines, SSH, SSL, bootstrap commands, and options."
                        )
                    } trailing: {
                        Button("Add profile") {
                            editedProfile = .draft()
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    ForEach(Array(profiles.profiles.enumerated()), id: \.element.id) { index, profile in
                        ConnectionProfileRow(
                            profile: profile,
                            onEdit: { editedProfile = profile },
                            onDuplicate: { profiles.duplicate(id: profile.id) },
                            onTest: { dryRun(profile) },
                            onDelete: { profiles.delete(id: profile.id) }
                        )
                        if index < profiles.profiles.count - 1 {
                            CardDivider()
                        }
                    }
                    CardDivider()
                    SettingsRow {
                        RowLabel(title: "Add another profile", detail: "Profiles store connection metadata only.")
                    } trailing: {
                        Button("Add profile") {
                            editedProfile = .draft()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

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
        .sheet(item: $editedProfile) { profile in
            DatabaseConnectionProfileEditorSheet(
                profile: profile,
                onCancel: { editedProfile = nil },
                onSave: { saved in
                    profiles.upsert(saved)
                    editedProfile = nil
                    ToastCenter.shared.show("Connection profile saved")
                },
                onTest: { draft in
                    dryRun(draft)
                }
            )
            .frame(width: 620, height: 760)
        }
    }

    private func dryRun(_ profile: DatabaseConnectionProfile) {
        let result = profiles.dryRun(profile)
        switch result.status {
        case .passed:
            ToastCenter.shared.show(result.message)
        case .externalPending:
            ToastCenter.shared.show("EXTERNAL PENDING: \(result.message)", icon: .warning)
        case .failed:
            ToastCenter.shared.show(result.message, icon: .error)
        }
    }
}

private struct ConnectionProfileRow: View {
    let profile: DatabaseConnectionProfile
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onTest: () -> Void
    let onDelete: () -> Void

    @State private var confirmingDelete = false

    var body: some View {
        SettingsRow {
            RowLabel(title: LocalizedStringKey(profile.displayName), detail: LocalizedStringKey(detail))
        } trailing: {
            HStack(spacing: 8) {
                Button("Test", action: onTest)
                    .buttonStyle(.bordered)
                Button("Duplicate", action: onDuplicate)
                    .buttonStyle(.bordered)
                Button("Edit", action: onEdit)
                    .buttonStyle(.bordered)
                Button("Remove") {
                    confirmingDelete = true
                }
                .buttonStyle(.bordered)
            }
        }
        .confirmationDialog(
            "Remove connection profile?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the local profile metadata from this Mac.")
        }
    }

    private var detail: String {
        let engine = profile.engine?.label ?? profile.engineId
        let target = profile.hostOrPath.isEmpty ? "No target" : profile.hostOrPath
        let port = profile.port.map { ":\($0)" } ?? ""
        let tunnel = profile.sshEnabled ? " · SSH" : ""
        return "\(engine) · \(target)\(port) · \(profile.tag)\(tunnel)"
    }
}

private struct DatabaseConnectionProfileEditorSheet: View {
    @State private var draft: DatabaseConnectionProfile

    let onCancel: () -> Void
    let onSave: (DatabaseConnectionProfile) -> Void
    let onTest: (DatabaseConnectionProfile) -> Void

    init(
        profile: DatabaseConnectionProfile,
        onCancel: @escaping () -> Void,
        onSave: @escaping (DatabaseConnectionProfile) -> Void,
        onTest: @escaping (DatabaseConnectionProfile) -> Void
    ) {
        _draft = State(initialValue: profile)
        self.onCancel = onCancel
        self.onSave = onSave
        self.onTest = onTest
    }

    private var engine: DatabaseWorkbenchEngine? {
        DatabaseWorkbenchPreferences.supportedEngines.first { $0.id == draft.engineId }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connection profile")
                        .font(BodyFont.system(size: 18, wght: 700))
                        .foregroundColor(Palette.textPrimary)
                    Text("Save metadata for a database workspace. Secrets stay outside this profile.")
                        .font(BodyFont.system(size: 12))
                        .foregroundColor(Palette.textSecondary)
                }
                Spacer()
            }
            .padding(20)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SettingsCard {
                        DropdownRow(
                            title: "Engine",
                            detail: "Connection type for this profile.",
                            options: DatabaseWorkbenchPreferences.supportedEngines.map { ($0.id, $0.label) },
                            selection: engineBinding,
                            minWidth: 220
                        )
                        CardDivider()
                        TextFieldRow(title: "Name", detail: "Local label shown in Clawix.", text: $draft.name)
                        CardDivider()
                        TextFieldRow(title: "Group", detail: "Optional grouping label.", text: $draft.groupName)
                        CardDivider()
                        TextFieldRow(title: "Tag", detail: "Short environment label.", text: $draft.tag)
                    }

                    SettingsCard {
                        TextFieldRow(
                            title: engine?.supportsFileOpen == true ? "File path" : "Host or socket",
                            detail: engine?.supportsFileOpen == true ? "Local database file path." : "Server host, IP, or socket.",
                            text: $draft.hostOrPath
                        )
                        if engine?.supportsFileOpen != true {
                            CardDivider()
                            NumberRow(title: "Port", detail: "Server port.", value: portBinding, range: 1...65_535, suffix: "")
                        }
                        CardDivider()
                        TextFieldRow(title: "User", detail: "Username for the connection.", text: $draft.username)
                        CardDivider()
                        TextFieldRow(title: "Database", detail: "Database, schema, or catalog name.", text: $draft.databaseName)
                        CardDivider()
                        DropdownRow(
                            title: "Password",
                            detail: "How Clawix should request or resolve secret material.",
                            options: DatabaseConnectionAuthStorage.allCases.map { ($0, $0.label) },
                            selection: $draft.authStorage,
                            minWidth: 180
                        )
                    }

                    SettingsCard {
                        DropdownRow(
                            title: "SSL mode",
                            detail: "TLS behavior for engines that support it.",
                            options: DatabaseConnectionSSLMode.allCases.map { ($0, $0.label) },
                            selection: $draft.sslMode,
                            minWidth: 170
                        )
                        CardDivider()
                        DropdownRow(
                            title: "Negotiation",
                            detail: "Protocol negotiation mode.",
                            options: DatabaseConnectionNegotiation.allCases.map { ($0, $0.label) },
                            selection: $draft.negotiation,
                            minWidth: 170
                        )
                        CardDivider()
                        TextFieldRow(title: "SSL key", detail: "Optional local key file path.", text: $draft.sslKeyPath)
                        CardDivider()
                        TextFieldRow(title: "SSL certificate", detail: "Optional client certificate path.", text: $draft.sslCertificatePath)
                        CardDivider()
                        TextFieldRow(title: "CA certificate", detail: "Optional CA certificate path.", text: $draft.sslCAPath)
                    }

                    SettingsCard {
                        ToggleRow(title: "Over SSH", detail: "Tunnel the database connection through SSH.", isOn: $draft.sshEnabled)
                        CardDivider()
                        DropdownRow(
                            title: "SSH version",
                            detail: "SSH client compatibility mode.",
                            options: DatabaseConnectionSSHVersion.allCases.map { ($0, $0.label) },
                            selection: $draft.sshVersion,
                            minWidth: 170
                        )
                        CardDivider()
                        TextFieldRow(title: "SSH host", detail: "Jump host for the tunnel.", text: $draft.sshHost)
                        CardDivider()
                        NumberRow(title: "SSH port", detail: "Jump host port.", value: $draft.sshPort, range: 1...65_535, suffix: "")
                        CardDivider()
                        TextFieldRow(title: "SSH user", detail: "SSH username.", text: $draft.sshUsername)
                        CardDivider()
                        DropdownRow(
                            title: "SSH password",
                            detail: "How Clawix should request or resolve SSH secret material.",
                            options: DatabaseConnectionAuthStorage.allCases.map { ($0, $0.label) },
                            selection: $draft.sshAuthStorage,
                            minWidth: 180
                        )
                        CardDivider()
                        ToggleRow(title: "Use private key", detail: "Resolve SSH authentication through a private key file.", isOn: $draft.sshUsesPrivateKey)
                        CardDivider()
                        TextFieldRow(title: "Private key", detail: "Optional local private key path.", text: $draft.sshPrivateKeyPath)
                    }

                    SettingsCard {
                        ToggleRow(title: "Load system schemas", detail: "Include system schemas when browsing metadata.", isOn: $draft.loadSystemSchemas)
                        CardDivider()
                        ToggleRow(title: "Disable channel binding", detail: "Compatibility option for older servers and proxies.", isOn: $draft.disableChannelBinding)
                        CardDivider()
                        MultilineTextRow(title: "Bootstrap commands", detail: "SQL run after a future approved connection opens.", text: $draft.bootstrapSQL)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            Divider().background(Color.white.opacity(0.07))
            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Dry run") { onTest(draft) }
                Button("Save") { onSave(draft) }
                    .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .background(Palette.background)
    }

    private var engineBinding: Binding<String> {
        Binding(
            get: { draft.engineId },
            set: { id in
                draft.engineId = id
                guard let engine = DatabaseWorkbenchPreferences.supportedEngines.first(where: { $0.id == id }) else { return }
                draft.port = engine.defaultPort
                draft.sslMode = engine.supportsSSL ? .preferred : .disabled
                if engine.supportsFileOpen {
                    draft.sshEnabled = false
                    draft.hostOrPath = ""
                } else if draft.hostOrPath.isEmpty {
                    draft.hostOrPath = "127.0.0.1"
                }
            }
        )
    }

    private var portBinding: Binding<Int> {
        Binding(
            get: { draft.port ?? engine?.defaultPort ?? 1 },
            set: { draft.port = $0 }
        )
    }
}

private struct TextFieldRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    @Binding var text: String

    var body: some View {
        SettingsRow {
            RowLabel(title: title, detail: detail)
        } trailing: {
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
        }
    }
}

private struct MultilineTextRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RowLabel(title: title, detail: detail)
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 96)
                .scrollContentBackground(.hidden)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.045))
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
