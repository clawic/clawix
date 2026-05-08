import Foundation

/// Wire-format version exchanged in every frame. Bumped on any breaking
/// change to `BridgeFrame` payloads. Clients refuse to talk to a peer
/// reporting a different `schemaVersion` and surface an "update Clawix"
/// empty state.
///
/// v2 (2026-05): Added `clientKind` capability tag to `auth` so the
/// server can tell apart the iPhone companion from a co-located desktop
/// client (the macOS GUI talking to the LaunchAgent daemon over
/// loopback). Added desktop-only frame types for chat editing
/// (`editPrompt`), archive/pin toggles, project listing, and the
/// pairing handshake the GUI uses to ask the daemon for a fresh QR.
/// v1 frames decode cleanly into v2 because every new field is optional
/// and every new frame type is additive.
///
/// v3 (2026-05): Voice notes. `WireAttachment` now carries a `kind`
/// discriminator (`image` | `audio`) so the daemon can route audio
/// blobs to Whisper instead of `localImage`. `WireMessage` carries an
/// optional `audioRef` so the chat history shows a playable bubble for
/// user messages that started life as a voice clip. New `requestAudio`
/// / `audioSnapshot` frames let clients fetch the original audio bytes
/// for replay. Old peers accept the new fields tolerantly because
/// every addition is optional, but `schemaVersion` bumps so callers
/// without the new frame types short-circuit cleanly with an "Update
/// Clawix" empty state instead of silently failing on a missing case.
///
/// v4 (2026-05): Inline assistant images. `WireWorkItem` carries an
/// optional `generatedImagePath` so clients know which PNG Codex wrote
/// for an `imageGeneration` tool call. New `requestGeneratedImage` /
/// `generatedImageSnapshot` frames let clients fetch the bytes by
/// path (the daemon sandboxes reads to `~/.codex/generated_images`).
/// Used both by the work-item path (turn 1: model called the
/// `imagegen` tool) and by markdown-detected paths the model wrote
/// inline (turn 2: model wrote `![](/Users/.../*.png)` after the
/// user complained the image hadn't shown up). All additions are
/// optional so v3 peers keep parsing.
///
/// v5 (2026-05): Rate limits. Three new desktop-only frames so the
/// macOS GUI can keep its "Remaining usage limits" widget alive when
/// the LaunchAgent daemon owns the Codex backend. `requestRateLimits`
/// (desktop -> daemon) asks for the current snapshot, `rateLimitsSnapshot`
/// is the reply, and `rateLimitsUpdated` is a daemon push fired whenever
/// Codex emits `account/rateLimits/updated`. iPhone clients ignore the
/// new types. All additions are additive frames; v4 peers decode v5
/// frames as `unknownType` and fall through to their default branch.
public let bridgeSchemaVersion: Int = 5

/// Default count of trailing messages the server returns on
/// `openChat(limit:)` when the client opts into pagination. 60 covers
/// the last ~6-10 turns including their tool-call timelines and inline
/// attachments without burning the first paint on a big chat. Older
/// pages stream in via `loadOlderMessages` as the user scrolls up.
public let bridgeInitialPageLimit: Int = 60

/// Page size for each `loadOlderMessages` request fired by the client
/// after the user scrolls near the top of the transcript. Smaller than
/// the initial batch because (a) the user already saw the recent
/// turns, (b) older history is the long tail and we want each pull to
/// stay under ~300ms over LAN even when turns carry heavy timelines.
public let bridgeOlderPageLimit: Int = 40

/// Kind of client speaking on a session. Affects which frame types the
/// server is willing to dispatch:
///
/// - `.ios` is the read-mostly mobile companion: list/open chats and
///   send prompts, but not the chat-mutation grab-bag.
/// - `.desktop` is the macOS GUI talking to the LaunchAgent daemon. It
///   gets the full surface (edit, archive, pin, branch switch, project
///   selection, pairing token issuance, auth coordinator, etc.).
///
/// Old v1 iPhones don't send a `clientKind`; the server treats absent
/// as `.ios` so they keep working unchanged.
public enum ClientKind: String, Codable, Equatable, Sendable {
    case ios
    case desktop
}

public struct BridgeFrame: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let body: BridgeBody

    public init(_ body: BridgeBody, schemaVersion: Int = bridgeSchemaVersion) {
        self.schemaVersion = schemaVersion
        self.body = body
    }

    private enum TopKeys: String, CodingKey {
        case schemaVersion
        case type
    }

    public init(from decoder: Decoder) throws {
        let top = try decoder.container(keyedBy: TopKeys.self)
        self.schemaVersion = try top.decode(Int.self, forKey: .schemaVersion)
        let type = try top.decode(String.self, forKey: .type)
        self.body = try BridgeBody.decode(type: type, from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        var top = encoder.container(keyedBy: TopKeys.self)
        try top.encode(schemaVersion, forKey: .schemaVersion)
        try top.encode(body.typeTag, forKey: .type)
        try body.encodePayload(to: encoder)
    }
}

/// All discriminated frame bodies. Wire format is flat: every frame
/// carries `schemaVersion`, `type`, and the payload fields at the top
/// level (no `payload` envelope) so log lines stay readable.
public enum BridgeBody: Equatable, Sendable {
    // MARK: - v1 outbound (iPhone -> Mac)
    case auth(token: String, deviceName: String?, clientKind: ClientKind?)
    case listChats
    /// Open a chat for streaming. `limit` is optional: when set, the
    /// server replies with the trailing N messages and a `hasMore`
    /// flag so the client can lazily fetch older history via
    /// `loadOlderMessages`. Old clients omit the field and receive the
    /// full transcript like before; old servers receiving a frame with
    /// `limit` ignore it because the field decodes via `decodeIfPresent`.
    case openChat(chatId: String, limit: Int?)
    /// Pull a window of older messages anchored at the oldest message
    /// the client currently holds. `beforeMessageId` is exclusive
    /// (clients have it already), `limit` is how many earlier rows to
    /// fetch. Server replies with `messagesPage`.
    case loadOlderMessages(chatId: String, beforeMessageId: String, limit: Int)
    /// Carries optional inline attachments alongside the prompt. The
    /// daemon writes each one to a turn-scoped temp file and forwards
    /// the resulting paths to Codex as `localImage` user input items.
    /// Old peers that don't know about attachments omit the field; old
    /// servers receiving a frame with attachments fall back to text
    /// because the field is decoded with `decodeIfPresent ?? []`.
    case sendPrompt(chatId: String, text: String, attachments: [WireAttachment])
    /// New conversation kicked off from the iPhone FAB. The client
    /// pre-mints the UUID so it can route to the chat detail screen
    /// before the round trip lands; the Mac creates a chat with that
    /// exact id, appends the user message, and runs the turn. The bus
    /// auto-subscribes the new id so streaming deltas flow back without
    /// an extra `openChat`.
    case newChat(chatId: String, text: String, attachments: [WireAttachment])
    /// Stop the active turn for `chatId` if any. Mirrors the macOS
    /// composer's stop button: marks the turn interrupted, clears
    /// `hasActiveTurn` on the chat, and asks the backend to cancel.
    /// No-op when the chat has no in-flight turn.
    case interruptTurn(chatId: String)

    // MARK: - v1 inbound (Mac -> iPhone)
    case authOk(macName: String?)
    case authFailed(reason: String)
    case versionMismatch(serverVersion: Int)
    case chatsSnapshot(chats: [WireChat])
    case chatUpdated(chat: WireChat)
    /// Replace the client's view of a chat with the server's. `hasMore`
    /// is optional and only populated when the server honoured a paged
    /// `openChat` (`limit != nil`); a `nil` value means "old server
    /// path, no pagination metadata, treat as no older history". When
    /// the client receives this it MUST reset its pagination state for
    /// `chatId` because every snapshot is the new baseline.
    case messagesSnapshot(chatId: String, messages: [WireMessage], hasMore: Bool?)
    /// Reply to `loadOlderMessages`. `messages` is the slice prior to
    /// the cursor (chronological order, oldest first); `hasMore` is
    /// `false` when the slice reaches the start of the chat.
    case messagesPage(chatId: String, messages: [WireMessage], hasMore: Bool)
    case messageAppended(chatId: String, message: WireMessage)
    /// Carries the full current state of the message (content +
    /// reasoning) every tick, not deltas. The iPhone replaces. Trades
    /// a few extra KB on LAN for no append/delta correctness bugs.
    case messageStreaming(
        chatId: String,
        messageId: String,
        content: String,
        reasoningText: String,
        finished: Bool
    )
    case errorEvent(code: String, message: String)

    // MARK: - v2 outbound (desktop client -> daemon)
    /// Edit a prompt in place and re-run the turn. `chatId` is the
    /// chat, `messageId` is the user message being rewritten, `text`
    /// is the new content. Daemon truncates the rollout at this turn,
    /// applies the new prompt, and re-streams.
    case editPrompt(chatId: String, messageId: String, text: String)
    /// Toggle the archived flag. Sticks across relaunches because the
    /// archive state lives in the GRDB database the daemon owns.
    case archiveChat(chatId: String)
    case unarchiveChat(chatId: String)
    /// Toggle the pinned flag.
    case pinChat(chatId: String)
    case unpinChat(chatId: String)
    /// Rename a chat. Daemon writes the new name to the runtime
    /// (`thread/name/set` JSON-RPC against Codex) and echoes the
    /// updated `WireChat` back via `chatUpdated` so every other
    /// connected client sees the new title.
    case renameChat(chatId: String, title: String)
    /// Ask the daemon for a fresh pairing payload (token + QR JSON).
    /// Used by `PairWindowView` in the GUI.
    case pairingStart
    /// Ask the daemon for the current list of projects derived from
    /// chats + manual additions. Reply is `projectsSnapshot`.
    case listProjects
    /// Ask the daemon to read a text file off disk and ship its
    /// contents back so the iPhone can render the same Markdown / raw
    /// preview the Mac panel offers when tapping a changed-file pill.
    /// Path is resolved as an absolute filesystem path on the Mac.
    /// Reply is `fileSnapshot`.
    case readFile(path: String)

    // MARK: - v2 inbound (daemon -> desktop client)
    /// Reply to `pairingStart`. The QR is what the iPhone scans; the
    /// bearer is what the daemon will accept on the next `auth` frame
    /// from a fresh iPhone.
    case pairingPayload(qrJson: String, bearer: String)
    /// Reply to `listProjects`.
    case projectsSnapshot(projects: [WireProject])
    /// Reply to `readFile`. Either `content` is set with the UTF-8
    /// text of the file (and `isMarkdown` says how to render it), or
    /// `error` carries a short reason string suitable for display
    /// ("File not found", "Couldn't decode file as text", etc.).
    case fileSnapshot(path: String, content: String?, isMarkdown: Bool, error: String?)

    /// Voice-to-text request from the iPhone companion. The audio blob
    /// travels base64-encoded inline (same shape as `WireAttachment`)
    /// because the bridge transport is text-only WebSocket frames; for a
    /// few seconds of compressed audio (m4a/AAC) it stays well under any
    /// practical size. `requestId` is a client-minted correlation token
    /// so the iPhone can match the answer to the right pending request
    /// without needing a per-chat queue. `language` is an optional
    /// Whisper language code (e.g. "en", "es"); `nil` means auto-detect.
    case transcribeAudio(requestId: String, audioBase64: String, mimeType: String, language: String?)
    /// Reply to `transcribeAudio`. On success `text` is the transcript
    /// and `errorMessage` is nil. On failure (decode error, no model
    /// downloaded, transcription crash) `text` is empty and
    /// `errorMessage` carries a short reason for display.
    case transcriptionResult(requestId: String, text: String, errorMessage: String?)

    /// Ask the daemon for the bytes of a previously-stored voice clip.
    /// `audioId` is the value the daemon put into the user message's
    /// `audioRef.id`. Reply is `audioSnapshot`. Clients are expected to
    /// cache the answer locally; the daemon's storage is the canonical
    /// copy but the round trip is wasteful on every replay.
    case requestAudio(audioId: String)
    /// Reply to `requestAudio`. On success `audioBase64` carries the
    /// raw bytes (m4a/AAC unless the user uploaded something else) and
    /// `errorMessage` is nil. On failure (no longer on disk, never
    /// existed) `audioBase64` is nil and `errorMessage` is a short
    /// reason like "Audio no longer available".
    case audioSnapshot(audioId: String, audioBase64: String?, mimeType: String?, errorMessage: String?)

    /// Ask the daemon for the bytes of a generated image written by
    /// Codex's `imagegen` tool (or any image the assistant referenced
    /// by absolute path inside `~/.codex/generated_images`). The daemon
    /// validates the path stays under that root and rejects anything
    /// else with a "denied" error. `path` is the absolute filesystem
    /// path on the Mac. Reply is `generatedImageSnapshot`.
    case requestGeneratedImage(path: String)
    /// Reply to `requestGeneratedImage`. On success `dataBase64` carries
    /// the raw PNG (or whatever the file actually is, declared via
    /// `mimeType`) and `errorMessage` is nil. On failure (file missing,
    /// path outside the sandbox, decode error) `dataBase64` is nil and
    /// `errorMessage` is a short reason for display.
    case generatedImageSnapshot(path: String, dataBase64: String?, mimeType: String?, errorMessage: String?)

    /// Host-side bootstrap state. `state` is one of `booting`,
    /// `syncing`, `ready`, `error`. `chatCount` is the size of the
    /// chats list as the host currently knows it (useful while in
    /// `ready` to confirm the snapshot is non-empty by design, not by
    /// race). `message` carries a short reason when state is `error`,
    /// or a hint for `syncing` (e.g. "loading rollouts"); nil otherwise.
    /// Sent immediately after `authOk` and again whenever the host
    /// transitions, so a peer that connected during boot sees the
    /// `syncing → ready` flip without polling.
    case bridgeState(state: String, chatCount: Int, message: String?)

    // MARK: - v5 outbound (desktop client -> daemon)
    /// Ask the daemon for the current rate-limits snapshot. Reply is
    /// `rateLimitsSnapshot`. The macOS GUI sends this once after
    /// `authOk` so the "Remaining usage limits" widget hydrates as
    /// soon as the desktop client connects to the daemon. iPhone
    /// clients never emit it.
    case requestRateLimits

    // MARK: - v5 inbound (daemon -> desktop client)
    /// Reply to `requestRateLimits` and also the shape of the push
    /// the daemon sends when Codex emits `account/rateLimits/updated`.
    /// `snapshot` is the general-account view (the same field Codex
    /// returns at `rateLimits` top level); `byLimitId` is the
    /// per-bucket map keyed by metered `limit_id` (e.g. `"codex"`,
    /// `"codex_<model>"`). Both are optional: `snapshot` is nil while
    /// the daemon is still booting and hasn't pulled the first read,
    /// `byLimitId` is empty when the backend doesn't surface
    /// per-bucket data.
    case rateLimitsSnapshot(snapshot: WireRateLimitSnapshot?, byLimitId: [String: WireRateLimitSnapshot])
    /// Push from the daemon every time Codex notifies a fresh
    /// `account/rateLimits/updated`. Same shape as `rateLimitsSnapshot`
    /// so clients can apply both through the same code path.
    case rateLimitsUpdated(snapshot: WireRateLimitSnapshot?, byLimitId: [String: WireRateLimitSnapshot])

    fileprivate var typeTag: String {
        switch self {
        case .auth:               return "auth"
        case .listChats:          return "listChats"
        case .openChat:           return "openChat"
        case .loadOlderMessages:  return "loadOlderMessages"
        case .sendPrompt:         return "sendPrompt"
        case .newChat:            return "newChat"
        case .interruptTurn:      return "interruptTurn"
        case .authOk:             return "authOk"
        case .authFailed:         return "authFailed"
        case .versionMismatch:    return "versionMismatch"
        case .chatsSnapshot:      return "chatsSnapshot"
        case .chatUpdated:        return "chatUpdated"
        case .messagesSnapshot:   return "messagesSnapshot"
        case .messagesPage:       return "messagesPage"
        case .messageAppended:    return "messageAppended"
        case .messageStreaming:   return "messageStreaming"
        case .errorEvent:         return "errorEvent"
        case .editPrompt:         return "editPrompt"
        case .archiveChat:        return "archiveChat"
        case .unarchiveChat:      return "unarchiveChat"
        case .pinChat:            return "pinChat"
        case .unpinChat:          return "unpinChat"
        case .renameChat:         return "renameChat"
        case .pairingStart:       return "pairingStart"
        case .pairingPayload:     return "pairingPayload"
        case .listProjects:       return "listProjects"
        case .projectsSnapshot:   return "projectsSnapshot"
        case .readFile:           return "readFile"
        case .fileSnapshot:       return "fileSnapshot"
        case .transcribeAudio:    return "transcribeAudio"
        case .transcriptionResult: return "transcriptionResult"
        case .requestAudio:       return "requestAudio"
        case .audioSnapshot:      return "audioSnapshot"
        case .requestGeneratedImage: return "requestGeneratedImage"
        case .generatedImageSnapshot: return "generatedImageSnapshot"
        case .bridgeState:        return "bridgeState"
        case .requestRateLimits:  return "requestRateLimits"
        case .rateLimitsSnapshot: return "rateLimitsSnapshot"
        case .rateLimitsUpdated:  return "rateLimitsUpdated"
        }
    }

    private enum FlatKeys: String, CodingKey {
        case token, deviceName, clientKind
        case chatId, text, messageId, title
        case macName, reason, serverVersion
        case chats, chat, messages, message
        case content, reasoningText, finished
        case code
        case qrJson, bearer
        case projects
        case path, isMarkdown, error
        case attachments
        case requestId, audioBase64, mimeType, language, errorMessage
        case audioId
        case dataBase64
        case limit, beforeMessageId, hasMore
        case state, chatCount
        case rateLimits, rateLimitsByLimitId
    }

    fileprivate func encodePayload(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: FlatKeys.self)
        switch self {
        case .auth(let token, let deviceName, let clientKind):
            try c.encode(token, forKey: .token)
            try c.encodeIfPresent(deviceName, forKey: .deviceName)
            try c.encodeIfPresent(clientKind, forKey: .clientKind)
        case .listChats:
            break
        case .openChat(let chatId, let limit):
            try c.encode(chatId, forKey: .chatId)
            try c.encodeIfPresent(limit, forKey: .limit)
        case .loadOlderMessages(let chatId, let beforeMessageId, let limit):
            try c.encode(chatId, forKey: .chatId)
            try c.encode(beforeMessageId, forKey: .beforeMessageId)
            try c.encode(limit, forKey: .limit)
        case .sendPrompt(let chatId, let text, let attachments):
            try c.encode(chatId, forKey: .chatId)
            try c.encode(text, forKey: .text)
            if !attachments.isEmpty {
                try c.encode(attachments, forKey: .attachments)
            }
        case .newChat(let chatId, let text, let attachments):
            try c.encode(chatId, forKey: .chatId)
            try c.encode(text, forKey: .text)
            if !attachments.isEmpty {
                try c.encode(attachments, forKey: .attachments)
            }
        case .interruptTurn(let chatId):
            try c.encode(chatId, forKey: .chatId)
        case .authOk(let macName):
            try c.encodeIfPresent(macName, forKey: .macName)
        case .authFailed(let reason):
            try c.encode(reason, forKey: .reason)
        case .versionMismatch(let serverVersion):
            try c.encode(serverVersion, forKey: .serverVersion)
        case .chatsSnapshot(let chats):
            try c.encode(chats, forKey: .chats)
        case .chatUpdated(let chat):
            try c.encode(chat, forKey: .chat)
        case .messagesSnapshot(let chatId, let messages, let hasMore):
            try c.encode(chatId, forKey: .chatId)
            try c.encode(messages, forKey: .messages)
            try c.encodeIfPresent(hasMore, forKey: .hasMore)
        case .messagesPage(let chatId, let messages, let hasMore):
            try c.encode(chatId, forKey: .chatId)
            try c.encode(messages, forKey: .messages)
            try c.encode(hasMore, forKey: .hasMore)
        case .messageAppended(let chatId, let message):
            try c.encode(chatId, forKey: .chatId)
            try c.encode(message, forKey: .message)
        case .messageStreaming(let chatId, let messageId, let content, let reasoningText, let finished):
            try c.encode(chatId, forKey: .chatId)
            try c.encode(messageId, forKey: .messageId)
            try c.encode(content, forKey: .content)
            try c.encode(reasoningText, forKey: .reasoningText)
            try c.encode(finished, forKey: .finished)
        case .errorEvent(let code, let message):
            try c.encode(code, forKey: .code)
            try c.encode(message, forKey: .message)
        case .editPrompt(let chatId, let messageId, let text):
            try c.encode(chatId, forKey: .chatId)
            try c.encode(messageId, forKey: .messageId)
            try c.encode(text, forKey: .text)
        case .archiveChat(let chatId), .unarchiveChat(let chatId),
             .pinChat(let chatId), .unpinChat(let chatId):
            try c.encode(chatId, forKey: .chatId)
        case .renameChat(let chatId, let title):
            try c.encode(chatId, forKey: .chatId)
            try c.encode(title, forKey: .title)
        case .pairingStart, .listProjects:
            break
        case .pairingPayload(let qrJson, let bearer):
            try c.encode(qrJson, forKey: .qrJson)
            try c.encode(bearer, forKey: .bearer)
        case .projectsSnapshot(let projects):
            try c.encode(projects, forKey: .projects)
        case .readFile(let path):
            try c.encode(path, forKey: .path)
        case .fileSnapshot(let path, let content, let isMarkdown, let error):
            try c.encode(path, forKey: .path)
            try c.encodeIfPresent(content, forKey: .content)
            try c.encode(isMarkdown, forKey: .isMarkdown)
            try c.encodeIfPresent(error, forKey: .error)
        case .transcribeAudio(let requestId, let audioBase64, let mimeType, let language):
            try c.encode(requestId, forKey: .requestId)
            try c.encode(audioBase64, forKey: .audioBase64)
            try c.encode(mimeType, forKey: .mimeType)
            try c.encodeIfPresent(language, forKey: .language)
        case .transcriptionResult(let requestId, let text, let errorMessage):
            try c.encode(requestId, forKey: .requestId)
            try c.encode(text, forKey: .text)
            try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
        case .requestAudio(let audioId):
            try c.encode(audioId, forKey: .audioId)
        case .audioSnapshot(let audioId, let audioBase64, let mimeType, let errorMessage):
            try c.encode(audioId, forKey: .audioId)
            try c.encodeIfPresent(audioBase64, forKey: .audioBase64)
            try c.encodeIfPresent(mimeType, forKey: .mimeType)
            try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
        case .requestGeneratedImage(let path):
            try c.encode(path, forKey: .path)
        case .generatedImageSnapshot(let path, let dataBase64, let mimeType, let errorMessage):
            try c.encode(path, forKey: .path)
            try c.encodeIfPresent(dataBase64, forKey: .dataBase64)
            try c.encodeIfPresent(mimeType, forKey: .mimeType)
            try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
        case .bridgeState(let state, let chatCount, let message):
            try c.encode(state, forKey: .state)
            try c.encode(chatCount, forKey: .chatCount)
            try c.encodeIfPresent(message, forKey: .message)
        case .requestRateLimits:
            break
        case .rateLimitsSnapshot(let snapshot, let byLimitId):
            try c.encodeIfPresent(snapshot, forKey: .rateLimits)
            try c.encode(byLimitId, forKey: .rateLimitsByLimitId)
        case .rateLimitsUpdated(let snapshot, let byLimitId):
            try c.encodeIfPresent(snapshot, forKey: .rateLimits)
            try c.encode(byLimitId, forKey: .rateLimitsByLimitId)
        }
    }

    fileprivate static func decode(type: String, from decoder: Decoder) throws -> BridgeBody {
        let c = try decoder.container(keyedBy: FlatKeys.self)
        switch type {
        case "auth":
            return .auth(
                token: try c.decode(String.self, forKey: .token),
                deviceName: try c.decodeIfPresent(String.self, forKey: .deviceName),
                clientKind: try c.decodeIfPresent(ClientKind.self, forKey: .clientKind)
            )
        case "listChats":
            return .listChats
        case "openChat":
            return .openChat(
                chatId: try c.decode(String.self, forKey: .chatId),
                limit: try c.decodeIfPresent(Int.self, forKey: .limit)
            )
        case "loadOlderMessages":
            return .loadOlderMessages(
                chatId: try c.decode(String.self, forKey: .chatId),
                beforeMessageId: try c.decode(String.self, forKey: .beforeMessageId),
                limit: try c.decode(Int.self, forKey: .limit)
            )
        case "sendPrompt":
            return .sendPrompt(
                chatId: try c.decode(String.self, forKey: .chatId),
                text: try c.decode(String.self, forKey: .text),
                attachments: try c.decodeIfPresent([WireAttachment].self, forKey: .attachments) ?? []
            )
        case "newChat":
            return .newChat(
                chatId: try c.decode(String.self, forKey: .chatId),
                text: try c.decode(String.self, forKey: .text),
                attachments: try c.decodeIfPresent([WireAttachment].self, forKey: .attachments) ?? []
            )
        case "interruptTurn":
            return .interruptTurn(chatId: try c.decode(String.self, forKey: .chatId))
        case "authOk":
            return .authOk(macName: try c.decodeIfPresent(String.self, forKey: .macName))
        case "authFailed":
            return .authFailed(reason: try c.decode(String.self, forKey: .reason))
        case "versionMismatch":
            return .versionMismatch(serverVersion: try c.decode(Int.self, forKey: .serverVersion))
        case "chatsSnapshot":
            return .chatsSnapshot(chats: try c.decode([WireChat].self, forKey: .chats))
        case "chatUpdated":
            return .chatUpdated(chat: try c.decode(WireChat.self, forKey: .chat))
        case "messagesSnapshot":
            return .messagesSnapshot(
                chatId: try c.decode(String.self, forKey: .chatId),
                messages: try c.decode([WireMessage].self, forKey: .messages),
                hasMore: try c.decodeIfPresent(Bool.self, forKey: .hasMore)
            )
        case "messagesPage":
            return .messagesPage(
                chatId: try c.decode(String.self, forKey: .chatId),
                messages: try c.decode([WireMessage].self, forKey: .messages),
                hasMore: try c.decode(Bool.self, forKey: .hasMore)
            )
        case "messageAppended":
            return .messageAppended(
                chatId: try c.decode(String.self, forKey: .chatId),
                message: try c.decode(WireMessage.self, forKey: .message)
            )
        case "messageStreaming":
            return .messageStreaming(
                chatId: try c.decode(String.self, forKey: .chatId),
                messageId: try c.decode(String.self, forKey: .messageId),
                content: try c.decode(String.self, forKey: .content),
                reasoningText: try c.decode(String.self, forKey: .reasoningText),
                finished: try c.decode(Bool.self, forKey: .finished)
            )
        case "errorEvent":
            return .errorEvent(
                code: try c.decode(String.self, forKey: .code),
                message: try c.decode(String.self, forKey: .message)
            )
        case "editPrompt":
            return .editPrompt(
                chatId: try c.decode(String.self, forKey: .chatId),
                messageId: try c.decode(String.self, forKey: .messageId),
                text: try c.decode(String.self, forKey: .text)
            )
        case "archiveChat":
            return .archiveChat(chatId: try c.decode(String.self, forKey: .chatId))
        case "unarchiveChat":
            return .unarchiveChat(chatId: try c.decode(String.self, forKey: .chatId))
        case "pinChat":
            return .pinChat(chatId: try c.decode(String.self, forKey: .chatId))
        case "unpinChat":
            return .unpinChat(chatId: try c.decode(String.self, forKey: .chatId))
        case "renameChat":
            return .renameChat(
                chatId: try c.decode(String.self, forKey: .chatId),
                title: try c.decode(String.self, forKey: .title)
            )
        case "pairingStart":
            return .pairingStart
        case "pairingPayload":
            return .pairingPayload(
                qrJson: try c.decode(String.self, forKey: .qrJson),
                bearer: try c.decode(String.self, forKey: .bearer)
            )
        case "listProjects":
            return .listProjects
        case "projectsSnapshot":
            return .projectsSnapshot(projects: try c.decode([WireProject].self, forKey: .projects))
        case "readFile":
            return .readFile(path: try c.decode(String.self, forKey: .path))
        case "fileSnapshot":
            return .fileSnapshot(
                path: try c.decode(String.self, forKey: .path),
                content: try c.decodeIfPresent(String.self, forKey: .content),
                isMarkdown: try c.decodeIfPresent(Bool.self, forKey: .isMarkdown) ?? false,
                error: try c.decodeIfPresent(String.self, forKey: .error)
            )
        case "transcribeAudio":
            return .transcribeAudio(
                requestId: try c.decode(String.self, forKey: .requestId),
                audioBase64: try c.decode(String.self, forKey: .audioBase64),
                mimeType: try c.decode(String.self, forKey: .mimeType),
                language: try c.decodeIfPresent(String.self, forKey: .language)
            )
        case "transcriptionResult":
            return .transcriptionResult(
                requestId: try c.decode(String.self, forKey: .requestId),
                text: try c.decode(String.self, forKey: .text),
                errorMessage: try c.decodeIfPresent(String.self, forKey: .errorMessage)
            )
        case "requestAudio":
            return .requestAudio(audioId: try c.decode(String.self, forKey: .audioId))
        case "audioSnapshot":
            return .audioSnapshot(
                audioId: try c.decode(String.self, forKey: .audioId),
                audioBase64: try c.decodeIfPresent(String.self, forKey: .audioBase64),
                mimeType: try c.decodeIfPresent(String.self, forKey: .mimeType),
                errorMessage: try c.decodeIfPresent(String.self, forKey: .errorMessage)
            )
        case "requestGeneratedImage":
            return .requestGeneratedImage(path: try c.decode(String.self, forKey: .path))
        case "generatedImageSnapshot":
            return .generatedImageSnapshot(
                path: try c.decode(String.self, forKey: .path),
                dataBase64: try c.decodeIfPresent(String.self, forKey: .dataBase64),
                mimeType: try c.decodeIfPresent(String.self, forKey: .mimeType),
                errorMessage: try c.decodeIfPresent(String.self, forKey: .errorMessage)
            )
        case "bridgeState":
            return .bridgeState(
                state: try c.decode(String.self, forKey: .state),
                chatCount: try c.decode(Int.self, forKey: .chatCount),
                message: try c.decodeIfPresent(String.self, forKey: .message)
            )
        case "requestRateLimits":
            return .requestRateLimits
        case "rateLimitsSnapshot":
            return .rateLimitsSnapshot(
                snapshot: try c.decodeIfPresent(WireRateLimitSnapshot.self, forKey: .rateLimits),
                byLimitId: try c.decodeIfPresent([String: WireRateLimitSnapshot].self, forKey: .rateLimitsByLimitId) ?? [:]
            )
        case "rateLimitsUpdated":
            return .rateLimitsUpdated(
                snapshot: try c.decodeIfPresent(WireRateLimitSnapshot.self, forKey: .rateLimits),
                byLimitId: try c.decodeIfPresent([String: WireRateLimitSnapshot].self, forKey: .rateLimitsByLimitId) ?? [:]
            )
        default:
            throw BridgeDecodingError.unknownType(type)
        }
    }
}

public enum BridgeDecodingError: Error, Equatable {
    case unknownType(String)
}

/// Bootstrap state of the host that drives a `BridgeServer`. The
/// daemon flips through `booting → syncing → ready` while it spawns
/// the Codex backend, runs `initialize`, and pulls the first
/// `thread/list`. The in-process GUI server sits permanently at
/// `.ready` because it shares process state with the chat owner.
public enum BridgeRuntimeState: Equatable, Sendable {
    /// Daemon process started, host wired up, but the Codex backend
    /// subprocess hasn't been launched yet.
    case booting
    /// Codex backend running and `initialize` succeeded; we're now
    /// pulling the chat list / hydrating any cached state.
    case syncing
    /// First chat snapshot has been published to the bus. Subsequent
    /// snapshots flow through the throttled chat publisher; clients
    /// are expected to render the chats list now.
    case ready
    /// Bootstrap failed. The string is short and user-facing
    /// (surfaced as the "fail" line in `clawix up` and as an error
    /// banner on iOS). Hosts may transition back to `.syncing` after
    /// a retry.
    case error(String)

    public var wireTag: String {
        switch self {
        case .booting: return "booting"
        case .syncing: return "syncing"
        case .ready:   return "ready"
        case .error:   return "error"
        }
    }

    public var errorMessage: String? {
        if case .error(let message) = self { return message }
        return nil
    }
}

// MARK: - Rate limits wire types

/// Single rate-limit window (primary or secondary). Mirrors the shape
/// Codex returns under `account/rateLimits/read.rateLimits.primary`.
/// `windowDurationMins` and `resetsAt` are optional because older
/// daemons / future buckets may omit them.
public struct WireRateLimitWindow: Codable, Equatable, Sendable {
    public let usedPercent: Int
    public let resetsAt: Int64?
    public let windowDurationMins: Int64?

    public init(usedPercent: Int, resetsAt: Int64?, windowDurationMins: Int64?) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.windowDurationMins = windowDurationMins
    }
}

/// Credits balance for the account (overage / pay-per-use). The GUI's
/// Settings → Usage page renders a row when this is non-nil.
public struct WireCreditsSnapshot: Codable, Equatable, Sendable {
    public let hasCredits: Bool
    public let unlimited: Bool
    public let balance: String?

    public init(hasCredits: Bool, unlimited: Bool, balance: String?) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.balance = balance
    }
}

/// One bucket of rate-limit state. The general account view ships with
/// `limitId == "codex"` (or nil); per-model buckets carry their own id
/// (e.g. `"codex_<spark>"`) and a human label in `limitName`.
public struct WireRateLimitSnapshot: Codable, Equatable, Sendable {
    public let primary: WireRateLimitWindow?
    public let secondary: WireRateLimitWindow?
    public let credits: WireCreditsSnapshot?
    public let limitId: String?
    public let limitName: String?

    public init(
        primary: WireRateLimitWindow?,
        secondary: WireRateLimitWindow?,
        credits: WireCreditsSnapshot?,
        limitId: String?,
        limitName: String?
    ) {
        self.primary = primary
        self.secondary = secondary
        self.credits = credits
        self.limitId = limitId
        self.limitName = limitName
    }
}

public enum BridgeCoder {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func encode(_ frame: BridgeFrame) throws -> Data {
        try encoder.encode(frame)
    }

    public static func decode(_ data: Data) throws -> BridgeFrame {
        try decoder.decode(BridgeFrame.self, from: data)
    }
}
