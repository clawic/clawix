import Foundation
import Combine
import ClawixCore

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

    /// iPhone or daemon-backed desktop client opened a chat. Hosts
    /// that read rollouts lazily should hydrate the history off disk
    /// here so subsequent `bridgeChatsCurrent` lookups already carry
    /// the full message list.
    func handleHydrateHistory(chatId: UUID)

    /// Inbound `sendPrompt` from a client. The host is responsible for
    /// routing the prompt into the agent (the macOS GUI delegates to
    /// `AppState.sendUserMessageFromBridge`).
    func handleSendPrompt(chatId: UUID, text: String)

    /// Inbound `newChat` from a client. The host creates a fresh chat
    /// with the supplied UUID, appends the user message, and kicks off
    /// the agent. Pre-minting the id on the client side lets the iPhone
    /// route to the chat detail screen synchronously while the round
    /// trip is in flight.
    func handleNewChat(chatId: UUID, text: String)

    // MARK: - v2 desktop-only hooks (LaunchAgent daemon will override)

    /// Edit a previous user message in place and re-run the turn.
    /// Default impl is a no-op so v1 hosts (the in-process server in
    /// the GUI) can ignore desktop-only frames.
    func handleEditPrompt(chatId: UUID, messageId: UUID, text: String)

    func handleArchiveChat(chatId: UUID, archived: Bool)
    func handlePinChat(chatId: UUID, pinned: Bool)

    /// Mint a new pairing payload (token + QR JSON) and return it via
    /// the completion. The bridge translates this into a
    /// `pairingPayload` frame back to the requesting client.
    func handlePairingStart() -> (qrJson: String, bearer: String)?

    /// Snapshot of projects the daemon knows about. Returned as the
    /// reply to `listProjects`. Default impl returns empty so the
    /// in-process GUI server can opt out.
    func currentProjects() -> [WireProject]
}

// MARK: - Default no-op impls for desktop-only hooks

public extension EngineHost {
    func handleEditPrompt(chatId: UUID, messageId: UUID, text: String) {}
    func handleArchiveChat(chatId: UUID, archived: Bool) {}
    func handlePinChat(chatId: UUID, pinned: Bool) {}
    func handlePairingStart() -> (qrJson: String, bearer: String)? { nil }
    func currentProjects() -> [WireProject] { [] }
    func handleNewChat(chatId: UUID, text: String) {}
}
