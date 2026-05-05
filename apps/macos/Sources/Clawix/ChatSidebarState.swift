import Foundation

/// One open "window" inside a chat's right sidebar. Web pages and file
/// previews live side by side as siblings of the same tab strip, so a
/// chat's sidebar can hold any mix of the two.
enum SidebarItem: Identifiable, Equatable, Codable {
    case web(WebPayload)
    case file(FilePayload)

    struct WebPayload: Equatable, Codable {
        let id: UUID
        var url: URL
        var title: String
        var faviconURL: URL?
    }

    struct FilePayload: Equatable, Codable {
        let id: UUID
        var path: String
    }

    var id: UUID {
        switch self {
        case .web(let p):  return p.id
        case .file(let p): return p.id
        }
    }
}

/// Per-conversation right-sidebar state. Each chat owns its own copy and
/// keeps it across restarts. Switching chats animates the column to the
/// destination chat's state (closed if empty, open with whatever was
/// active otherwise).
struct ChatSidebarState: Equatable, Codable {
    var isOpen: Bool = false
    var items: [SidebarItem] = []
    var activeItemId: UUID? = nil

    static let empty = ChatSidebarState()

    var activeItem: SidebarItem? {
        guard let id = activeItemId else { return nil }
        return items.first(where: { $0.id == id })
    }
}
