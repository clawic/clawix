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

    /// In-flight transcription requests keyed by `requestId`. Each
    /// continuation resumes when the matching `transcriptionResult`
    /// frame arrives. Same lifecycle as the network message: if the
    /// bridge tears down before the reply lands, we resume them with
    /// an error in `clearPendingTranscriptions()`.
    @ObservationIgnored
    private var pendingTranscriptions: [String: CheckedContinuation<String, Error>] = [:]

    /// Drives `SnapshotCache.save` after a quiet 500ms window. Each
    /// call cancels the previous in-flight task; streaming bursts and
    /// rapid chat updates collapse into a single write. The actual
    /// IO runs on a background priority Task to keep the main thread
    /// out of the file-system path entirely.
    @ObservationIgnored
    private var persistTask: Task<Void, Never>?

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
        // Optimistic append: surface the user bubble before the bridge
        // round-trip resolves. The server eventually replies with a
        // `messageAppended` carrying its own canonical id; the
        // `local-` prefix on this placeholder lets `applyMessageAppended`
        // swap the row in-place instead of appending a duplicate.
        let optimistic = WireMessage(
            id: "local-\(UUID().uuidString)",
            role: .user,
            content: trimmed,
            timestamp: Date()
        )
        messagesByChat[chatId, default: []].append(optimistic)
        if pendingNewChats.remove(chatId) != nil {
            client?.sendNewChat(chatId: chatId, text: trimmed, attachments: attachments)
        } else {
            client?.sendPrompt(chatId: chatId, text: trimmed, attachments: attachments)
        }
    }

    /// Apply a server-confirmed message append. If a matching local
    /// optimistic user bubble exists (`id` prefixed `local-`, same
    /// `role` and `content`), the server payload is merged onto it
    /// while preserving the placeholder's `id`. Keeping the id stable
    /// means SwiftUI's `ForEach(id: \.id)` does not unmount/remount
    /// the row, so the entrance animation that already played at
    /// optimistic-append time does not run a second time on ack.
    /// Anything else (assistant messages, brand-new chats from
    /// elsewhere, retries) appends at the tail like before.
    @MainActor
    func applyMessageAppended(chatId: String, message: WireMessage) {
        var current = messagesByChat[chatId] ?? []
        if message.role == .user,
           let idx = current.firstIndex(where: {
               $0.id.hasPrefix("local-")
                   && $0.role == .user
                   && $0.content == message.content
           }) {
            let placeholderId = current[idx].id
            current[idx] = WireMessage(
                id: placeholderId,
                role: message.role,
                content: message.content,
                reasoningText: message.reasoningText,
                streamingFinished: message.streamingFinished,
                isError: message.isError,
                timestamp: message.timestamp,
                timeline: message.timeline,
                workSummary: message.workSummary
            )
        } else {
            current.append(message)
        }
        messagesByChat[chatId] = current
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

    /// Send an audio blob to the Mac for transcription. Suspends until
    /// the daemon answers with the corresponding `transcriptionResult`
    /// frame. Throws on bridge error or daemon-reported failure.
    /// `requestId` should be a fresh UUID per call so the answer can
    /// be routed back to the right caller.
    @MainActor
    func transcribeAudio(
        requestId: String,
        audioData: Data,
        mimeType: String,
        language: String?
    ) async throws -> String {
        guard let client else {
            throw TranscriptionBridgeError.notConnected
        }
        return try await withCheckedThrowingContinuation { continuation in
            pendingTranscriptions[requestId] = continuation
            client.transcribeAudio(
                requestId: requestId,
                audioBase64: audioData.base64EncodedString(),
                mimeType: mimeType,
                language: language
            )
        }
    }

    /// Resolve a pending transcription with the daemon's reply. Called
    /// by `BridgeClient` when it decodes a `transcriptionResult` frame.
    @MainActor
    func applyTranscriptionResult(requestId: String, text: String, errorMessage: String?) {
        guard let cont = pendingTranscriptions.removeValue(forKey: requestId) else { return }
        if let errorMessage, !errorMessage.isEmpty {
            cont.resume(throwing: TranscriptionBridgeError.daemonError(errorMessage))
        } else {
            cont.resume(returning: text)
        }
    }

    /// Drain pending transcriptions when the bridge connection drops.
    /// Resumes each continuation with `notConnected` so the iOS view
    /// model can fall back or surface an error.
    @MainActor
    func clearPendingTranscriptions() {
        for (_, cont) in pendingTranscriptions {
            cont.resume(throwing: TranscriptionBridgeError.notConnected)
        }
        pendingTranscriptions.removeAll()
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

    enum TranscriptionBridgeError: Error, LocalizedError {
        case notConnected
        case daemonError(String)

        var errorDescription: String? {
            switch self {
            case .notConnected: return "Not connected to the Mac bridge"
            case .daemonError(let msg): return msg
            }
        }
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
