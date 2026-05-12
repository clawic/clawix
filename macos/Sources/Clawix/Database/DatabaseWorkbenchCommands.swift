import SwiftUI

struct DatabaseWorkbenchCommands: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var prefs = DatabaseWorkbenchPreferences.shared

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
        appState.currentRoute = .databaseHome
        ToastCenter.shared.show("Database workbench opened")
    }

    private func openSettings() {
        appState.settingsCategory = .databaseWorkbench
        appState.currentRoute = .settings
        ToastCenter.shared.show("Database workbench settings opened")
    }
}

struct DatabaseWorkbenchMenuBarSection: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var prefs = DatabaseWorkbenchPreferences.shared
    let openMainWindow: () -> Void

    var body: some View {
        Section {
            Menu {
                Button {
                    appState.currentRoute = .databaseHome
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
}
