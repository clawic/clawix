import SwiftUI

/// Global ⌘⇧N quick-add sheet. Picks one of the curated collection
/// types (Task / Note / Goal / Project), then renders a minimal form.
/// Enter submits, Esc cancels.
struct DatabaseQuickAddOverlay: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var manager: DatabaseManager

    @State private var collectionName: String = "tasks"
    @State private var title: String = ""
    @State private var details: String = ""
    @State private var saving: Bool = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Quick add")
                    .font(BodyFont.system(size: 16, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
            }
            Picker("Type", selection: $collectionName) {
                ForEach(CuratedFilterRegistry.sidebarEntries, id: \.collection) { entry in
                    Text(entry.label).tag(entry.collection)
                }
                Text("Decision").tag("decisions")
                Text("Reminder").tag("reminders")
                Text("Inbox message").tag("inbox_messages")
            }
            .pickerStyle(.menu)

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(BodyFont.system(size: 14))
                .onSubmit { Task { await commit() } }

            TextField("Details (optional)", text: $details, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(BodyFont.system(size: 12.5))
                .lineLimit(3...6)

            if let error {
                Text(error)
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(.orange)
            }

            HStack {
                Spacer()
                Button("Add") {
                    Task { await commit() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(title.isEmpty || saving)
                if saving { ProgressView().controlSize(.small) }
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func commit() async {
        guard !title.isEmpty else { return }
        saving = true
        error = nil
        defer { saving = false }
        var data: [String: DBJSON] = [:]
        data["title"] = .string(title)
        if !details.isEmpty {
            // Pick the right field name based on the target collection.
            switch collectionName {
            case "notes":   data["body"] = .string(details)
            case "tasks", "goals", "projects":
                data["description"] = .string(details)
            default:
                data["description"] = .string(details)
            }
        }
        // Required fields for known built-ins.
        switch collectionName {
        case "tasks":
            data["status"] = .string("todo")
            data["priority"] = .string("medium")
        case "goals":
            data["status"] = .string("active")
            data["level"] = .string("personal")
        case "projects":
            data["status"] = .string("in_progress")
        default:
            break
        }
        do {
            _ = try await manager.createRecord(collection: collectionName, data: data)
            isPresented = false
        } catch {
            self.error = error.localizedDescription
        }
    }
}
