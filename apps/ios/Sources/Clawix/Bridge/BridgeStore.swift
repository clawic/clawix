import Foundation
import ClawixCore
import Observation

@Observable
final class BridgeStore {

    /// Path the bridge client is using. `lan` covers Bonjour-resolved
    /// endpoints AND direct IPv4 candidates from the QR (any private
    /// LAN address, including ethernet). `tailscale` is the CGNAT
    /// 100.64.0.0/10 path: works from anywhere as long as both ends
    /// are on the same Tailnet. Surfaced in the UI so the user can
    /// tell at a glance whether they are on the fast home path or the
    /// remote one.
    enum Route: String, Equatable {
        case lan
        case tailscale
    }

    enum ConnectionState: Equatable {
        case unpaired
        case connecting
        case connected(macName: String?, via: Route?)
        case error(message: String)
    }

    /// State of an in-flight or cached file read. Keyed by absolute
    /// path. `loading` is set the first time the viewer asks for a
    /// path; the bridge reply flips it to `loaded` or `failed`.
    enum FileSnapshotState: Equatable {
        case loading
        case loaded(content: String, isMarkdown: Bool)
        case failed(reason: String)
    }

    var connection: ConnectionState = .unpaired
    var chats: [WireChat] = []
    var messagesByChat: [String: [WireMessage]] = [:]
    var openChatId: String?
    var fileSnapshots: [String: FileSnapshotState] = [:]

    /// Chat ids minted locally by the FAB that haven't yet been
    /// flushed to the Mac. The first `sendPrompt` for an id in this
    /// set is upgraded to a `newChat` frame so the Mac creates the
    /// chat with that exact UUID.
    @ObservationIgnored
    private var pendingNewChats: Set<String> = []

    @ObservationIgnored
    private var client: BridgeClient?

    init() {}

    @MainActor
    func attach(client: BridgeClient) {
        self.client = client
    }

    @MainActor
    func openChat(_ chatId: String) {
        openChatId = chatId
        // Intentionally NOT seeding `messagesByChat[chatId] = []` here.
        // We use the `nil` vs `[]` distinction to mean "snapshot not
        // delivered yet" vs "snapshot arrived and the chat is genuinely
        // empty". The detail view keys its empty-state visibility off
        // that, so a freshly-opened chat doesn't flash "No messages
        // loaded" for the few hundred ms before the bridge replies.
        client?.openChat(chatId)
    }

    /// `true` once a `messagesSnapshot` for this chat has been
    /// delivered. Used to gate the empty-state UI: while loading, the
    /// detail view shows nothing instead of the empty placeholder.
    func hasLoadedMessages(_ chatId: String) -> Bool {
        messagesByChat[chatId] != nil
    }

    @MainActor
    func closeChat() {
        openChatId = nil
    }

    @MainActor
    func sendPrompt(chatId: String, text: String, attachments: [WireAttachment] = []) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Allow attachment-only sends: an empty text body still goes
        // through as long as at least one image is attached, mirroring
        // how the Codex CLI accepts dragged images without a prompt.
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        if pendingNewChats.remove(chatId) != nil {
            client?.sendNewChat(chatId: chatId, text: trimmed, attachments: attachments)
        } else {
            client?.sendPrompt(chatId: chatId, text: trimmed, attachments: attachments)
        }
    }

    /// Mints a fresh chat id for the FAB-driven "new chat" flow. The
    /// id is queued as pending so the next `sendPrompt(chatId:text:)`
    /// emits a `newChat` frame instead, and `messagesByChat` is seeded
    /// to `[]` so the detail view treats the chat as "loaded, empty"
    /// rather than gating on a snapshot that will never arrive (the
    /// chat doesn't exist on the Mac yet).
    @MainActor
    func startNewChat() -> String {
        let id = UUID().uuidString
        pendingNewChats.insert(id)
        messagesByChat[id] = []
        return id
    }

    /// Kick off (or refresh) the read of a file on the Mac. Idempotent:
    /// re-tapping a pill while a request is in flight is a no-op, but a
    /// second tap on a `.failed` row retries.
    @MainActor
    func requestFile(_ path: String) {
        switch fileSnapshots[path] {
        case .loading:
            return
        default:
            fileSnapshots[path] = .loading
            client?.readFile(path: path)
        }
    }

    func messages(for chatId: String) -> [WireMessage] {
        messagesByChat[chatId] ?? []
    }

    func chat(_ chatId: String) -> WireChat? {
        chats.first { $0.id == chatId }
    }

    static func mock() -> BridgeStore {
        let s = BridgeStore()
        s.connection = .connected(macName: "studio Mac", via: .lan)
        s.chats = MockData.chats
        // Seed every chat with the same canned transcript so any row the
        // designer taps lands on a populated detail screen instead of
        // the loading gate. Cheap and isolated to mock builds.
        var seeded: [String: [WireMessage]] = [:]
        for chat in MockData.chats {
            seeded[chat.id] = MockData.messages
        }
        s.messagesByChat = seeded
        return s
    }
}
