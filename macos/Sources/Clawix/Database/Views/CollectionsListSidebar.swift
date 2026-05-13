import SwiftUI

/// Sidebar of collections shown by the database admin (3-pane layout).
/// Groups collections in three sections: Productivity (built-in core),
/// Apps (built-in extras: companies, hub, wiki), and Custom.
struct CollectionsListSidebar: View {
    @Binding var selectedCollection: String?
    @EnvironmentObject private var manager: DatabaseManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                section(title: "Productivity", collections: productivityCollections)
                section(title: "Apps", collections: appCollections)
                section(title: "Custom", collections: customCollections)
            }
            .padding(.vertical, 8)
        }
        .background(Color.white.opacity(0.02))
    }

    @ViewBuilder
    private func section(title: String, collections: [DBCollection]) -> some View {
        if !collections.isEmpty {
            Text(title.uppercased())
                .font(BodyFont.system(size: 10, wght: 700))
                .foregroundColor(Palette.textTertiary)
                .tracking(0.5)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 4)
            ForEach(collections) { collection in
                row(for: collection)
            }
        }
    }

    private func row(for collection: DBCollection) -> some View {
        let isSelected = selectedCollection == collection.name
        return Button {
            selectedCollection = collection.name
        } label: {
            HStack(spacing: 8) {
                Image(systemName: iconName(for: collection))
                    .font(.system(size: 11))
                    .frame(width: 14)
                    .foregroundColor(isSelected ? Color.accentColor : Palette.textSecondary)
                Text(collection.displayName)
                    .font(BodyFont.system(size: 12.5, wght: isSelected ? 600 : 500))
                    .foregroundColor(isSelected ? Palette.textPrimary : Palette.textSecondary)
                    .lineLimit(1)
                Spacer()
                let count = manager.records(for: collection.name).count
                if count > 0 {
                    Text("\(count)")
                        .font(BodyFont.system(size: 10.5))
                        .foregroundColor(Palette.textTertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func iconName(for collection: DBCollection) -> String {
        if collection.name == "tasks" { return "checkmark.circle" }
        if collection.name == "goals" { return "flag" }
        if collection.name == "notes" { return "note.text" }
        if collection.name == "projects" { return "square.stack.3d.up" }
        if collection.name == "people" { return "person.2" }
        if collection.name == "areas" { return "circle.grid.2x2" }
        if collection.name == "events" { return "calendar" }
        if collection.name == "issues" { return "exclamationmark.bubble" }
        if collection.name == "decisions" { return "scale.3d" }
        if collection.name == "pages" { return "book" }
        if collection.name == "hub_messages" { return "bubble.left" }
        if collection.builtin { return "doc.text" }
        return "rectangle.stack"
    }

    private var productivityCollections: [DBCollection] {
        let core: Set<String> = [
            "tasks", "goals", "notes", "projects", "areas", "people",
            "lists", "sections", "comments", "attachments", "saved_views",
            "recurrences", "cycles", "epics", "custom_fields", "field_values",
            "templates", "milestones", "events", "activity_entries",
            "blockers", "artifacts", "decisions", "work_sessions",
            "assignments", "handoffs", "approvals", "capacity", "agents",
            "releases", "incidents", "feedback", "checks", "reminders",
            "deadlines", "inbox_threads", "inbox_messages",
        ]
        return manager.collections.filter { core.contains($0.name) }
    }

    private var appCollections: [DBCollection] {
        manager.collections.filter { $0.builtin && !productivityCollections.contains($0) }
    }

    private var customCollections: [DBCollection] {
        manager.collections.filter { !$0.builtin }
    }
}
