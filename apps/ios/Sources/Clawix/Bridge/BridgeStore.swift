import Foundation
import ClawixCore
import Observation
import os
#if canImport(UIKit)
import UIKit
#endif

/// Temporary diagnostic logger for the new-chat-disappears bug. All
/// writes go through here so a single grep on `subsystem CONTAINS
/// "clawix.bridge.dbg"` over `xcrun simctl spawn ... log show` (sim) or
/// `xcrun devicectl device log stream` (device) surfaces the full
/// timeline of a repro. Remove once the regression is closed out.
fileprivate let bridgeDbg = Logger(subsystem: "clawix.bridge.dbg", category: "store")

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
    /// Pagination state per chat. `true` means the daemon has older
    /// messages we haven't pulled yet; the chat detail view shows the
    /// scroll-up sentinel and triggers `loadOlderMessages` when it
    /// materializes. Reset on every `messagesSnapshot` (the snapshot is
    /// the new baseline). Absent / `false` is treated as "no older
    /// history known" — covers chats we just opened, chats the legacy
    /// daemon served without pagination metadata, and chats hydrated
    /// from the on-disk snapshot cache before reconnect.
    var hasMoreByChat: [String: Bool] = [:]
    /// `true` while a `loadOlderMessages` round trip is in flight for
    /// the chat. Guards against firing duplicate requests when the
    /// scroll-up sentinel re-materializes (a single onAppear can fire
    /// twice during fast scrolls). Cleared by `applyMessagesPage`.
    var loadingOlderByChat: [String: Bool] = [:]
    /// Cursor for the next `loadOlderMessages` call: id of the oldest
    /// message currently held for the chat. Recomputed from
    /// `messagesByChat[chatId].first` after every snapshot/page apply.
    var oldestKnownIdByChat: [String: String] = [:]
    var openChatId: String?
    var fileSnapshots: [String: FileSnapshotState] = [:]
    /// Cache of generated images keyed by absolute path on the Mac.
    /// Painted by the assistant timeline (workitem-driven) and by the
    /// inline markdown renderer (`![](file:...)` / `![](/Users/.../*.png)`)
    /// so the same path resolved from two angles only round-trips once.
    var generatedImagesByPath: [String: GeneratedImageState] = [:]
    #if canImport(UIKit)
    /// Inline image previews for user messages that this device sent
    /// during the current session. Keyed by `WireMessage.id`. The
    /// `messageAppended` echo from the Mac merges onto the local-* id
    /// (see `applyMessageAppended`), so the preview survives the round
    /// trip without re-keying. Cleared when the chat is dropped from
    /// `messagesByChat` (relaunch, manual delete) — we deliberately do
    /// NOT persist these blobs because they would balloon the snapshot
    /// cache and the photo lives on the Mac side anyway.
    var attachmentImagesByMessageId: [String: [UIImage]] = [:]
    #endif

    /// Per-cwd display-name overrides set by the user on this iPhone.
    /// Persisted to UserDefaults under `Clawix.ProjectLabels.v1`. The
    /// daemon doesn't model project entities yet, so a folder rename
    /// is local until the bridge gets a `renameProject` frame; this
    /// keeps the action useful (the user's chosen label sticks across
    /// relaunches on this device) without lying about syncing.
    var projectLabels: [String: String] = ProjectLabelsCache.load()

    /// Chat ids whose last assistant turn finished while the user was
    /// looking somewhere else. Drives the soft-blue dot at the right
    /// edge of the chat row (same role as the desktop's
    /// `hasUnreadCompletion`). The wire model has no read-state, so
    /// detection is purely client-side: we watch for the
    /// `hasActiveTurn: true → false` transition on incoming chat
    /// updates and add the chat id here when `openChatId` is something
    /// else. Cleared the moment the user opens that chat. Persisted to
    /// UserDefaults so the dot survives a relaunch.
    var unreadChatIds: Set<String> = UnreadChatsCache.load()

    /// In-memory mirror of each chat's last observed `hasActiveTurn`,
    /// used only to detect the true→false transition that promotes a
    /// chat into `unreadChatIds`. Not persisted: relaunch resets the
    /// baseline so we do not retroactively decide "everything that
    /// looks idle now must have been busy before".
    @ObservationIgnored
    private var previousActiveTurnByChat: [String: Bool] = [:]

    /// Chat ids minted locally by the FAB that haven't yet been
    /// flushed to the Mac. The first `sendPrompt` for an id in this
    /// set is upgraded to a `newChat` frame so the Mac creates the
    /// chat with that exact UUID.
    @ObservationIgnored
    private var pendingNewChats: Set<String> = []

    @ObservationIgnored
    private var client: BridgeClient?

    /// Mock-only stand-in for the bridge's `loadOlderMessages` round
    /// trip. Set by `BridgeStore.mock()` so designer-preview launches
    /// (`CLAWIX_MOCK=1`) can exercise the scroll-up flow without a
    /// paired Mac. Receives the same `(chatId, beforeMessageId)` pair
    /// the real client would send and is responsible for invoking
    /// `applyMessagesPage` (with whatever delay it likes) to flip the
    /// in-flight flag back off. `@MainActor` because the apply method
    /// it ultimately calls is main-actor isolated.
    @ObservationIgnored
    var mockLoadOlderHandler: (@MainActor (String, String) -> Void)?

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
        clearUnread(chatId: chatId)
        // Intentionally NOT seeding `messagesByChat[chatId] = []` here.
        // We use the `nil` vs `[]` distinction to mean "snapshot not
        // delivered yet" vs "snapshot arrived and the chat is genuinely
        // empty". The detail view keys its empty-state visibility off
        // that, so a freshly-opened chat doesn't flash "No messages
        // loaded" for the few hundred ms before the bridge replies.
        client?.openChat(chatId)
    }

    /// Drop the soft-blue unread dot for `chatId`. Called when the user
    /// opens the chat (the act of reading it) and from `applyChatUpdate`
    /// when a chat starts a brand-new turn (the user is about to look
    /// at it anyway, and the previous completion is no longer the most
    /// recent thing on the row).
    @MainActor
    private func clearUnread(chatId: String) {
        guard unreadChatIds.contains(chatId) else { return }
        unreadChatIds.remove(chatId)
        UnreadChatsCache.save(unreadChatIds)
    }

    /// True when `chatId`'s last assistant turn finished without the
    /// user looking. Drives the soft-blue dot in `ChatRow`.
    func isUnread(chatId: String) -> Bool {
        unreadChatIds.contains(chatId)
    }

    /// Centralized chat-update entry point. Detects the
    /// `hasActiveTurn: true → false` transition and surfaces the
    /// soft-blue unread dot when the user is not currently viewing
    /// that chat. Routed from both `applyChatsSnapshot` and the
    /// per-chat `chatUpdated` frame.
    @MainActor
    private func observeActiveTurnTransition(_ updated: WireChat) {
        let prior = previousActiveTurnByChat[updated.id]
        if prior == true && updated.hasActiveTurn == false && openChatId != updated.id {
            if !unreadChatIds.contains(updated.id) {
                unreadChatIds.insert(updated.id)
                UnreadChatsCache.save(unreadChatIds)
            }
        }
        // A brand-new turn starting on a row that was carrying an old
        // unread dot: the dot referred to the previous completion, which
        // is no longer the freshest event on the row. Clearing here
        // prevents the dot from outliving the moment it described.
        if prior == false && updated.hasActiveTurn == true {
            clearUnread(chatId: updated.id)
        }
        previousActiveTurnByChat[updated.id] = updated.hasActiveTurn
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
    /// Replace the chat's message list with a server-delivered snapshot
    /// while preserving the ids of any local optimistic user bubbles
    /// already on screen. Without the id-preserving step the snapshot
    /// the daemon emits when a brand-new chat materializes would swap
    /// the placeholder's `local-...` id for the server id; the
    /// `ForEach(id: \.id)` in the transcript would then unmount and
    /// remount the bubble, replaying its entrance animation a second
    /// time. Matching by `role == .user` + content mirrors what
    /// `applyMessageAppended` does on subsequent turns.
    @MainActor
    func applyMessagesSnapshot(chatId: String, messages: [WireMessage], hasMore: Bool? = nil) {
        // Reset pagination state regardless: the snapshot is the new
        // baseline. Done before the equality short-circuit because
        // `hasMore` may have flipped (legacy daemon → paged daemon
        // mid-session, or vice versa) without the message array
        // changing. Treat absent metadata as "no older history known"
        // so legacy peers keep their old eager behaviour.
        hasMoreByChat[chatId] = hasMore ?? false
        loadingOlderByChat[chatId] = false
        oldestKnownIdByChat[chatId] = messages.first?.id
        // Short-circuit when the incoming snapshot is structurally
        // identical to what we already hold. `@Observable` would
        // otherwise invalidate every subscriber on the reassignment
        // even when the rendered output is the same, and the chat
        // transcript reanchors its ScrollView during that invalidation
        // window, surfacing as a visible jump on chat entry.
        if let current = messagesByChat[chatId], current == messages {
            return
        }
        let placeholders = (messagesByChat[chatId] ?? []).filter {
            $0.id.hasPrefix("local-") && $0.role == .user
        }
        let reconciled: [WireMessage]
        if placeholders.isEmpty {
            reconciled = messages
        } else {
            var consumed: Set<String> = []
            reconciled = messages.map { msg in
                guard msg.role == .user,
                      let placeholder = placeholders.first(where: {
                          !consumed.contains($0.id) && $0.content == msg.content
                      })
                else { return msg }
                consumed.insert(placeholder.id)
                return WireMessage(
                    id: placeholder.id,
                    role: msg.role,
                    content: msg.content,
                    reasoningText: msg.reasoningText,
                    streamingFinished: msg.streamingFinished,
                    isError: msg.isError,
                    timestamp: msg.timestamp,
                    timeline: msg.timeline,
                    workSummary: msg.workSummary,
                    audioRef: msg.audioRef,
                    attachments: msg.attachments
                )
            }
        }
        messagesByChat[chatId] = reconciled
        oldestKnownIdByChat[chatId] = reconciled.first?.id
        #if canImport(UIKit)
        for msg in reconciled {
            ingestInlineAttachments(messageId: msg.id, attachments: msg.attachments)
        }
        #endif
    }

    /// Apply a server-delivered page of older messages. Prepended to
    /// the existing array, deduped by id (a `messageAppended` for a
    /// streamed message could land in the same window the server
    /// sliced the page from). Updates the cursor to the new oldest
    /// id and clears the in-flight flag. An empty page with
    /// `hasMore: false` is the canonical "you reached the start" reply
    /// — also covers the case where the cursor was invalidated by an
    /// `editPrompt` that truncated the chat between requests.
    @MainActor
    func applyMessagesPage(chatId: String, messages: [WireMessage], hasMore: Bool) {
        loadingOlderByChat[chatId] = false
        hasMoreByChat[chatId] = hasMore
        guard !messages.isEmpty else { return }
        var current = messagesByChat[chatId] ?? []
        let existingIds = Set(current.map(\.id))
        let prepend = messages.filter { !existingIds.contains($0.id) }
        guard !prepend.isEmpty else { return }
        current.insert(contentsOf: prepend, at: 0)
        messagesByChat[chatId] = current
        oldestKnownIdByChat[chatId] = current.first?.id
        #if canImport(UIKit)
        for msg in prepend {
            ingestInlineAttachments(messageId: msg.id, attachments: msg.attachments)
        }
        #endif
    }

    /// Ask the daemon for the next page of older messages if (and only
    /// if) we have a cursor, the daemon told us there are more, and we
    /// don't already have a page in flight. Called by the chat detail
    /// view's scroll-up sentinel; the iOS-26 `LazyVStack` materializes
    /// it whenever it enters the viewport, so this is on the hot path
    /// and must short-circuit cheaply.
    @MainActor
    func requestOlderIfNeeded(chatId: String) {
        guard hasMoreByChat[chatId] == true else { return }
        guard loadingOlderByChat[chatId] != true else { return }
        guard let cursor = oldestKnownIdByChat[chatId] else { return }
        loadingOlderByChat[chatId] = true
        if let client {
            client.loadOlderMessages(chatId: chatId, beforeMessageId: cursor)
        } else if let mockLoadOlderHandler {
            mockLoadOlderHandler(chatId, cursor)
        } else {
            // No bridge attached and no mock handler: cancel the
            // in-flight flag so the next sentinel firing can retry
            // (e.g. once the bridge connects).
            loadingOlderByChat[chatId] = false
        }
    }

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
                workSummary: message.workSummary,
                audioRef: message.audioRef,
                attachments: message.attachments
            )
            #if canImport(UIKit)
            ingestInlineAttachments(messageId: placeholderId, attachments: message.attachments)
            #endif
        } else {
            current.append(message)
            #if canImport(UIKit)
            ingestInlineAttachments(messageId: message.id, attachments: message.attachments)
            #endif
        }
        messagesByChat[chatId] = current
    }

    #if canImport(UIKit)
    /// Decode the inline base64 image bytes attached to a hydrated
    /// message and push them into `attachmentImagesByMessageId` so the
    /// `UserBubble` renders the same `[image]` thumbnails the user
    /// originally saw. No-op when the array is empty (typed messages,
    /// assistant turns, or peers that never sent attachments). Skips
    /// silently if the bytes are unreadable so a malformed fixture
    /// doesn't bring down the chat.
    private func ingestInlineAttachments(messageId: String, attachments: [WireAttachment]) {
        guard !attachments.isEmpty else { return }
        // Don't overwrite a locally-cached preview from this device's
        // own send: that copy has the original `UIImage` and round-tripping
        // through base64 can drop fidelity.
        if attachmentImagesByMessageId[messageId] != nil { return }
        var images: [UIImage] = []
        for att in attachments where att.kind == .image {
            // `.ignoreUnknownCharacters` so newlines / whitespace inside
            // the base64 (e.g. when the bytes were inlined as a Swift
            // multiline string for the standalone `CLAWIX_MOCK=1` flow)
            // don't reject the otherwise-valid payload.
            guard let data = Data(
                    base64Encoded: att.dataBase64,
                    options: .ignoreUnknownCharacters
                  ),
                  let image = UIImage(data: data) else { continue }
            images.append(image)
        }
        if !images.isEmpty {
            attachmentImagesByMessageId[messageId] = images
        }
    }
    #endif

    /// Rename a project's display name on this device. The mapping is
    /// keyed by `cwd` because that's the project's stable identity in
    /// the iOS model (`DerivedProject.id == cwd`); the cwd itself is
    /// untouched. Empty / whitespace-only names clear the override so
    /// the project falls back to the cwd's last path component again.
    @MainActor
    func renameProject(cwd: String, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            projectLabels.removeValue(forKey: cwd)
        } else {
            projectLabels[cwd] = trimmed
        }
        ProjectLabelsCache.save(projectLabels)
    }

    /// Resolve the display name for a project. Returns the user's
    /// override if one has been set on this device, otherwise the
    /// fallback (typically the cwd's last path component).
    func projectDisplayName(cwd: String, fallback: String) -> String {
        let custom = projectLabels[cwd]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let custom, !custom.isEmpty { return custom }
        return fallback
    }

    /// Rename a chat. Updates the local title optimistically so the
    /// chat list and detail header reflect the new name immediately,
    /// then sends a `renameChat` frame to the Mac. The daemon writes
    /// through to Codex (`thread/name/set`) and republishes via
    /// `chatUpdated`, which is the canonical state.
    @MainActor
    func renameChat(chatId: String, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let idx = chats.firstIndex(where: { $0.id == chatId }) {
            chats[idx].title = trimmed
        }
        client?.renameChat(chatId: chatId, title: trimmed)
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

    /// Merge a server-delivered chats list into `chats` while preserving
    /// any locally-synthesized stub the Mac hasn't acknowledged yet. A
    /// fresh `newChat` flow goes:
    ///
    ///   1. iOS calls `beginPendingTurn` and the user message lands in
    ///      `messagesByChat[id]` with a `local-…` id.
    ///   2. iOS dispatches `sendNewChat` to the Mac.
    ///   3. The Mac processes it and republishes; the bus emits a
    ///      `chatsSnapshot` containing the new chat.
    ///
    /// Between (2) and (3), the Mac may emit *another* snapshot for an
    /// unrelated reason (post-auth bootstrap, `listChats` reply, a
    /// throttled tick triggered by a peer). Replacing `chats` wholesale
    /// at that point would drop our optimistic stub and make the chat
    /// vanish from the list until the echo lands. The merge keeps the
    /// stub alive: any chat we currently hold whose id isn't in
    /// `incoming` AND whose transcript still has a `local-…` user
    /// bubble (so we know it's mid-flight, not just stale) is appended
    /// back. The chat list views handle final ordering.
    @MainActor
    func applyChatsSnapshot(_ incoming: [WireChat]) {
        let incomingIds = Set(incoming.map(\.id))
        let inflightCandidates = chats.filter { existing in
            guard !incomingIds.contains(existing.id) else { return false }
            return messagesByChat[existing.id]?
                .contains(where: { $0.id.hasPrefix("local-") }) ?? false
        }
        let priorIds = Set(chats.map(\.id))
        let droppedIds = priorIds.subtracting(incomingIds).subtracting(inflightCandidates.map(\.id))
        bridgeDbg.notice("applyChatsSnapshot in=\(incoming.count, privacy: .public) prior=\(self.chats.count, privacy: .public) keptInflight=\(inflightCandidates.count, privacy: .public) dropped=\(droppedIds.count, privacy: .public)")
        if !droppedIds.isEmpty {
            for did in droppedIds.sorted().prefix(8) {
                let msgs = messagesByChat[did]
                let firstId = msgs?.first?.id ?? "<no msgs>"
                bridgeDbg.notice("  drop id=\(did, privacy: .public) firstMsgId=\(firstId, privacy: .public) msgCount=\(msgs?.count ?? 0, privacy: .public)")
            }
        }
        for chat in incoming {
            observeActiveTurnTransition(chat)
        }
        chats = incoming + inflightCandidates
        // Drop unread entries for chats the daemon no longer reports
        // (deleted on the Mac). The set otherwise grows monotonically
        // across a relaunch.
        let known = incomingIds.union(inflightCandidates.map(\.id))
        let stale = unreadChatIds.subtracting(known)
        if !stale.isEmpty {
            unreadChatIds.subtract(stale)
            UnreadChatsCache.save(unreadChatIds)
        }
    }

    /// Apply a single `chatUpdated` frame. Centralized so the
    /// soft-blue unread dot logic lives in one place; `BridgeClient`
    /// routes through this instead of writing into `chats[idx]`
    /// directly.
    @MainActor
    func applyChatUpdate(_ chat: WireChat) {
        observeActiveTurnTransition(chat)
        if let idx = chats.firstIndex(where: { $0.id == chat.id }) {
            chats[idx] = chat
            bridgeDbg.notice("applyChatUpdate REPLACE id=\(chat.id, privacy: .public) hasActiveTurn=\(chat.hasActiveTurn, privacy: .public)")
        } else {
            chats.append(chat)
            bridgeDbg.notice("applyChatUpdate APPEND id=\(chat.id, privacy: .public) hasActiveTurn=\(chat.hasActiveTurn, privacy: .public) totalChats=\(self.chats.count, privacy: .public)")
        }
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
