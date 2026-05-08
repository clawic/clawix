import Foundation
import Combine
import ClawixCore

/// Pair of "general" + "per-bucket" rate-limit views the daemon ships
/// to desktop clients. `snapshot` is the top-level Codex view (the same
/// shape returned at `account/rateLimits/read.rateLimits`), while
/// `byLimitId` carries the per-bucket map (e.g. `"codex_<model>"`).
/// `nil` snapshot means "the daemon hasn't fetched the first read yet";
/// empty `byLimitId` means "the backend doesn't surface per-bucket
/// data". Hosts without a real Codex connection ship `.empty`.
public struct WireRateLimitsPayload: Equatable, Sendable {
    public var snapshot: WireRateLimitSnapshot?
    public var byLimitId: [String: WireRateLimitSnapshot]

    public init(snapshot: WireRateLimitSnapshot? = nil, byLimitId: [String: WireRateLimitSnapshot] = [:]) {
        self.snapshot = snapshot
        self.byLimitId = byLimitId
    }

    public static let empty = WireRateLimitsPayload()
}

/// Snapshot of one chat carrying everything the bridge needs to diff
/// and emit frames for: the wire-level metadata (`WireChat`) plus the
/// full ordered message list. The host (the macOS `AppState` today,
/// the LaunchAgent daemon's `EngineCore` later) republishes this list
/// on every chat change.
///
/// We carry full `[WireMessage]` here, not deltas, because the bus
/// owns the diffing logic and decides per-tick what to emit on the
/// wire. The host does not have to reason about deltas at all.
public struct BridgeChatSnapshot: Equatable, Sendable {
    public let chat: WireChat
    public let messages: [WireMessage]

    public init(chat: WireChat, messages: [WireMessage]) {
        self.chat = chat
        self.messages = messages
    }

    public var id: String { chat.id }
}

/// Surface the bridge needs from the process that owns the chat state.
///
/// The macOS GUI's `AppState` implements this today by adapting its
/// `Chat`/`ChatMessage` domain models to wire types via `toWire()`.
/// The LaunchAgent daemon will implement it natively against its own
/// in-process `ChatStore`. The bridge code (`BridgeServer`,
/// `BridgeBus`, `BridgeSession`, `BridgeIntent`) talks only to this
/// protocol, never to a concrete host type, so the same source files
/// link into both targets.
@MainActor
public protocol EngineHost: AnyObject {

    /// Most recent chats snapshot. Used for the immediate reply to
    /// `listChats` / `openChat` before the publisher emits a new tick.
    var bridgeChatsCurrent: [BridgeChatSnapshot] { get }

    /// Stream of chat snapshots. The bus throttles + diffs internally,
    /// so the host can republish freely (every keystroke that touches
    /// chats is fine; the bus collapses to ~16ms ticks on loopback).
    var bridgeChatsPublisher: AnyPublisher<[BridgeChatSnapshot], Never> { get }

    /// Current bootstrap state of the host. Surfaced over the wire as
    /// a `bridgeState` frame so a peer that connected during boot
    /// distinguishes "snapshot is empty because we're still loading"
    /// from "snapshot is empty because there really are no chats".
    /// Hosts that come up instantly (the in-process GUI server) keep
    /// the default `.ready`.
    var bridgeStateCurrent: BridgeRuntimeState { get }

    /// Stream of bootstrap states. Default impl emits a single `.ready`
    /// so hosts without a real bootstrap don't have to publish anything.
    var bridgeStatePublisher: AnyPublisher<BridgeRuntimeState, Never> { get }

    /// Most recent rate-limits view the host knows about. The bus reads
    /// this synchronously when a desktop client sends `requestRateLimits`
    /// so the reply doesn't have to wait for the next publisher tick.
    /// Default impl returns `.empty` so hosts that don't track Codex
    /// rate limits (the in-process GUI server) get a no-op.
    var bridgeRateLimitsCurrent: WireRateLimitsPayload { get }

    /// Stream of rate-limits views. The bus subscribes to this and
    /// emits `rateLimitsUpdated` frames to all desktop sessions every
    /// time a fresh value lands. Default impl emits a single empty
    /// payload so the bus's `.sink` is well-formed without spamming.
    var bridgeRateLimitsPublisher: AnyPublisher<WireRateLimitsPayload, Never> { get }

    /// iPhone or daemon-backed desktop client opened a chat. Hosts
    /// that read rollouts lazily should hydrate the history off disk
    /// here so subsequent `bridgeChatsCurrent` lookups already carry
    /// the full message list.
    func handleHydrateHistory(chatId: UUID)

    /// Inbound `sendPrompt` from a client. The host is responsible for
    /// routing the prompt into the agent (the macOS GUI delegates to
    /// `AppState.sendUserMessageFromBridge`). Attachments are inline
    /// image payloads the daemon writes to disk and forwards as
    /// `localImage` user input items; hosts that don't support them
    /// can ignore the array.
    func handleSendPrompt(chatId: UUID, text: String, attachments: [WireAttachment])

    /// Inbound `newChat` from a client. The host creates a fresh chat
    /// with the supplied UUID, appends the user message, and kicks off
    /// the agent. Pre-minting the id on the client side lets the iPhone
    /// route to the chat detail screen synchronously while the round
    /// trip is in flight.
    func handleNewChat(chatId: UUID, text: String, attachments: [WireAttachment])

    /// Inbound `interruptTurn` from a client. Stop the in-flight turn
    /// for `chatId` if any: clear `hasActiveTurn`, mark the turn
    /// interrupted so late deltas are dropped, and ask the backend to
    /// cancel. Mirrors the Mac composer's stop button.
    func handleInterruptTurn(chatId: UUID)

    // MARK: - v2 desktop-only hooks (LaunchAgent daemon will override)

    /// Edit a previous user message in place and re-run the turn.
    /// Default impl is a no-op so v1 hosts (the in-process server in
    /// the GUI) can ignore desktop-only frames.
    func handleEditPrompt(chatId: UUID, messageId: UUID, text: String)

    func handleArchiveChat(chatId: UUID, archived: Bool)
    func handlePinChat(chatId: UUID, pinned: Bool)

    /// Rename `chatId` to `title`. Daemon writes through to the runtime
    /// (Codex `thread/name/set`) and republishes the chat snapshot so
    /// every subscriber sees the new name.
    func handleRenameChat(chatId: UUID, title: String)

    /// Mint a new pairing payload (token + QR JSON) and return it via
    /// the completion. The bridge translates this into a
    /// `pairingPayload` frame back to the requesting client.
    func handlePairingStart() -> (qrJson: String, bearer: String)?

    /// Snapshot of projects the daemon knows about. Returned as the
    /// reply to `listProjects`. Default impl returns empty so the
    /// in-process GUI server can opt out.
    func currentProjects() -> [WireProject]

    /// Inbound `transcribeAudio` from a client. The host decodes the
    /// base64 audio, runs Whisper on it, and calls `reply` with either
    /// the transcript and `nil`, or an empty string and a short error
    /// message. The bridge wraps that into a `transcriptionResult`
    /// frame addressed to the same `requestId`. Hosts without a local
    /// transcription engine reply with an error via the default impl.
    func handleTranscribeAudio(
        requestId: String,
        audioBase64: String,
        mimeType: String,
        language: String?,
        reply: @MainActor @escaping (_ text: String, _ errorMessage: String?) -> Void
    )

    /// Inbound `requestAudio` from a client. The host looks up the
    /// audio bytes by the supplied `audioId` (typically minted by the
    /// daemon at ingest time and surfaced on a `WireMessage.audioRef`)
    /// and calls `reply` with either `(audioBase64, mimeType, nil)` or
    /// `(nil, nil, errorMessage)`. Hosts that don't store audio reply
    /// via the default impl with a "not available" error.
    func handleRequestAudio(
        audioId: String,
        reply: @MainActor @escaping (_ audioBase64: String?, _ mimeType: String?, _ errorMessage: String?) -> Void
    )

    /// Inbound `requestGeneratedImage` from a client. The host resolves
    /// `path` to an actual file on disk, ensures the path stays inside
    /// `~/.codex/generated_images/` (or the host's equivalent sandbox)
    /// to avoid arbitrary file reads, and calls `reply` with either
    /// `(dataBase64, mimeType, nil)` or `(nil, nil, errorMessage)`. The
    /// default impl handles the standard Codex layout so most hosts
    /// don't need to override.
    func handleRequestGeneratedImage(
        path: String,
        reply: @MainActor @escaping (_ dataBase64: String?, _ mimeType: String?, _ errorMessage: String?) -> Void
    )
}

// MARK: - Default no-op impls for desktop-only hooks

public extension EngineHost {
    func handleEditPrompt(chatId: UUID, messageId: UUID, text: String) {}
    func handleArchiveChat(chatId: UUID, archived: Bool) {}
    func handlePinChat(chatId: UUID, pinned: Bool) {}
    func handleRenameChat(chatId: UUID, title: String) {}
    func handlePairingStart() -> (qrJson: String, bearer: String)? { nil }
    func currentProjects() -> [WireProject] { [] }
    func handleNewChat(chatId: UUID, text: String, attachments: [WireAttachment]) {}
    func handleInterruptTurn(chatId: UUID) {}

    /// In-process hosts come up instantly: nothing to bootstrap, the
    /// chat store is already populated from disk before the bridge
    /// starts. They sit permanently at `.ready`.
    var bridgeStateCurrent: BridgeRuntimeState { .ready }
    var bridgeStatePublisher: AnyPublisher<BridgeRuntimeState, Never> {
        Just(BridgeRuntimeState.ready).eraseToAnyPublisher()
    }
    /// Hosts that don't own a Codex backend (the in-process GUI server
    /// reads rate limits straight from `AppState`, no bridge involved)
    /// surface an empty payload here. The daemon overrides both with
    /// a real CurrentValueSubject seeded from `account/rateLimits/read`.
    var bridgeRateLimitsCurrent: WireRateLimitsPayload { .empty }
    var bridgeRateLimitsPublisher: AnyPublisher<WireRateLimitsPayload, Never> {
        Just(WireRateLimitsPayload.empty).eraseToAnyPublisher()
    }
    func handleTranscribeAudio(
        requestId: String,
        audioBase64: String,
        mimeType: String,
        language: String?,
        reply: @MainActor @escaping (String, String?) -> Void
    ) {
        reply("", "Transcription is not available on this host")
    }
    func handleRequestAudio(
        audioId: String,
        reply: @MainActor @escaping (String?, String?, String?) -> Void
    ) {
        reply(nil, nil, "Audio replay is not available on this host")
    }
    func handleRequestGeneratedImage(
        path: String,
        reply: @MainActor @escaping (String?, String?, String?) -> Void
    ) {
        let result = GeneratedImageReader.read(path: path)
        reply(result.dataBase64, result.mimeType, result.errorMessage)
    }
}
