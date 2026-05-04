import SwiftUI

struct ProjectRenameSheet: View {
    let project: Project
    let onClose: () -> Void

    @EnvironmentObject var appState: AppState
    @State private var name: String = ""
    @FocusState private var fieldFocused: Bool

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Rename project")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Color(white: 0.97))
                    Text("Keep it short and recognizable")
                        .font(.system(size: 13))
                        .foregroundColor(Color(white: 0.55))
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
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

            TextField("Project name", text: $name)
                .sheetTextFieldStyle()
                .focused($fieldFocused)
                .padding(.horizontal, 22)
                .onSubmit { if canSave { save() } }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { onClose() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(SheetCancelButtonStyle())
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                    .buttonStyle(SheetPrimaryButtonStyle(enabled: canSave))
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 18)
        }
        .frame(width: 440)
        .sheetStandardBackground()
        .onAppear {
            name = project.name
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { fieldFocused = true }
        }
    }

    private func save() {
        appState.renameProject(id: project.id, newName: name)
        onClose()
    }
}
