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

        let fallbackDetails = details.isEmpty ? title : details
        let searchText = details.isEmpty ? title : "\(title)\n\(details)"
        let now = ISO8601DateFormatter().string(from: Date())

        if collectionName == "inbox_messages" {
            do {
                let thread = try await manager.createRecord(collection: "inbox_threads", data: [
                    "channel": .string("quick_add"),
                    "status": .string("unread"),
                    "subject": .string(title),
                    "preview": .string(fallbackDetails),
                    "latestMessageAt": .string(now),
                ])
                do {
                    _ = try await manager.createRecord(collection: collectionName, data: [
                        "threadId": .string(thread.id),
                        "channel": .string("quick_add"),
                        "direction": .string("inbound"),
                        "status": .string("unread"),
                        "content": .string(fallbackDetails),
                    ])
                    isPresented = false
                } catch {
                    try? await manager.deleteRecord(collection: "inbox_threads", id: thread.id)
                    throw error
                }
            } catch {
                self.error = error.localizedDescription
            }
            return
        }

        var data: [String: DBJSON] = [:]
        switch collectionName {
        case "projects":
            data["name"] = .string(title)
        default:
            data["title"] = .string(title)
        }

        // Required fields for known built-ins.
        switch collectionName {
        case "tasks":
            data["status"] = .string("todo")
            data["priority"] = .string("medium")
            if !details.isEmpty { data["description"] = .string(details) }
        case "goals":
            data["status"] = .string("active")
            data["level"] = .string("personal")
            if !details.isEmpty { data["description"] = .string(details) }
        case "projects":
            data["status"] = .string("in_progress")
            if !details.isEmpty { data["description"] = .string(details) }
        case "notes":
            data["searchText"] = .string(searchText)
            if !details.isEmpty { data["summary"] = .string(details) }
        case "decisions":
            data["status"] = .string("proposed")
            if !details.isEmpty { data["summary"] = .string(details) }
        case "reminders":
            data["status"] = .string("active")
            data["triggerAt"] = .string(ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600)))
            if !details.isEmpty { data["description"] = .string(details) }
        default:
            if !details.isEmpty { data["description"] = .string(details) }
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
