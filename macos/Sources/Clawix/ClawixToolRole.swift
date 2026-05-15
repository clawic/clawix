import SwiftUI

/// One mini-app per sidebar tool. Each case mirrors a row in
/// `SidebarToolsCatalog` (see `SidebarView.swift`) and resolves to the same
/// view the main app mounts when the user clicks that row. The binary picks
/// a role at launch from the `CLXAppRole` Info.plist key the build script
/// injects per mini-app bundle.
enum ClawixToolRole: String, CaseIterable {
    case tasks, goals, notes, projects
    case secrets, memory, database
    case photos, documents, recent, drive

    var windowTitle: String {
        switch self {
        case .tasks:     return "Tasks"
        case .goals:     return "Goals"
        case .notes:     return "Notes"
        case .projects:  return "Projects"
        case .secrets:   return "Secrets"
        case .memory:    return "Memory"
        case .database:  return "Database"
        case .photos:    return "Photos"
        case .documents: return "Documents"
        case .recent:    return "Recent"
        case .drive:     return "Drive"
        }
    }

    @ViewBuilder func makeView() -> some View {
        switch self {
        case .tasks:     DatabaseScreen(mode: .curated(collectionName: "tasks"))
        case .goals:     DatabaseScreen(mode: .curated(collectionName: "goals"))
        case .notes:     DatabaseScreen(mode: .curated(collectionName: "notes"))
        case .projects:  DatabaseScreen(mode: .curated(collectionName: "projects"))
        case .secrets:   SecretsScreen()
        case .memory:    MemoryScreen()
        case .database:  DatabaseScreen(mode: .admin)
        case .photos:    DriveScreen(mode: .photos)
        case .documents: DriveScreen(mode: .documents)
        case .recent:    DriveScreen(mode: .recent)
        case .drive:     DriveScreen(mode: .admin)
        }
    }

    /// Resolves the role from `Bundle.main`. v1 tool bundles declare
    /// `CLXAppRole=tool:<slug>`.
    static func fromBundle() -> ClawixToolRole? {
        let raw = Bundle.main.infoDictionary?["CLXAppRole"] as? String ?? ""
        guard raw.hasPrefix("tool:") else { return nil }
        return ClawixToolRole(rawValue: String(raw.dropFirst("tool:".count)))
    }
}
