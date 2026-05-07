import Foundation
import ClawixCore
import Observation
#if canImport(UIKit)
import UIKit
#endif

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

    /// State of an in-flight or cached request for an `imagegen` PNG
    /// the assistant produced (or any image referenced by absolute
    /// path under `~/.codex/generated_images`). Keyed by absolute path
    /// on the Mac. The bridge serves the bytes via `requestGeneratedImage`
    /// / `generatedImageSnapshot`; we cache the decoded image so a
    /// single PNG painted in the timeline AND inline in the markdown
    /// only round-trips once.
    enum GeneratedImageState: Equatable {
        case loading
        #if canImport(UIKit)
        case loaded(UIImage)
        #else
        case loaded(Data)
        #endif
        case failed(reason: String)

        static func == (lhs: GeneratedImageState, rhs: GeneratedImageState) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading): return true
            case (.failed(let a), .failed(let b)): return a == b
            case (.loaded, .loaded): return true
            default: return false
            }
        }
    }

    var connection: ConnectionState = .unpaired
    var chats: [WireChat] = []
    var messagesByChat: [String: [WireMessage]] = [:]
    var openChatId: String?
    var fileSnapshots: [String: FileSnapshotState] = [:]
    /// Cache of generated images keyed by absolute path on the Mac.
    /// Painted by the assistant timeline (workitem-driven) and by the
    /// inline markdown renderer (`![](file:...)` / `![](/Users/.../*.png)`)
    /// so the same path resolved from two angles only round-trips once.
    var generatedImagesByPath: [String: GeneratedImageState] = [:]

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

    /// In-flight `requestAudio` requests keyed by `audioId`. Each
    /// continuation resumes with the byte payload when the matching
    /// `audioSnapshot` frame arrives. Drained on bridge tear-down so
    /// AudioBubble's loader doesn't dangle.
    @ObservationIgnored
    private var pendingAudioFetches: [String: [CheckedContinuation<(data: Data, mimeType: String), Error>]] = [:]

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
        for (_, conts) in pendingAudioFetches {
            for cont in conts {
                cont.resume(throwing: TranscriptionBridgeError.notConnected)
            }
        }
        pendingAudioFetches.removeAll()
    }

    /// Fetch the bytes of a previously-stored voice clip. Multiple
    /// concurrent calls for the same `audioId` coalesce onto a single
    /// frame round trip — useful when the chat first paints and the
    /// audio bubble lazily decides to preload before the user taps.
    @MainActor
    func requestAudio(audioId: String) async throws -> (data: Data, mimeType: String) {
        guard let client else {
            throw TranscriptionBridgeError.notConnected
        }
        return try await withCheckedThrowingContinuation { continuation in
            let alreadyInFlight = pendingAudioFetches[audioId] != nil
            pendingAudioFetches[audioId, default: []].append(continuation)
            if !alreadyInFlight {
                client.requestAudio(audioId: audioId)
            }
        }
    }

    /// Resolve all continuations waiting on `audioId` with the daemon's
    /// reply. Called by `BridgeClient` when an `audioSnapshot` frame
    /// lands. Errors from the daemon are surfaced as `daemonError`;
    /// missing payload (no error, no bytes) gets a generic
    /// `notConnected` so the bubble shows a "tap again to retry" state.
    @MainActor
    func applyAudioSnapshot(
        audioId: String,
        audioBase64: String?,
        mimeType: String?,
        errorMessage: String?
    ) {
        guard let conts = pendingAudioFetches.removeValue(forKey: audioId) else { return }
        if let errorMessage, !errorMessage.isEmpty {
            for c in conts { c.resume(throwing: TranscriptionBridgeError.daemonError(errorMessage)) }
            return
        }
        guard let audioBase64,
              let data = Data(base64Encoded: audioBase64),
              let mime = mimeType
        else {
            for c in conts { c.resume(throwing: TranscriptionBridgeError.notConnected) }
            return
        }
        for c in conts { c.resume(returning: (data, mime)) }
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

    /// Kick off (or return cached) bytes for a generated image. Safe to
    /// call from a SwiftUI body — repeated invocations while loading
    /// are no-ops, and cached `.loaded` returns immediately. A second
    /// call after `.failed` retries (the user can tap the placeholder
    /// to reissue the fetch).
    @MainActor
    func requestGeneratedImage(path: String) -> GeneratedImageState {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failed(reason: "Empty path")
        }
        if let existing = generatedImagesByPath[trimmed] {
            switch existing {
            case .loading, .loaded:
                return existing
            case .failed:
                break
            }
        }
        generatedImagesByPath[trimmed] = .loading
        client?.requestGeneratedImage(path: trimmed)
        return .loading
    }

    /// Resolve a pending generated-image fetch with the daemon's reply.
    /// Decodes the base64 bytes into a UIImage so the views can bind
    /// to the cache without each one re-decoding. Failure messages are
    /// stored verbatim so the placeholder can render the daemon's
    /// reason ("Image not found", "Path is outside the sandbox", …).
    @MainActor
    func applyGeneratedImageSnapshot(
        path: String,
        dataBase64: String?,
        mimeType: String?,
        errorMessage: String?
    ) {
        if let errorMessage, !errorMessage.isEmpty {
            generatedImagesByPath[path] = .failed(reason: errorMessage)
            return
        }
        guard let dataBase64,
              let data = Data(base64Encoded: dataBase64) else {
            generatedImagesByPath[path] = .failed(reason: "Empty payload")
            return
        }
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else {
            generatedImagesByPath[path] = .failed(reason: "Couldn't decode image")
            return
        }
        generatedImagesByPath[path] = .loaded(image)
        #else
        generatedImagesByPath[path] = .loaded(data)
        #endif
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

    /// Restore the on-disk snapshot if one exists. Called once at
    /// startup before the bridge connects, so the home screen and any
    /// recently-opened chat detail render their last-known state
    /// instantly while the WebSocket race is still in flight. The
    /// bridge's own `chatsSnapshot` / `messagesSnapshot` frames will
    /// shortly overwrite this with the canonical truth.
    @MainActor
    func loadCachedSnapshot() {
        guard chats.isEmpty, messagesByChat.isEmpty else { return }
        guard let payload = SnapshotCache.load() else { return }
        chats = payload.chats
        messagesByChat = payload.messagesByChat
    }

    /// Schedule a persist of the current chats + messages snapshot
    /// after 500ms of quiet. Streaming chunks and rapid chat updates
    /// collapse into a single write; the IO runs on a background
    /// queue so the main thread is never blocked. Safe to call from
    /// any of the bridge inbound paths after a mutation.
    @MainActor
    func persistSnapshotDebounced() {
        persistTask?.cancel()
        persistTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            let chatsSnap = self.chats
            let messagesSnap = self.messagesByChat
            Task.detached(priority: .background) {
                SnapshotCache.save(chats: chatsSnap, messages: messagesSnap)
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
