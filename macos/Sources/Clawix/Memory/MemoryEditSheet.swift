import SwiftUI

/// Modal sheet for creating new memories or editing existing ones.
struct MemoryEditSheet: View {

    enum Mode {
        case create
        case edit(ClawJSMemoryClient.MemoryNote)
    }

    @ObservedObject var manager: MemoryManager
    let mode: Mode
    let onDismiss: () -> Void

    @State private var noteKind: String = "memory"
    @State private var memoryClass: String = "semantic"
    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var tags: String = ""
    @State private var scopeUser: String = ""
    @State private var scopeAgent: String = ""
    @State private var scopeProject: String = ""
    @State private var saving: Bool = false
    @State private var errorText: String? = nil

    private static let memoryClasses = ["semantic", "episodic", "procedural", "archival"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            CardDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if case .edit(let note) = mode, note.kind == "memory", note.lastEditedBy == nil, note.createdBy != "user" {
                        agentBanner
                    }
                    Group {
                        Text("Kind")
                            .font(BodyFont.system(size: 11, wght: 600))
                            .foregroundColor(.white.opacity(0.55))
                        Picker("Kind", selection: $noteKind) {
                            Text("Memory").tag("memory")
                            Text("Entity").tag("entity")
                        }
                        .pickerStyle(.segmented)
                    }
                    if noteKind == "memory" {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Memory class")
                                .font(BodyFont.system(size: 11, wght: 600))
                                .foregroundColor(.white.opacity(0.55))
                            Picker("Class", selection: $memoryClass) {
                                ForEach(Self.memoryClasses, id: \.self) { value in
                                    Text(value.capitalized).tag(value)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                    field("Title", binding: $title)
                    bodyEditor
                    field("Tags (comma separated)", binding: $tags, placeholder: "e.g. frontend, release")
                    HStack(spacing: 10) {
                        field("Scope user", binding: $scopeUser)
                        field("Scope agent", binding: $scopeAgent)
                        field("Scope project", binding: $scopeProject)
                    }
                    if let errorText {
                        Text(errorText)
                            .font(BodyFont.system(size: 11.5, wght: 500))
                            .foregroundColor(.red.opacity(0.8))
                    }
                }
                .padding(20)
            }
            CardDivider()
            footer
        }
        .frame(width: 560, height: 540)
        .background(Color(white: 0.10))
        .onAppear { populate() }
    }

    private var header: some View {
        HStack {
            Text(headerTitle)
                .font(BodyFont.system(size: 14, wght: 700))
                .foregroundColor(.white)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var agentBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow.opacity(0.85))
            Text("You are editing a memory written by an agent. The original body will be preserved as `originalBody` and the edit will be stamped with `lastEditedBy: user`.")
                .font(BodyFont.system(size: 11.5, wght: 400))
                .foregroundColor(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.yellow.opacity(0.10))
        )
    }

    private var headerTitle: String {
        switch mode {
        case .create: return "New memory"
        case .edit(let note): return "Edit · \(note.title)"
        }
    }

    private func field(_ label: String, binding: Binding<String>, placeholder: String = "") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(BodyFont.system(size: 11, wght: 600))
                .foregroundColor(.white.opacity(0.55))
            TextField(placeholder, text: binding)
                .textFieldStyle(.plain)
                .font(BodyFont.system(size: 13, wght: 400))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
        }
    }

    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Body (markdown)")
                .font(BodyFont.system(size: 11, wght: 600))
                .foregroundColor(.white.opacity(0.55))
            TextEditor(text: $bodyText)
                .font(BodyFont.system(size: 13, wght: 400))
                .foregroundColor(.white)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 140)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(action: onDismiss) {
                Text("Cancel")
                    .font(BodyFont.system(size: 12.5, wght: 600))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            Button(action: save) {
                Text(saving ? "Saving…" : "Save")
                    .font(BodyFont.system(size: 12.5, wght: 600))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(saving ? 0.5 : 0.95))
                    )
            }
            .buttonStyle(.plain)
            .disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func populate() {
        guard case .edit(let note) = mode else { return }
        noteKind = note.kind
        title = note.title
        bodyText = note.body
        tags = note.tags.joined(separator: ", ")
        scopeUser = note.scopeUser ?? ""
        scopeAgent = note.scopeAgent ?? ""
        scopeProject = note.scopeProject ?? ""
        if let mc = note.memoryClassRaw { memoryClass = mc }
    }

    private func save() {
        let parsedTags = tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            errorText = "Title is required."
            return
        }
        if trimmedBody.isEmpty {
            errorText = "Body is required."
            return
        }
        saving = true
        errorText = nil
        Task {
            defer { Task { @MainActor in saving = false } }
            do {
                switch mode {
                case .create:
                    let input = ClawJSMemoryClient.CreateNoteInput(
                        noteKind: noteKind,
                        title: trimmedTitle,
                        body: trimmedBody,
                        memoryClass: noteKind == "memory" ? memoryClass : nil,
                        type: nil,
                        tags: parsedTags.isEmpty ? nil : parsedTags,
                        scopeUser: scopeUser.isEmpty ? nil : scopeUser,
                        scopeAgent: scopeAgent.isEmpty ? nil : scopeAgent,
                        scopeProject: scopeProject.isEmpty ? nil : scopeProject
                    )
                    _ = try await manager.create(input)
                case .edit(let note):
                    let patch = ClawJSMemoryClient.UpdateNotePatch(
                        title: trimmedTitle,
                        body: trimmedBody,
                        tags: parsedTags,
                        scopeUser: scopeUser.isEmpty ? nil : scopeUser,
                        scopeAgent: scopeAgent.isEmpty ? nil : scopeAgent,
                        scopeProject: scopeProject.isEmpty ? nil : scopeProject,
                        memoryClass: noteKind == "memory" ? memoryClass : nil
                    )
                    _ = try await manager.update(id: note.id, patch: patch, editor: "user")
                }
                await MainActor.run { onDismiss() }
            } catch {
                await MainActor.run { errorText = error.localizedDescription }
            }
        }
    }
}
