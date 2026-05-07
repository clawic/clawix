import Foundation
import Combine
import ClawixCore

/// Sits between `EngineHost` (the chat-state owner) and the WS sessions.
/// Subscribes to `host.bridgeChatsPublisher`, throttles streaming
/// deltas so they don't saturate the wire, and emits `BridgeFrame`s
/// describing what changed since the previous tick.
@MainActor
public final class BridgeBus {
    private weak var host: EngineHost?
    private var cancellables = Set<AnyCancellable>()
    private var subscribedChatIds: Set<String> = []
    private var snapshot: [String: ChatProjection] = [:]
    private var listShape: [String] = []
    private var emit: ((BridgeFrame) -> Void)?

    /// Diff key: derived fields that, when changed, warrant a frame.
    /// Equality on this struct is what gates "did anything observable
    /// change for this chat?" so the bus stays quiet on no-op republishes.
    private struct ChatProjection: Equatable {
        let title: String
        let isPinned: Bool
        let isArchived: Bool
        let hasActiveTurn: Bool
        let lastTurnInterrupted: Bool
        let messageCount: Int
        let lastMessageId: String?
        let lastContent: String
        let lastReasoning: String
        let lastFinished: Bool
        let lastTimestamp: Date?

        init(_ s: BridgeChatSnapshot) {
            self.title = s.chat.title
            self.isPinned = s.chat.isPinned
            self.isArchived = s.chat.isArchived
            self.hasActiveTurn = s.chat.hasActiveTurn
            self.lastTurnInterrupted = s.chat.lastTurnInterrupted
            self.messageCount = s.messages.count
            self.lastMessageId = s.messages.last?.id
            self.lastContent = s.messages.last?.content ?? ""
            self.lastReasoning = s.messages.last?.reasoningText ?? ""
            self.lastFinished = s.messages.last?.streamingFinished ?? true
            self.lastTimestamp = s.messages.last?.timestamp
        }
    }

    public init(host: EngineHost) {
        self.host = host
    }

    public func startObserving(emit: @escaping (BridgeFrame) -> Void) {
        self.emit = emit
        host?.bridgeChatsPublisher
            .throttle(for: .milliseconds(60), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] chats in
                self?.process(chats: chats)
            }
            .store(in: &cancellables)
    }

    public func stop() {
        cancellables.removeAll()
        subscribedChatIds.removeAll()
        snapshot.removeAll()
        listShape.removeAll()
        emit = nil
    }

    /// Client called `openChat`. Returns the current snapshot of
    /// messages so the session can reply with `messagesSnapshot`.
    /// When `limit` is set, only the trailing N messages are returned
    /// alongside `hasMore: true` if there are older messages on the
    /// server's side. `limit == nil` preserves the legacy "ship the
    /// whole transcript" behaviour for old peers and produces
    /// `hasMore: false`.
    public func subscribe(chatId: String, limit: Int? = nil) -> (messages: [WireMessage], hasMore: Bool) {
        subscribedChatIds.insert(chatId)
        let all = host?.bridgeChatsCurrent.first(where: { $0.id == chatId })?.messages ?? []
        guard let limit, limit > 0, all.count > limit else {
            return (all, false)
        }
        return (Array(all.suffix(limit)), true)
    }

    /// Pull a page of older messages anchored before `beforeMessageId`.
    /// Returns the slice that ends exactly before the cursor, oldest
    /// first, plus `hasMore` set when there is at least one older
    /// message on the server's side. If the cursor cannot be found
    /// (chat truncated by `editPrompt` between requests, message id
    /// from a stale view), the function returns `([], false)` so the
    /// client treats it as "nothing older".
    public func page(chatId: String, before beforeMessageId: String, limit: Int) -> (messages: [WireMessage], hasMore: Bool) {
        guard limit > 0 else { return ([], false) }
        let all = host?.bridgeChatsCurrent.first(where: { $0.id == chatId })?.messages ?? []
        guard let cursorIdx = all.firstIndex(where: { $0.id == beforeMessageId }) else {
            return ([], false)
        }
        let lower = max(0, cursorIdx - limit)
        let slice = Array(all[lower..<cursorIdx])
        let hasMore = lower > 0
        return (slice, hasMore)
    }

    public func unsubscribe(chatId: String) {
        subscribedChatIds.remove(chatId)
    }

    /// Client called `listChats`. Returns the current chats list. The
    /// session replies with `chatsSnapshot`.
    public func currentChats() -> [WireChat] {
        host?.bridgeChatsCurrent.map(\.chat) ?? []
    }

    private func process(chats: [BridgeChatSnapshot]) {
        guard let emit else { return }

        let currentShape = chats.map(\.id)
        let listChanged = currentShape != listShape
        listShape = currentShape

        for snap in chats {
            let proj = ChatProjection(snap)
            let prev = snapshot[snap.id]
            snapshot[snap.id] = proj
            guard prev != proj else { continue }
            let metadataChanged = prev.map {
                $0.title != proj.title
                    || $0.isPinned != proj.isPinned
                    || $0.isArchived != proj.isArchived
                    || $0.hasActiveTurn != proj.hasActiveTurn
                    || $0.lastTurnInterrupted != proj.lastTurnInterrupted
            } ?? false

            // Subscribed chats get message-level updates.
            if subscribedChatIds.contains(snap.id) {
                if let prev, prev.messageCount < proj.messageCount {
                    let added = snap.messages.suffix(proj.messageCount - prev.messageCount)
                    for msg in added {
                        emit(BridgeFrame(.messageAppended(
                            chatId: snap.id,
                            message: msg
                        )))
                    }
                } else if prev?.messageCount != proj.messageCount {
                    // Count decreased (rare: turn cancelled with placeholder
                    // dropped) or first observation. Send full snapshot.
                    // `hasMore: nil` tells the iPhone "this is a whole
                    // transcript, reset any pagination state you held".
                    emit(BridgeFrame(.messagesSnapshot(
                        chatId: snap.id,
                        messages: snap.messages,
                        hasMore: nil
                    )))
                }

                if let lastId = proj.lastMessageId,
                   prev?.lastMessageId == lastId,
                   (prev?.lastContent != proj.lastContent
                    || prev?.lastReasoning != proj.lastReasoning
                    || prev?.lastFinished != proj.lastFinished) {
                    emit(BridgeFrame(.messageStreaming(
                        chatId: snap.id,
                        messageId: lastId,
                        content: proj.lastContent,
                        reasoningText: proj.lastReasoning,
                        finished: proj.lastFinished
                    )))
                }
            }

            if metadataChanged {
                emit(BridgeFrame(.chatUpdated(chat: snap.chat)))
            }

            // Unsubscribed chats still get a chatUpdated when surface
            // metadata (title, lastMessage, hasActiveTurn) changed.
            if !subscribedChatIds.contains(snap.id), prev != nil, !metadataChanged {
                emit(BridgeFrame(.chatUpdated(chat: snap.chat)))
            }
        }

        if listChanged {
            emit(BridgeFrame(.chatsSnapshot(chats: chats.map(\.chat))))
        }
    }
}
