import Foundation

/// One open "window" inside a chat's right sidebar. Web pages, file
/// previews and side chats live side by side as siblings of the same
/// tab strip, so a chat's sidebar can hold any mix of the three.
enum SidebarItem: Identifiable, Equatable, Codable {
    case web(WebPayload)
    case file(FilePayload)
    case chat(ChatPayload)
    case iosSimulator(IOSSimulatorPayload)

    /// Side-chat tab. The `id` doubles as the underlying `Chat.id` of
    /// the silently-forked conversation so the tab and the chat share
    /// identity. The pill resolves its title dynamically from
    /// `appState.chat(byId:)` so renames flow without state sync.
    struct ChatPayload: Equatable, Codable {
        let id: UUID
    }

    struct WebPayload: Equatable, Codable {
        let id: UUID
        var url: URL
        var title: String
        var faviconURL: URL?
        var pageZoom: Double = 1.0
        var mobileMode: Bool = false

        init(
            id: UUID,
            url: URL,
            title: String,
            faviconURL: URL? = nil,
            pageZoom: Double = 1.0,
            mobileMode: Bool = false
        ) {
            self.id = id
            self.url = url
            self.title = title
            self.faviconURL = faviconURL
            self.pageZoom = pageZoom
            self.mobileMode = mobileMode
        }

        // Custom decoder so existing on-disk payloads (no zoom/mobile fields)
        // don't fail to load. Newly added fields default to their identity
        // values, matching the in-memory init defaults.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try c.decode(UUID.self, forKey: .id)
            self.url = try c.decode(URL.self, forKey: .url)
            self.title = try c.decode(String.self, forKey: .title)
            self.faviconURL = try c.decodeIfPresent(URL.self, forKey: .faviconURL)
            self.pageZoom = try c.decodeIfPresent(Double.self, forKey: .pageZoom) ?? 1.0
            self.mobileMode = try c.decodeIfPresent(Bool.self, forKey: .mobileMode) ?? false
        }
    }

    struct FilePayload: Equatable, Codable {
        let id: UUID
        var path: String
    }

    struct IOSSimulatorPayload: Equatable, Codable {
        let id: UUID
        var deviceUDID: String?
        var deviceName: String

        init(id: UUID, deviceUDID: String? = nil, deviceName: String = "iOS Simulator") {
            self.id = id
            self.deviceUDID = deviceUDID
            self.deviceName = deviceName
        }
    }

    var id: UUID {
        switch self {
        case .web(let p):  return p.id
        case .file(let p): return p.id
        case .chat(let p): return p.id
        case .iosSimulator(let p): return p.id
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
