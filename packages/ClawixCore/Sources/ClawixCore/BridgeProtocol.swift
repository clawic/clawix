import Foundation

/// Wire-format version exchanged in every frame. Clients refuse to talk to a
/// peer reporting a different `schemaVersion` and surface an "update Clawix"
/// empty state.
public let bridgeSchemaVersion: Int = 1

/// Default count of trailing messages the server returns on
/// `openSession(limit:)` when the client opts into pagination. 60 covers
/// the last ~6-10 turns including their tool-call timelines and inline
/// attachments without burning the first paint on a big chat. Earlier
/// pages stream in via `loadOlderMessages` as the user scrolls up.
public let bridgeInitialPageLimit: Int = 60

/// Page size for each `loadOlderMessages` request fired by the client
/// after the user scrolls near the top of the transcript. Smaller than
/// the initial batch because (a) the user already saw the recent
/// turns, (b) earlier history is the long tail and we want each pull to
/// stay under ~300ms over LAN even when turns carry heavy timelines.
public let bridgeOlderPageLimit: Int = 40

/// Kind of client speaking on a session. Affects which frame types the
/// server is willing to dispatch:
///
/// - `.companion` is the read-mostly companion role: list/open sessions
///   and send messages, but not the session-mutation grab-bag.
/// - `.desktop` is the macOS GUI talking to the LaunchAgent daemon. It
///   gets the full surface (edit, archive, pin, branch switch, project
///   selection, pairing token issuance, auth coordinator, etc.).
///
/// Clients send `clientKind` as a role, not as a platform identifier.
public enum ClientKind: String, Codable, Equatable, Sendable {
    case companion
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
    // MARK: - Outbound (iPhone -> Mac)
    case auth(
        token: String,
        deviceName: String?,
        clientKind: ClientKind,
        clientId: String,
        installationId: String,
        deviceId: String
    )
    case listSessions
    /// Open a chat for streaming. `limit` is optional: when set, the
    /// server replies with the trailing N messages and a `hasMore`
    /// flag so the client can lazily fetch earlier history via
    /// `loadOlderMessages`. `limit == nil` is the current v1 request
    /// for the whole transcript.
    case openSession(sessionId: String, limit: Int?)
    /// Pull a window of earlier messages anchored at the oldest message
    /// the client currently holds. `beforeMessageId` is exclusive
    /// (clients have it already), `limit` is how many earlier rows to
    /// fetch. Server replies with `messagesPage`.
    case loadOlderMessages(sessionId: String, beforeMessageId: String, limit: Int)
    /// Carries optional inline attachments alongside the prompt. The
    /// daemon writes each one to a turn-scoped temp file and forwards
    /// the resulting paths to Codex as `localImage` user input items.
    /// Empty attachment lists may omit the field; attachment entries
    /// themselves must carry an explicit `kind`.
    case sendMessage(sessionId: String, text: String, attachments: [WireAttachment])
    /// New conversation kicked off from the iPhone FAB. The client
    /// pre-mints the UUID so it can route to the chat detail screen
    /// before the round trip lands; the Mac creates a chat with that
    /// exact id, appends the user message, and runs the turn. The bus
    /// auto-subscribes the new id so streaming deltas flow back without
    /// an extra `openSession`.
    case newSession(sessionId: String, text: String, attachments: [WireAttachment])
    /// Stop the active turn for `sessionId` if any. Mirrors the macOS
    /// composer's stop button: marks the turn interrupted, clears
    /// `hasActiveTurn` on the chat, and asks the backend to cancel.
    /// No-op when the chat has no in-flight turn.
    case interruptTurn(sessionId: String)

    // MARK: - Inbound (Mac -> iPhone)
    case authOk(hostDisplayName: String?)
    case authFailed(reason: String)
    case versionMismatch(serverVersion: Int)
    case sessionsSnapshot(sessions: [WireSession])
    case sessionUpdated(session: WireSession)
    /// Replace the client's view of a chat with the server's. `hasMore`
    /// is optional: `nil` means this snapshot is the complete transcript.
    /// When the client receives this it MUST reset its pagination state
    /// for `sessionId` because every snapshot is the new baseline.
    case messagesSnapshot(sessionId: String, messages: [WireMessage], hasMore: Bool?)
    /// Reply to `loadOlderMessages`. `messages` is the slice prior to
    /// the cursor (chronological order, oldest first); `hasMore` is
    /// `false` when the slice reaches the start of the chat.
    case messagesPage(sessionId: String, messages: [WireMessage], hasMore: Bool)
    case messageAppended(sessionId: String, message: WireMessage)
    /// Carries the full current state of the message (content +
    /// reasoning) every tick, not deltas. The iPhone replaces. Trades
    /// a few extra KB on LAN for no append/delta correctness bugs.
    case messageStreaming(
        sessionId: String,
        messageId: String,
        content: String,
        reasoningText: String,
        finished: Bool
    )
    case errorEvent(code: String, message: String)

    // MARK: - Desktop control outbound (desktop client -> daemon)
    /// Edit a prompt in place and re-run the turn. `sessionId` is the
    /// chat, `messageId` is the user message being rewritten, `text`
    /// is the new content. Daemon truncates the rollout at this turn,
    /// applies the new prompt, and re-streams.
    case editPrompt(sessionId: String, messageId: String, text: String)
    /// Toggle the archived flag. Sticks across relaunches because the
    /// archive state lives in the GRDB database the daemon owns.
    case archiveSession(sessionId: String)
    case unarchiveSession(sessionId: String)
    /// Toggle the pinned flag.
    case pinSession(sessionId: String)
    case unpinSession(sessionId: String)
    /// Rename a chat. Daemon writes the new name to the runtime
    /// (`thread/name/set` JSON-RPC against Codex) and echoes the
    /// updated `WireSession` back via `sessionUpdated` so every other
    /// connected client sees the new title.
    case renameSession(sessionId: String, title: String)
    /// Ask the daemon for a fresh pairing payload (token + QR JSON).
    /// Used by `PairWindowView` in the GUI.
    case pairingStart
    /// Ask the daemon for the current list of projects derived from
    /// sessions + manual additions. Reply is `projectsSnapshot`.
    case listProjects
    /// Ask the daemon to read a text file off disk and ship its
    /// contents back so the iPhone can render the same Markdown / raw
    /// preview the Mac panel offers when tapping a changed-file pill.
    /// Path is resolved as an absolute filesystem path on the Mac.
    /// Reply is `fileSnapshot`.
    case readFile(path: String)

    // MARK: - Desktop control inbound (daemon -> desktop client)
    /// Reply to `pairingStart`. The QR is what the iPhone scans; the
    /// token is what the daemon will accept on the next `auth` frame
    /// from a fresh iPhone.
    case pairingPayload(qrJson: String, token: String, shortCode: String)
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
    /// sessions list as the host currently knows it (useful while in
    /// `ready` to confirm the snapshot is non-empty by design, not by
    /// race). `message` carries a short reason when state is `error`,
    /// or a hint for `syncing` (e.g. "loading rollouts"); nil otherwise.
    /// Sent immediately after `authOk` and again whenever the host
    /// transitions, so a peer that connected during boot sees the
    /// `syncing → ready` flip without polling.
    case bridgeState(state: String, chatCount: Int, message: String?)

    // MARK: - Rate limits outbound (desktop client -> daemon)
    /// Ask the daemon for the current rate-limits snapshot. Reply is
    /// `rateLimitsSnapshot`. The macOS GUI sends this once after
    /// `authOk` so the "Remaining usage limits" widget hydrates as
    /// soon as the desktop client connects to the daemon. iPhone
    /// clients never emit it.
    case requestRateLimits

    // MARK: - Rate limits inbound (daemon -> desktop client)
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

    // MARK: - Audio catalog outbound (client -> daemon)
    /// Register a new audio asset in the framework's audio catalog and
    /// optionally attach a primary transcript in the same round trip.
    /// Reply is `audioRegisterResult` carrying the inserted asset and
    /// any transcripts the framework wrote.
    case audioRegister(requestId: String, request: WireAudioRegisterRequest)
    /// Attach a transcript to an existing audio asset. Used to back the
    /// re-transcription flow (e.g. retry with a larger Whisper model)
    /// without losing the prior transcripts. `markAsPrimary` flips the
    /// primary atomically.
    case audioAttachTranscript(requestId: String, audioId: String, transcript: WireAudioAttachTranscriptInput)
    /// Pull an asset record plus all its transcripts. Bytes are NOT
    /// included; use `audioGetBytes` for the base64 payload.
    case audioGet(requestId: String, audioId: String, appId: String)
    /// Pull the raw bytes of an asset. Carried inline as base64 in the
    /// reply (`audioBytesResult`). Current v1 uses inline base64; a
    /// future same-machine optimization can add a path+token handoff.
    case audioGetBytes(requestId: String, audioId: String, appId: String)
    /// List assets matching the filter. `appId` is required so apps
    /// don't accidentally see each other's audio.
    case audioList(requestId: String, filter: WireAudioListFilter)
    /// Delete an asset by id, scoped by `appId`. Cascades transcripts
    /// and unlinks the blob from disk.
    case audioDelete(requestId: String, audioId: String, appId: String)

    // MARK: - Audio catalog inbound (daemon -> client)
    case audioRegisterResult(requestId: String, asset: WireAudioAssetWithTranscripts?, errorMessage: String?)
    case audioAttachTranscriptResult(requestId: String, transcript: WireAudioTranscript?, errorMessage: String?)
    case audioGetResult(requestId: String, asset: WireAudioAssetWithTranscripts?, errorMessage: String?)
    case audioBytesResult(requestId: String, audioBase64: String?, mimeType: String?, durationMs: Int?, errorMessage: String?)
    case audioListResult(requestId: String, list: WireAudioListResult?, errorMessage: String?)
    case audioDeleteResult(requestId: String, deleted: Bool, errorMessage: String?)

    fileprivate var typeTag: String {
        // Split into base bridge and audio helpers
        // so the Swift type-checker doesn't time out on a single
        // ~70-case switch ("compiler is unable to type-check this
        // expression in reasonable time"). Each helper covers a
        // disjoint set; the dispatcher tries audio -> base.
        if let tag = audioTypeTag { return tag }
        return baseTypeTag
    }

    private var baseTypeTag: String {
        switch self {
        case .auth:               return "auth"
        case .listSessions:          return "listSessions"
        case .openSession:           return "openSession"
        case .loadOlderMessages:  return "loadOlderMessages"
        case .sendMessage:         return "sendMessage"
        case .newSession:            return "newSession"
        case .interruptTurn:      return "interruptTurn"
        case .authOk:             return "authOk"
        case .authFailed:         return "authFailed"
        case .versionMismatch:    return "versionMismatch"
        case .sessionsSnapshot:      return "sessionsSnapshot"
        case .sessionUpdated:        return "sessionUpdated"
        case .messagesSnapshot:   return "messagesSnapshot"
        case .messagesPage:       return "messagesPage"
        case .messageAppended:    return "messageAppended"
        case .messageStreaming:   return "messageStreaming"
        case .errorEvent:         return "errorEvent"
        case .editPrompt:         return "editPrompt"
        case .archiveSession:        return "archiveSession"
        case .unarchiveSession:      return "unarchiveSession"
        case .pinSession:            return "pinSession"
        case .unpinSession:          return "unpinSession"
        case .renameSession:         return "renameSession"
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
        default:
            // Unreachable: every base bridge case is enumerated above
            // and audio cases are handled by `audioTypeTag` before this branch.
            // If a new case is added without updating either helper this
            // will trip in tests, which is the desired behaviour.
            preconditionFailure("BridgeBody.baseTypeTag missing case for \(self)")
        }
    }

    private var audioTypeTag: String? {
        switch self {
        case .audioRegister:               return "audioRegister"
        case .audioAttachTranscript:       return "audioAttachTranscript"
        case .audioGet:                    return "audioGet"
        case .audioGetBytes:               return "audioGetBytes"
        case .audioList:                   return "audioList"
        case .audioDelete:                 return "audioDelete"
        case .audioRegisterResult:         return "audioRegisterResult"
        case .audioAttachTranscriptResult: return "audioAttachTranscriptResult"
        case .audioGetResult:              return "audioGetResult"
        case .audioBytesResult:            return "audioBytesResult"
        case .audioListResult:             return "audioListResult"
        case .audioDeleteResult:           return "audioDeleteResult"
        default:
            return nil
        }
    }

    private enum FlatKeys: String, CodingKey {
        case token, deviceName, clientKind, clientId, installationId, deviceId
        case sessionId, text, messageId, title
        case hostDisplayName, reason, serverVersion
        case sessions, session, messages, message
        case content, reasoningText, finished
        case code
        case qrJson, shortCode
        case projects
        case path, isMarkdown, error
        case attachments
        case requestId, audioBase64, mimeType, language, errorMessage
        case audioId
        case dataBase64
        case limit, beforeMessageId, hasMore
        case state, chatCount
        case rateLimits, rateLimitsByLimitId
        // Audio catalog
        case appId, request, transcript, asset, list, filter, durationMs, deleted
    }

    fileprivate func encodePayload(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: FlatKeys.self)
        // Helpers split by domain so the Swift type-checker doesn't
        // time out on a single ~70-case switch. Try audio -> base.
        if try encodeAudioPayload(into: &c) { return }
        try encodeBasePayload(into: &c)
    }

    private func encodeBasePayload(into c: inout KeyedEncodingContainer<FlatKeys>) throws {
        switch self {
        case .auth(let token, let deviceName, let clientKind, let clientId, let installationId, let deviceId):
            try c.encode(token, forKey: .token)
            try c.encodeIfPresent(deviceName, forKey: .deviceName)
            try c.encode(clientKind, forKey: .clientKind)
            try c.encode(clientId, forKey: .clientId)
            try c.encode(installationId, forKey: .installationId)
            try c.encode(deviceId, forKey: .deviceId)
        case .listSessions:
            break
        case .openSession(let sessionId, let limit):
            try c.encode(sessionId, forKey: .sessionId)
            try c.encodeIfPresent(limit, forKey: .limit)
        case .loadOlderMessages(let sessionId, let beforeMessageId, let limit):
            try c.encode(sessionId, forKey: .sessionId)
            try c.encode(beforeMessageId, forKey: .beforeMessageId)
            try c.encode(limit, forKey: .limit)
        case .sendMessage(let sessionId, let text, let attachments):
            try c.encode(sessionId, forKey: .sessionId)
            try c.encode(text, forKey: .text)
            if !attachments.isEmpty {
                try c.encode(attachments, forKey: .attachments)
            }
        case .newSession(let sessionId, let text, let attachments):
            try c.encode(sessionId, forKey: .sessionId)
            try c.encode(text, forKey: .text)
            if !attachments.isEmpty {
                try c.encode(attachments, forKey: .attachments)
            }
        case .interruptTurn(let sessionId):
            try c.encode(sessionId, forKey: .sessionId)
        case .authOk(let hostDisplayName):
            try c.encodeIfPresent(hostDisplayName, forKey: .hostDisplayName)
        case .authFailed(let reason):
            try c.encode(reason, forKey: .reason)
        case .versionMismatch(let serverVersion):
            try c.encode(serverVersion, forKey: .serverVersion)
        case .sessionsSnapshot(let sessions):
            try c.encode(sessions, forKey: .sessions)
        case .sessionUpdated(let session):
            try c.encode(session, forKey: .session)
        case .messagesSnapshot(let sessionId, let messages, let hasMore):
            try c.encode(sessionId, forKey: .sessionId)
            try c.encode(messages, forKey: .messages)
            try c.encodeIfPresent(hasMore, forKey: .hasMore)
        case .messagesPage(let sessionId, let messages, let hasMore):
            try c.encode(sessionId, forKey: .sessionId)
            try c.encode(messages, forKey: .messages)
            try c.encode(hasMore, forKey: .hasMore)
        case .messageAppended(let sessionId, let message):
            try c.encode(sessionId, forKey: .sessionId)
            try c.encode(message, forKey: .message)
        case .messageStreaming(let sessionId, let messageId, let content, let reasoningText, let finished):
            try c.encode(sessionId, forKey: .sessionId)
            try c.encode(messageId, forKey: .messageId)
            try c.encode(content, forKey: .content)
            try c.encode(reasoningText, forKey: .reasoningText)
            try c.encode(finished, forKey: .finished)
        case .errorEvent(let code, let message):
            try c.encode(code, forKey: .code)
            try c.encode(message, forKey: .message)
        case .editPrompt(let sessionId, let messageId, let text):
            try c.encode(sessionId, forKey: .sessionId)
            try c.encode(messageId, forKey: .messageId)
            try c.encode(text, forKey: .text)
        case .archiveSession(let sessionId), .unarchiveSession(let sessionId),
             .pinSession(let sessionId), .unpinSession(let sessionId):
            try c.encode(sessionId, forKey: .sessionId)
        case .renameSession(let sessionId, let title):
            try c.encode(sessionId, forKey: .sessionId)
            try c.encode(title, forKey: .title)
        case .pairingStart, .listProjects:
            break
        case .pairingPayload(let qrJson, let token, let shortCode):
            try c.encode(qrJson, forKey: .qrJson)
            try c.encode(token, forKey: .token)
            try c.encode(shortCode, forKey: .shortCode)
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
        default:
            // Audio cases are handled in encodeAudioPayload, called before
            // this method by the encodePayload dispatcher. Unknown base
            // cases would be a programming error caught by round-trip tests.
            break
        }
    }

    private func encodeAudioPayload(into c: inout KeyedEncodingContainer<FlatKeys>) throws -> Bool {
        switch self {
        case .audioRegister(let requestId, let request):
            try c.encode(requestId, forKey: .requestId)
            try c.encode(request, forKey: .request)
        case .audioAttachTranscript(let requestId, let audioId, let transcript):
            try c.encode(requestId, forKey: .requestId)
            try c.encode(audioId, forKey: .audioId)
            try c.encode(transcript, forKey: .transcript)
        case .audioGet(let requestId, let audioId, let appId):
            try c.encode(requestId, forKey: .requestId)
            try c.encode(audioId, forKey: .audioId)
            try c.encode(appId, forKey: .appId)
        case .audioGetBytes(let requestId, let audioId, let appId):
            try c.encode(requestId, forKey: .requestId)
            try c.encode(audioId, forKey: .audioId)
            try c.encode(appId, forKey: .appId)
        case .audioList(let requestId, let filter):
            try c.encode(requestId, forKey: .requestId)
            try c.encode(filter, forKey: .filter)
        case .audioDelete(let requestId, let audioId, let appId):
            try c.encode(requestId, forKey: .requestId)
            try c.encode(audioId, forKey: .audioId)
            try c.encode(appId, forKey: .appId)
        case .audioRegisterResult(let requestId, let asset, let errorMessage):
            try c.encode(requestId, forKey: .requestId)
            try c.encodeIfPresent(asset, forKey: .asset)
            try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
        case .audioAttachTranscriptResult(let requestId, let transcript, let errorMessage):
            try c.encode(requestId, forKey: .requestId)
            try c.encodeIfPresent(transcript, forKey: .transcript)
            try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
        case .audioGetResult(let requestId, let asset, let errorMessage):
            try c.encode(requestId, forKey: .requestId)
            try c.encodeIfPresent(asset, forKey: .asset)
            try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
        case .audioBytesResult(let requestId, let audioBase64, let mimeType, let durationMs, let errorMessage):
            try c.encode(requestId, forKey: .requestId)
            try c.encodeIfPresent(audioBase64, forKey: .audioBase64)
            try c.encodeIfPresent(mimeType, forKey: .mimeType)
            try c.encodeIfPresent(durationMs, forKey: .durationMs)
            try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
        case .audioListResult(let requestId, let list, let errorMessage):
            try c.encode(requestId, forKey: .requestId)
            try c.encodeIfPresent(list, forKey: .list)
            try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
        case .audioDeleteResult(let requestId, let deleted, let errorMessage):
            try c.encode(requestId, forKey: .requestId)
            try c.encode(deleted, forKey: .deleted)
            try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
        default:
            return false
        }
        return true
    }

    fileprivate static func decode(type: String, from decoder: Decoder) throws -> BridgeBody {
        let c = try decoder.container(keyedBy: FlatKeys.self)
        // Helpers split by domain. Try audio -> base.
        if let body = try decodeAudio(type: type, from: c) { return body }
        return try decodeBase(type: type, from: c)
    }

    private static func decodeAudio(type: String, from c: KeyedDecodingContainer<FlatKeys>) throws -> BridgeBody? {
        switch type {
        case "audioRegister":
            return .audioRegister(
                requestId: try c.decode(String.self, forKey: .requestId),
                request: try c.decode(WireAudioRegisterRequest.self, forKey: .request)
            )
        case "audioAttachTranscript":
            return .audioAttachTranscript(
                requestId: try c.decode(String.self, forKey: .requestId),
                audioId: try c.decode(String.self, forKey: .audioId),
                transcript: try c.decode(WireAudioAttachTranscriptInput.self, forKey: .transcript)
            )
        case "audioGet":
            return .audioGet(
                requestId: try c.decode(String.self, forKey: .requestId),
                audioId: try c.decode(String.self, forKey: .audioId),
                appId: try c.decode(String.self, forKey: .appId)
            )
        case "audioGetBytes":
            return .audioGetBytes(
                requestId: try c.decode(String.self, forKey: .requestId),
                audioId: try c.decode(String.self, forKey: .audioId),
                appId: try c.decode(String.self, forKey: .appId)
            )
        case "audioList":
            return .audioList(
                requestId: try c.decode(String.self, forKey: .requestId),
                filter: try c.decode(WireAudioListFilter.self, forKey: .filter)
            )
        case "audioDelete":
            return .audioDelete(
                requestId: try c.decode(String.self, forKey: .requestId),
                audioId: try c.decode(String.self, forKey: .audioId),
                appId: try c.decode(String.self, forKey: .appId)
            )
        case "audioRegisterResult":
            return .audioRegisterResult(
                requestId: try c.decode(String.self, forKey: .requestId),
                asset: try c.decodeIfPresent(WireAudioAssetWithTranscripts.self, forKey: .asset),
                errorMessage: try c.decodeIfPresent(String.self, forKey: .errorMessage)
            )
        case "audioAttachTranscriptResult":
            return .audioAttachTranscriptResult(
                requestId: try c.decode(String.self, forKey: .requestId),
                transcript: try c.decodeIfPresent(WireAudioTranscript.self, forKey: .transcript),
                errorMessage: try c.decodeIfPresent(String.self, forKey: .errorMessage)
            )
        case "audioGetResult":
            return .audioGetResult(
                requestId: try c.decode(String.self, forKey: .requestId),
                asset: try c.decodeIfPresent(WireAudioAssetWithTranscripts.self, forKey: .asset),
                errorMessage: try c.decodeIfPresent(String.self, forKey: .errorMessage)
            )
        case "audioBytesResult":
            return .audioBytesResult(
                requestId: try c.decode(String.self, forKey: .requestId),
                audioBase64: try c.decodeIfPresent(String.self, forKey: .audioBase64),
                mimeType: try c.decodeIfPresent(String.self, forKey: .mimeType),
                durationMs: try c.decodeIfPresent(Int.self, forKey: .durationMs),
                errorMessage: try c.decodeIfPresent(String.self, forKey: .errorMessage)
            )
        case "audioListResult":
            return .audioListResult(
                requestId: try c.decode(String.self, forKey: .requestId),
                list: try c.decodeIfPresent(WireAudioListResult.self, forKey: .list),
                errorMessage: try c.decodeIfPresent(String.self, forKey: .errorMessage)
            )
        case "audioDeleteResult":
            return .audioDeleteResult(
                requestId: try c.decode(String.self, forKey: .requestId),
                deleted: try c.decode(Bool.self, forKey: .deleted),
                errorMessage: try c.decodeIfPresent(String.self, forKey: .errorMessage)
            )
        default:
            return nil
        }
    }

    private static func decodeBase(type: String, from c: KeyedDecodingContainer<FlatKeys>) throws -> BridgeBody {
        switch type {
        case "auth":
            return .auth(
                token: try c.decode(String.self, forKey: .token),
                deviceName: try c.decodeIfPresent(String.self, forKey: .deviceName),
                clientKind: try c.decode(ClientKind.self, forKey: .clientKind),
                clientId: try c.decode(String.self, forKey: .clientId),
                installationId: try c.decode(String.self, forKey: .installationId),
                deviceId: try c.decode(String.self, forKey: .deviceId)
            )
        case "listSessions":
            return .listSessions
        case "openSession":
            return .openSession(
                sessionId: try c.decode(String.self, forKey: .sessionId),
                limit: try c.decodeIfPresent(Int.self, forKey: .limit)
            )
        case "loadOlderMessages":
            return .loadOlderMessages(
                sessionId: try c.decode(String.self, forKey: .sessionId),
                beforeMessageId: try c.decode(String.self, forKey: .beforeMessageId),
                limit: try c.decode(Int.self, forKey: .limit)
            )
        case "sendMessage":
            return .sendMessage(
                sessionId: try c.decode(String.self, forKey: .sessionId),
                text: try c.decode(String.self, forKey: .text),
                attachments: try c.decodeIfPresent([WireAttachment].self, forKey: .attachments) ?? []
            )
        case "newSession":
            return .newSession(
                sessionId: try c.decode(String.self, forKey: .sessionId),
                text: try c.decode(String.self, forKey: .text),
                attachments: try c.decodeIfPresent([WireAttachment].self, forKey: .attachments) ?? []
            )
        case "interruptTurn":
            return .interruptTurn(sessionId: try c.decode(String.self, forKey: .sessionId))
        case "authOk":
            return .authOk(hostDisplayName: try c.decodeIfPresent(String.self, forKey: .hostDisplayName))
        case "authFailed":
            return .authFailed(reason: try c.decode(String.self, forKey: .reason))
        case "versionMismatch":
            return .versionMismatch(serverVersion: try c.decode(Int.self, forKey: .serverVersion))
        case "sessionsSnapshot":
            return .sessionsSnapshot(sessions: try c.decode([WireSession].self, forKey: .sessions))
        case "sessionUpdated":
            return .sessionUpdated(session: try c.decode(WireSession.self, forKey: .session))
        case "messagesSnapshot":
            return .messagesSnapshot(
                sessionId: try c.decode(String.self, forKey: .sessionId),
                messages: try c.decode([WireMessage].self, forKey: .messages),
                hasMore: try c.decodeIfPresent(Bool.self, forKey: .hasMore)
            )
        case "messagesPage":
            return .messagesPage(
                sessionId: try c.decode(String.self, forKey: .sessionId),
                messages: try c.decode([WireMessage].self, forKey: .messages),
                hasMore: try c.decode(Bool.self, forKey: .hasMore)
            )
        case "messageAppended":
            return .messageAppended(
                sessionId: try c.decode(String.self, forKey: .sessionId),
                message: try c.decode(WireMessage.self, forKey: .message)
            )
        case "messageStreaming":
            return .messageStreaming(
                sessionId: try c.decode(String.self, forKey: .sessionId),
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
                sessionId: try c.decode(String.self, forKey: .sessionId),
                messageId: try c.decode(String.self, forKey: .messageId),
                text: try c.decode(String.self, forKey: .text)
            )
        case "archiveSession":
            return .archiveSession(sessionId: try c.decode(String.self, forKey: .sessionId))
        case "unarchiveSession":
            return .unarchiveSession(sessionId: try c.decode(String.self, forKey: .sessionId))
        case "pinSession":
            return .pinSession(sessionId: try c.decode(String.self, forKey: .sessionId))
        case "unpinSession":
            return .unpinSession(sessionId: try c.decode(String.self, forKey: .sessionId))
        case "renameSession":
            return .renameSession(
                sessionId: try c.decode(String.self, forKey: .sessionId),
                title: try c.decode(String.self, forKey: .title)
            )
        case "pairingStart":
            return .pairingStart
        case "pairingPayload":
            return .pairingPayload(
                qrJson: try c.decode(String.self, forKey: .qrJson),
                token: try c.decode(String.self, forKey: .token),
                shortCode: try c.decode(String.self, forKey: .shortCode)
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
    /// are expected to render the sessions list now.
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
/// `windowDurationMins` and `resetsAt` are optional because the account
/// endpoint can omit window metadata for non-windowed buckets.
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
