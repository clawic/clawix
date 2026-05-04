import Foundation
import Combine
import ClawixCore

/// Sits between `AppState` and the WS sessions. Subscribes to
/// `appState.$chats` (Combine), throttles to 60ms so streaming deltas
/// don't saturate the wire, and emits `BridgeFrame`s describing what
/// changed since the previous tick.
@MainActor
final class BridgeBus {
    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()
    private var subscribedChatIds: Set<UUID> = []
    private var snapshot: [UUID: ChatProjection] = [:]
    private var listShape: [UUID] = []
    private var emit: ((BridgeFrame) -> Void)?

    private struct ChatProjection: Equatable {
        let title: String
        let isPinned: Bool
        let isArchived: Bool
        let hasActiveTurn: Bool
        let messageCount: Int
        let lastMessageId: UUID?
        let lastContent: String
        let lastReasoning: String
        let lastFinished: Bool
        let lastTimestamp: Date?
    }

    init(appState: AppState) {
        self.appState = appState
    }

    func startObserving(emit: @escaping (BridgeFrame) -> Void) {
        self.emit = emit
        appState?.$chats
            .throttle(for: .milliseconds(60), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] chats in
                self?.process(chats: chats)
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        subscribedChatIds.removeAll()
        snapshot.removeAll()
        listShape.removeAll()
        emit = nil
    }

    /// iPhone called `openChat`. Returns the current snapshot of
    /// messages so the session can reply with `messagesSnapshot`.
    func subscribe(chatId: UUID) -> [WireMessage] {
        subscribedChatIds.insert(chatId)
        guard let chat = appState?.chats.first(where: { $0.id == chatId }) else { return [] }
        return chat.messages.map { $0.toWire() }
    }

    func unsubscribe(chatId: UUID) {
        subscribedChatIds.remove(chatId)
    }

    /// iPhone called `listChats`. Returns the current chats list. The
    /// session replies with `chatsSnapshot`.
    func currentChats() -> [WireChat] {
        appState?.chats.map { $0.toWire() } ?? []
    }

    private func process(chats: [Chat]) {
        guard let emit else { return }

        let currentShape = chats.map(\.id)
        let listChanged = currentShape != listShape
        listShape = currentShape

        for chat in chats {
            let proj = ChatProjection(
                title: chat.title,
                isPinned: chat.isPinned,
                isArchived: chat.isArchived,
                hasActiveTurn: chat.hasActiveTurn,
                messageCount: chat.messages.count,
                lastMessageId: chat.messages.last?.id,
                lastContent: chat.messages.last?.content ?? "",
                lastReasoning: chat.messages.last?.reasoningText ?? "",
                lastFinished: chat.messages.last?.streamingFinished ?? true,
                lastTimestamp: chat.messages.last?.timestamp
            )
            let prev = snapshot[chat.id]
            snapshot[chat.id] = proj
            guard prev != proj else { continue }

            // Subscribed chats get message-level updates.
            if subscribedChatIds.contains(chat.id) {
                if let prev, prev.messageCount < proj.messageCount {
                    let added = chat.messages.suffix(proj.messageCount - prev.messageCount)
                    for msg in added {
                        emit(BridgeFrame(.messageAppended(
                            chatId: chat.id.uuidString,
                            message: msg.toWire()
                        )))
                    }
                } else if prev?.messageCount != proj.messageCount {
                    // Count decreased (rare: turn cancelled with placeholder
                    // dropped) or first observation. Send full snapshot.
                    emit(BridgeFrame(.messagesSnapshot(
                        chatId: chat.id.uuidString,
                        messages: chat.messages.map { $0.toWire() }
                    )))
                }

                if let lastId = proj.lastMessageId,
                   prev?.lastMessageId == lastId,
                   (prev?.lastContent != proj.lastContent
                    || prev?.lastReasoning != proj.lastReasoning
                    || prev?.lastFinished != proj.lastFinished) {
                    emit(BridgeFrame(.messageStreaming(
                        chatId: chat.id.uuidString,
                        messageId: lastId.uuidString,
                        content: proj.lastContent,
                        reasoningText: proj.lastReasoning,
                        finished: proj.lastFinished
                    )))
                }
            }

            // Unsubscribed chats still get a chatUpdated when surface
            // metadata (title, lastMessage, hasActiveTurn) changed.
            if !subscribedChatIds.contains(chat.id), prev != nil {
                emit(BridgeFrame(.chatUpdated(chat: chat.toWire())))
            }
        }

        if listChanged {
            emit(BridgeFrame(.chatsSnapshot(chats: chats.map { $0.toWire() })))
        }
    }
}
