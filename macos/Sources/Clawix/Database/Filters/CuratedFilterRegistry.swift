import Foundation

/// Declarative registry of curated tabs per built-in collection. Each
/// tab describes a chip set + sort that the UI applies on top of the
/// user's free filter chips.
enum CuratedFilterRegistry {

    struct Tab: Identifiable, Equatable, Hashable {
        let id: String
        let label: String
        let chips: [DBFilterState.Chip]
        let sort: DBFilterState.Sort?
    }

    /// Curated entries that appear in the main sidebar of the app
    /// (Productivity section).
    static let sidebarEntries: [(route: String, label: String, icon: String, collection: String)] = [
        ("tasks", "Tasks", "checkmark.circle", "tasks"),
        ("goals", "Goals", "flag", "goals"),
        ("notes", "Notes", "note.text", "notes"),
        ("projects", "Projects", "square.stack.3d.up", "projects"),
    ]

    static func tabs(for collection: String) -> [Tab] {
        switch collection {
        case "tasks": return tasksTabs
        case "goals": return goalsTabs
        case "notes": return notesTabs
        case "projects": return projectsTabs
        default: return defaultTabs
        }
    }

    // Default (non-curated) collections only get an All / Archived toggle.
    private static let defaultTabs: [Tab] = [
        Tab(id: "all", label: "All", chips: [
            DBFilterState.Chip(field: "archivedAt", op: .isNull, value: .null)
        ], sort: DBFilterState.Sort(field: "updatedAt", descending: true)),
        Tab(id: "archived", label: "Archived", chips: [
            DBFilterState.Chip(field: "archivedAt", op: .notNull, value: .null)
        ], sort: DBFilterState.Sort(field: "updatedAt", descending: true)),
    ]

    private static let tasksTabs: [Tab] = [
        Tab(id: "inbox",    label: "Inbox", chips: [
            DBFilterState.Chip(field: "archivedAt", op: .isNull, value: .null),
            DBFilterState.Chip(field: "status", op: .eq, value: .string("todo")),
        ], sort: DBFilterState.Sort(field: "createdAt", descending: true)),
        Tab(id: "today",    label: "Today", chips: [
            DBFilterState.Chip(field: "archivedAt", op: .isNull, value: .null),
        ], sort: DBFilterState.Sort(field: "dueAt", descending: false)),
        Tab(id: "upcoming", label: "Upcoming", chips: [
            DBFilterState.Chip(field: "archivedAt", op: .isNull, value: .null),
            DBFilterState.Chip(field: "status", op: .neq, value: .string("done")),
        ], sort: DBFilterState.Sort(field: "dueAt", descending: false)),
        Tab(id: "anytime",  label: "Anytime", chips: [
            DBFilterState.Chip(field: "archivedAt", op: .isNull, value: .null),
        ], sort: DBFilterState.Sort(field: "updatedAt", descending: true)),
        Tab(id: "done",     label: "Done", chips: [
            DBFilterState.Chip(field: "archivedAt", op: .isNull, value: .null),
            DBFilterState.Chip(field: "status", op: .eq, value: .string("done")),
        ], sort: DBFilterState.Sort(field: "updatedAt", descending: true)),
        Tab(id: "archived", label: "Archived", chips: [
            DBFilterState.Chip(field: "archivedAt", op: .notNull, value: .null),
        ], sort: nil),
    ]

    private static let goalsTabs: [Tab] = [
        Tab(id: "active", label: "Active", chips: [
            DBFilterState.Chip(field: "archivedAt", op: .isNull, value: .null),
            DBFilterState.Chip(field: "status", op: .eq, value: .string("active")),
        ], sort: DBFilterState.Sort(field: "updatedAt", descending: true)),
        Tab(id: "paused", label: "Paused", chips: [
            DBFilterState.Chip(field: "archivedAt", op: .isNull, value: .null),
            DBFilterState.Chip(field: "status", op: .eq, value: .string("paused")),
        ], sort: nil),
        Tab(id: "done", label: "Done", chips: [
            DBFilterState.Chip(field: "archivedAt", op: .isNull, value: .null),
            DBFilterState.Chip(field: "status", op: .eq, value: .string("done")),
        ], sort: DBFilterState.Sort(field: "updatedAt", descending: true)),
        Tab(id: "archived", label: "Archived", chips: [
            DBFilterState.Chip(field: "archivedAt", op: .notNull, value: .null),
        ], sort: nil),
    ]

    private static let notesTabs: [Tab] = [
        Tab(id: "recent", label: "Recent", chips: [
            DBFilterState.Chip(field: "archivedAt", op: .isNull, value: .null),
        ], sort: DBFilterState.Sort(field: "updatedAt", descending: true)),
        Tab(id: "inbox", label: "Inbox", chips: [
            DBFilterState.Chip(field: "archivedAt", op: .isNull, value: .null),
        ], sort: DBFilterState.Sort(field: "createdAt", descending: true)),
        Tab(id: "archived", label: "Archived", chips: [
            DBFilterState.Chip(field: "archivedAt", op: .notNull, value: .null),
        ], sort: nil),
    ]

    private static let projectsTabs: [Tab] = [
        Tab(id: "active", label: "Active", chips: [
            DBFilterState.Chip(field: "archivedAt", op: .isNull, value: .null),
            DBFilterState.Chip(field: "status", op: .eq, value: .string("active")),
        ], sort: DBFilterState.Sort(field: "updatedAt", descending: true)),
        Tab(id: "on_hold", label: "On hold", chips: [
            DBFilterState.Chip(field: "archivedAt", op: .isNull, value: .null),
            DBFilterState.Chip(field: "status", op: .eq, value: .string("paused")),
        ], sort: nil),
        Tab(id: "done", label: "Done", chips: [
            DBFilterState.Chip(field: "archivedAt", op: .isNull, value: .null),
            DBFilterState.Chip(field: "status", op: .eq, value: .string("done")),
        ], sort: DBFilterState.Sort(field: "updatedAt", descending: true)),
        Tab(id: "archived", label: "Archived", chips: [
            DBFilterState.Chip(field: "archivedAt", op: .notNull, value: .null),
        ], sort: nil),
    ]
}
