import SwiftUI
import AppKit

// Modal sheet for creating or editing a Project. A project = title +
// absolute folder path on disk. Used both from the sidebar ("+" button)
// and from project rows (edit on hover).

struct ProjectEditorSheet: View {
    let context: ProjectEditorContext
    let onClose: () -> Void

    @EnvironmentObject var appState: AppState
    @State private var name: String = ""
    @State private var path: String = ""
    @FocusState private var nameFocused: Bool
    @FocusState private var pathFocused: Bool

    private var isEditing: Bool { context.project != nil }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !path.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(isEditing
                     ? String(localized: "Edit project", bundle: AppLocale.bundle, locale: AppLocale.current)
                     : String(localized: "New project", bundle: AppLocale.bundle, locale: AppLocale.current))
                    .font(BodyFont.system(size: 20, weight: .medium))
                    .foregroundColor(Color(white: 0.97))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(BodyFont.system(size: 12, weight: .medium))
                        .foregroundColor(Color(white: 0.65))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 14) {
                fieldGroup("Name") {
                    TextField("My project", text: $name)
                        .textFieldStyle(.plain)
                        .font(BodyFont.system(size: 13.5))
                        .foregroundColor(Color(white: 0.94))
                        .focused($nameFocused)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(textFieldBackground)
                }

                fieldGroup("Folder") {
                    HStack(spacing: 8) {
                        TextField("/Users/me/code/foo", text: $path)
                            .textFieldStyle(.plain)
                            .font(BodyFont.system(size: 13))
                            .foregroundColor(Color(white: 0.92))
                            .focused($pathFocused)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(textFieldBackground)
                        Button(action: chooseFolder) {
                            Text("Choose…")
                        }
                        .buttonStyle(SheetCancelButtonStyle())
                    }
                }

                if !path.isEmpty && !FileManager.default.fileExists(atPath: expandedPath) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(BodyFont.system(size: 11))
                        Text("This folder doesn’t exist on disk")
                            .font(BodyFont.system(size: 11.5))
                    }
                    .foregroundColor(Color(red: 0.95, green: 0.6, blue: 0.35))
                } else if !path.isEmpty && FileManager.default.fileExists(atPath: expandedPath) {
                    let projectId = context.project?.id
                    let pathMatchCount = appState.chats.filter { chat in
                        if let pid = projectId, chat.projectId == pid { return false }
                        guard chat.projectId == nil,
                              let cwd = chat.cwd, !cwd.isEmpty else { return false }
                        let normalizedCwd = (cwd as NSString).expandingTildeInPath
                        return normalizedCwd == expandedPath
                            || normalizedCwd.hasPrefix(expandedPath + "/")
                    }.count
                    if pathMatchCount > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                                .font(BodyFont.system(size: 11))
                            Text(L10n.chatsAutoGroupedByPath(pathMatchCount))
                                .font(BodyFont.system(size: 11.5))
                        }
                        .foregroundColor(Color(white: 0.50))
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)

            HStack(spacing: 8) {
                if isEditing, let project = context.project {
                    Button(action: {
                        appState.deleteProject(project.id)
                        onClose()
                    }) {
                        Text(String(localized: "Delete", bundle: AppLocale.bundle, locale: AppLocale.current))
                    }
                    .buttonStyle(SheetDestructiveButtonStyle())
                }
                Spacer()
                Button("Cancel") { onClose() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(SheetCancelButtonStyle())
                Button(isEditing
                       ? String(localized: "Save", bundle: AppLocale.bundle, locale: AppLocale.current)
                       : String(localized: "Create", bundle: AppLocale.bundle, locale: AppLocale.current)) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                    .buttonStyle(SheetPrimaryButtonStyle(enabled: canSave))
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 18)
        }
        .frame(width: 460)
        .sheetStandardBackground()
        .onAppear {
            if let project = context.project {
                name = project.name
                path = project.path
            }
            // Editing an existing project: cursor goes to the path field
            // (the name is the field most likely already correct, the
            // path is the one users actually re-pick). Creating a new
            // project: cursor in the name field, that's the first thing
            // the user types.
            DispatchQueue.main.async {
                if isEditing {
                    pathFocused = true
                } else {
                    nameFocused = true
                }
            }
        }
    }

    private var expandedPath: String {
        (path.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if let original = context.project {
            var updated = original
            updated.name = trimmedName
            updated.path = trimmedPath
            appState.updateProject(updated)
        } else {
            appState.createProject(name: trimmedName, path: trimmedPath)
        }
        onClose()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Select", bundle: AppLocale.bundle, locale: AppLocale.current)
        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
        }
    }

    private func fieldGroup<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(BodyFont.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(Color(white: 0.50))
            content()
        }
    }

    private var textFieldBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(white: 0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            )
    }
}
