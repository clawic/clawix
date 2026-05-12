import SwiftUI

struct DatabaseWorkbenchView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var prefs = DatabaseWorkbenchPreferences.shared
    @ObservedObject private var profiles = DatabaseConnectionProfileStore.shared
    @ObservedObject private var session = DatabaseWorkbenchSessionStore.shared
    @ObservedObject private var operations = DatabaseWorkbenchOperationStore.shared

    private var selectedProfile: DatabaseConnectionProfile? {
        profiles.profiles.first { $0.id == session.selectedProfileID } ?? profiles.profiles.first
    }

    var body: some View {
        VStack(spacing: 0) {
            workbenchToolbar
            Divider().background(Color.white.opacity(0.07))
            HStack(spacing: 0) {
                if prefs.showItemList {
                    objectSidebar
                        .frame(width: 260)
                    Divider().background(Color.white.opacity(0.07))
                }
                queryColumn
                if prefs.showRowDetail {
                    Divider().background(Color.white.opacity(0.07))
                    rowDetailColumn
                        .frame(width: 260)
                }
            }
        }
        .background(Palette.background)
        .onAppear {
            if session.selectedProfileID == nil {
                session.selectedProfileID = profiles.profiles.first?.id
            }
        }
    }

    private var workbenchToolbar: some View {
        HStack(spacing: 10) {
            Text("Database Workbench")
                .font(BodyFont.system(size: 14, wght: 700))
                .foregroundColor(Palette.textPrimary)

            Picker("", selection: profileSelection) {
                if profiles.profiles.isEmpty {
                    Text("No profile").tag(Optional<UUID>.none)
                } else {
                    ForEach(profiles.profiles) { profile in
                        Text(profile.displayName).tag(Optional(profile.id))
                    }
                }
            }
            .labelsHidden()
            .frame(width: 220)

            Button("Run current") {
                runDry()
            }
            .buttonStyle(.borderedProminent)

            Button("Format") {
                session.formatActiveSQL()
                ToastCenter.shared.show("SQL formatted")
            }
            .buttonStyle(.bordered)

            Button("Save draft") {
                _ = session.saveDraft()
                ToastCenter.shared.show("Query draft saved")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("Settings") {
                appState.settingsCategory = .databaseWorkbench
                appState.currentRoute = .settings
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var objectSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Profiles")
                .font(BodyFont.system(size: 12, wght: 700))
                .foregroundColor(Palette.textPrimary)
            if profiles.profiles.isEmpty {
                Text("Create a profile in Settings before connecting.")
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
            } else {
                ForEach(profiles.profiles) { profile in
                    Button {
                        session.selectedProfileID = profile.id
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(profile.displayName)
                                .font(BodyFont.system(size: 12, wght: 600))
                                .foregroundColor(Palette.textPrimary)
                                .lineLimit(1)
                            Text(profileDetail(profile))
                                .font(BodyFont.system(size: 11))
                                .foregroundColor(Palette.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().background(Color.white.opacity(0.07))

            Text("Operations")
                .font(BodyFont.system(size: 12, wght: 700))
                .foregroundColor(Palette.textPrimary)
            ForEach(DatabaseWorkbenchOperationKind.allCases.prefix(6)) { kind in
                Button {
                    prepareOperation(kind)
                } label: {
                    Text(kind.label)
                        .font(BodyFont.system(size: 12))
                        .foregroundColor(Palette.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            Divider().background(Color.white.opacity(0.07))

            Text("Query drafts")
                .font(BodyFont.system(size: 12, wght: 700))
                .foregroundColor(Palette.textPrimary)
            if session.drafts.isEmpty {
                Text("Saved drafts appear here.")
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
            } else {
                ForEach(session.drafts.prefix(8)) { draft in
                    Button {
                        session.loadDraft(draft)
                    } label: {
                        Text(draft.displayTitle)
                            .font(BodyFont.system(size: 12))
                            .foregroundColor(Palette.textPrimary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
        .padding(14)
        .background(Palette.cardFill)
    }

    private var queryColumn: some View {
        VStack(spacing: 0) {
            TextEditor(text: $session.activeSQL)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Palette.textPrimary)
                .scrollContentBackground(.hidden)
                .background(Palette.background)
                .frame(minHeight: 220)

            Divider().background(Color.white.opacity(0.07))

            if prefs.showConsoleLog {
                consolePanel
                    .frame(height: 110)
                Divider().background(Color.white.opacity(0.07))
            }

            resultPanel
        }
    }

    private var consolePanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Console")
                    .font(BodyFont.system(size: 12, wght: 700))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Button("Clear") {
                    session.clearConsole()
                }
                .buttonStyle(.bordered)
            }
            if session.console.isEmpty {
                Text("Dry-run messages and future execution logs appear here.")
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
            } else {
                ForEach(Array(session.console.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .background(Palette.cardFill)
    }

    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Results")
                .font(BodyFont.system(size: 12, wght: 700))
                .foregroundColor(Palette.textPrimary)
            HStack(spacing: 0) {
                resultCell("status")
                resultCell("statement")
                resultCell("profile")
            }
            HStack(spacing: 0) {
                resultCell("dry-run")
                resultCell(DatabaseWorkbenchSessionStore.classify(session.activeSQL).rawValue)
                resultCell(selectedProfile?.displayName ?? "No profile")
            }
            Spacer()
        }
        .padding(12)
        .background(Palette.background)
    }

    private func resultCell(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(Palette.textPrimary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(Palette.cardFill)
            .overlay(Rectangle().stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    private var rowDetailColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Row Detail")
                .font(BodyFont.system(size: 12, wght: 700))
                .foregroundColor(Palette.textPrimary)
            Text("Select a result row after an approved runner returns data.")
                .font(BodyFont.system(size: 12))
                .foregroundColor(Palette.textSecondary)
            Divider().background(Color.white.opacity(0.07))
            Text("History")
                .font(BodyFont.system(size: 12, wght: 700))
                .foregroundColor(Palette.textPrimary)
            ForEach(session.history.prefix(8)) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.outcome.rawValue)
                        .font(BodyFont.system(size: 11, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                    Text(entry.statementPreview)
                        .font(BodyFont.system(size: 11))
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(2)
                }
            }
            if !operations.records.isEmpty {
                Divider().background(Color.white.opacity(0.07))
                Text("Operations")
                    .font(BodyFont.system(size: 12, wght: 700))
                    .foregroundColor(Palette.textPrimary)
                ForEach(operations.records.prefix(6)) { record in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.kind.label)
                            .font(BodyFont.system(size: 11, wght: 600))
                            .foregroundColor(Palette.textPrimary)
                        Text(record.message)
                            .font(BodyFont.system(size: 11))
                            .foregroundColor(Palette.textSecondary)
                            .lineLimit(2)
                    }
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Palette.cardFill)
    }

    private var profileSelection: Binding<UUID?> {
        Binding(
            get: { session.selectedProfileID ?? profiles.profiles.first?.id },
            set: { session.selectedProfileID = $0 }
        )
    }

    private func runDry() {
        let plan = session.dryRun(profile: selectedProfile, preferences: prefs)
        switch plan.status {
        case .readyForFileProfile:
            ToastCenter.shared.show(plan.message)
        case .externalPending:
            ToastCenter.shared.show(plan.message, icon: .warning)
        case .blocked:
            ToastCenter.shared.show(plan.message, icon: .error)
        }
    }

    private func prepareOperation(_ kind: DatabaseWorkbenchOperationKind) {
        let plan = operations.plan(kind, profile: selectedProfile)
        session.appendOperationMessage(plan.message)
        switch plan.status {
        case .localReady:
            ToastCenter.shared.show(plan.message)
        case .externalPending:
            ToastCenter.shared.show(plan.message, icon: .warning)
        case .blocked:
            ToastCenter.shared.show(plan.message, icon: .error)
        }
    }

    private func profileDetail(_ profile: DatabaseConnectionProfile) -> String {
        let engine = profile.engine?.label ?? profile.engineId
        let target = profile.hostOrPath.isEmpty ? "No target" : profile.hostOrPath
        return "\(engine) · \(target)"
    }
}
