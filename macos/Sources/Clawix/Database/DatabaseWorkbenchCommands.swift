import SwiftUI

struct DatabaseWorkbenchCommands: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var prefs = DatabaseWorkbenchPreferences.shared
    @ObservedObject private var profiles = DatabaseConnectionProfileStore.shared
    @ObservedObject private var session = DatabaseWorkbenchSessionStore.shared
    @ObservedObject private var operations = DatabaseWorkbenchOperationStore.shared

    var body: some View {
        Button("Open Database Workbench") {
            openWorkbench()
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])

        Button("Database Workbench Settings…") {
            openSettings()
        }
        .keyboardShortcut(",", modifiers: [.command, .shift])

        Divider()

        Button("Create Connection Profile") {
            let profile = DatabaseConnectionProfile.draft()
            profiles.upsert(profile)
            openSettings()
            ToastCenter.shared.show("Connection profile created")
        }

        Menu("Connection Profiles") {
            if profiles.profiles.isEmpty {
                Text("No profiles")
            } else {
                ForEach(profiles.profiles) { profile in
                    Button("Dry Run \(profile.displayName)") {
                        dryRun(profile)
                    }
                }
            }
        }

        Divider()

        Button("New Query Draft") {
            session.newDraft()
            openWorkbench()
            ToastCenter.shared.show("Query draft created")
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])

        Button("Save Query Draft") {
            _ = session.saveDraft()
            ToastCenter.shared.show("Query draft saved")
        }
        .keyboardShortcut("s", modifiers: [.command, .shift])

        Button("Format Current Query") {
            session.formatActiveSQL()
            ToastCenter.shared.show("SQL formatted")
        }

        Button("Dry Run Current Query") {
            dryRunCurrentQuery()
        }
        .keyboardShortcut(.return, modifiers: [.command])

        Menu("Operations") {
            ForEach(DatabaseWorkbenchOperationKind.allCases) { kind in
                Button("Prepare \(kind.label)") {
                    prepareOperation(kind)
                }
            }
        }

        Divider()

        Button(prefs.safeMode == .silent ? "Enable Write Confirmations" : "Disable Write Confirmations") {
            prefs.toggleSafeMode()
            ToastCenter.shared.show(prefs.safeMode == .silent ? "Write confirmations disabled" : "Write confirmations enabled")
        }

        Toggle("Show Item List", isOn: $prefs.showItemList)
        Toggle("Show Console Log", isOn: $prefs.showConsoleLog)
        Toggle("Show Row Detail", isOn: $prefs.showRowDetail)

        Divider()

        Toggle("Auto-save Queries", isOn: $prefs.autoSaveQueries)
        Toggle("Uppercase Keywords", isOn: $prefs.uppercaseKeywords)
        Toggle("Insert Matching Pairs", isOn: $prefs.insertClosingPairs)
        Toggle("Keep Connections Alive", isOn: $prefs.keepConnectionAlive)

        Divider()

        Menu("Default Encoding") {
            ForEach(DatabaseWorkbenchPreferences.TextEncoding.allCases) { encoding in
                Button {
                    prefs.defaultEncoding = encoding
                } label: {
                    if prefs.defaultEncoding == encoding {
                        Label(encoding.label, systemImage: "checkmark")
                    } else {
                        Text(encoding.label)
                    }
                }
            }
        }

        Menu("Supported Engines") {
            ForEach(DatabaseWorkbenchPreferences.supportedEngines) { engine in
                Button(engine.label) {
                    ToastCenter.shared.show("\(engine.label) profile selected")
                }
            }
        }
    }

    private func openWorkbench() {
        appState.currentRoute = .databaseWorkbench
        ToastCenter.shared.show("Database workbench opened")
    }

    private func openSettings() {
        appState.settingsCategory = .databaseWorkbench
        appState.currentRoute = .settings
        ToastCenter.shared.show("Database workbench settings opened")
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

    private func dryRunCurrentQuery() {
        let profile = profiles.profiles.first { $0.id == session.selectedProfileID } ?? profiles.profiles.first
        let plan = session.dryRun(profile: profile, preferences: prefs)
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
        let profile = profiles.profiles.first { $0.id == session.selectedProfileID } ?? profiles.profiles.first
        let plan = operations.plan(kind, profile: profile)
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
}

struct DatabaseWorkbenchMenuBarSection: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var prefs = DatabaseWorkbenchPreferences.shared
    @ObservedObject private var profiles = DatabaseConnectionProfileStore.shared
    @ObservedObject private var session = DatabaseWorkbenchSessionStore.shared
    @ObservedObject private var operations = DatabaseWorkbenchOperationStore.shared
    let openMainWindow: () -> Void

    var body: some View {
        Section {
            Menu {
                Button {
                    appState.currentRoute = .databaseWorkbench
                    openMainWindow()
                } label: {
                    Label("Open Workbench", systemImage: "cylinder.split.1x2")
                }
                Button {
                    appState.settingsCategory = .databaseWorkbench
                    appState.currentRoute = .settings
                    openMainWindow()
                } label: {
                    Label("Settings…", systemImage: "gearshape")
                }
                Button {
                    profiles.upsert(.draft())
                    appState.settingsCategory = .databaseWorkbench
                    appState.currentRoute = .settings
                    openMainWindow()
                } label: {
                    Label("Create Connection Profile", systemImage: "plus")
                }

                Menu("Connection Profiles") {
                    if profiles.profiles.isEmpty {
                        Text("No profiles")
                    } else {
                        ForEach(profiles.profiles) { profile in
                            Button("Dry Run \(profile.displayName)") {
                                dryRun(profile)
                            }
                        }
                    }
                }

                Divider()

                Button {
                    session.newDraft()
                    appState.currentRoute = .databaseWorkbench
                    openMainWindow()
                } label: {
                    Label("New Query Draft", systemImage: "doc.badge.plus")
                }
                Button {
                    _ = session.saveDraft()
                } label: {
                    Label("Save Query Draft", systemImage: "square.and.arrow.down")
                }
                Button {
                    session.formatActiveSQL()
                } label: {
                    Label("Format Current Query", systemImage: "text.alignleft")
                }
                Button {
                    dryRunCurrentQuery()
                } label: {
                    Label("Dry Run Current Query", systemImage: "play")
                }

                Menu("Operations") {
                    ForEach(DatabaseWorkbenchOperationKind.allCases) { kind in
                        Button("Prepare \(kind.label)") {
                            prepareOperation(kind)
                        }
                    }
                }

                Divider()

                Button {
                    prefs.toggleSafeMode()
                } label: {
                    Label(
                        prefs.safeMode == .silent ? "Enable Write Confirmations" : "Disable Write Confirmations",
                        systemImage: prefs.safeMode == .silent ? "lock.open" : "lock"
                    )
                }

                Toggle("Item List", isOn: $prefs.showItemList)
                Toggle("Console Log", isOn: $prefs.showConsoleLog)
                Toggle("Row Detail", isOn: $prefs.showRowDetail)

                Divider()

                Menu("Encoding") {
                    ForEach(DatabaseWorkbenchPreferences.TextEncoding.allCases) { encoding in
                        Button {
                            prefs.defaultEncoding = encoding
                        } label: {
                            if prefs.defaultEncoding == encoding {
                                Label(encoding.label, systemImage: "checkmark")
                            } else {
                                Text(encoding.label)
                            }
                        }
                    }
                }
            } label: {
                Label("Database Workbench", systemImage: "cylinder.split.1x2")
            }
        } header: {
            Text("Database")
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

    private func dryRunCurrentQuery() {
        let profile = profiles.profiles.first { $0.id == session.selectedProfileID } ?? profiles.profiles.first
        let plan = session.dryRun(profile: profile, preferences: prefs)
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
        let profile = profiles.profiles.first { $0.id == session.selectedProfileID } ?? profiles.profiles.first
        let plan = operations.plan(kind, profile: profile)
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
}
