import SwiftUI

struct ProjectRenameSheet: View {
    let project: Project
    let onClose: () -> Void

    @EnvironmentObject var appState: AppState
    @State private var name: String = ""
    @FocusState private var fieldFocused: Bool

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != project.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Rename project")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color(white: 0.96))
                    Text("Keep it short and easy to recognise")
                        .font(.system(size: 13))
                        .foregroundColor(Color(white: 0.55))
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(white: 0.65))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 18)

            TextField("Project name", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(Color(white: 0.96))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(white: 0.16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.6)
                        )
                )
                .focused($fieldFocused)
                .padding(.horizontal, 24)
                .onSubmit { if canSave { save() } }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { onClose() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 22)
        }
        .frame(width: 460)
        .background(Color(white: 0.10))
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
