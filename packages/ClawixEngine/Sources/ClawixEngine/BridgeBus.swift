import Foundation
#if canImport(Combine)
import Combine
#else
import OpenCombine
import OpenCombineFoundation
#endif
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
    /// When a subscribed chat gains more than this many messages in a
    /// single publisher tick, the bus emits a single `messagesSnapshot`
    /// instead of N `messageAppended` frames. Protects clients from the
    /// "transcript fills in visibly one row per render" pattern when the
    /// host applies a bulk hydration (e.g. opening a chat that wasn't
    /// pre-hydrated). Live-streaming a turn produces small deltas (1-3
    /// messages: agentMessage + workItems + final), well under the
    /// threshold, so the existing append path keeps its tight latency.
    private let bridgeBatchAppendThreshold = 5
    /// Last `BridgeRuntimeState` seen on the wire. Cached so a peer
    /// connecting after `startObserving` can pull the current state
    /// synchronously without waiting for the next publisher tick.
    private(set) var lastState: BridgeRuntimeState = .booting
    /// Last rate-limits payload seen on the publisher. Cached for the
    /// same reason as `lastState`: a desktop peer that sends
    /// `requestRateLimits` between two publisher ticks gets the most
    /// recent value the host published, not whatever empty seed the
    /// bus started with.
    private(set) var lastRateLimits: WireRateLimitsPayload = .empty

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
        if let host {
            // Seed the cache from whatever the host knows synchronously
            // so the first peer that authenticates picks up the right
            // state even if the publisher hasn't ticked yet.
            lastState = host.bridgeStateCurrent
            lastRateLimits = host.bridgeRateLimitsCurrent
        }
        host?.bridgeStatePublisher
            .removeDuplicates()
            .sink { [weak self] state in
                self?.applyRuntimeState(state)
            }
            .store(in: &cancellables)
        host?.bridgeRateLimitsPublisher
            .removeDuplicates()
            .sink { [weak self] payload in
                self?.applyRateLimits(payload)
            }
            .store(in: &cancellables)
    }

    public func stop() {
        cancellables.removeAll()
        subscribedChatIds.removeAll()
        snapshot.removeAll()
        listShape.removeAll()
        emit = nil
        lastState = .booting
        lastRateLimits = .empty
    }

    /// Build the current `bridgeState` frame for a peer that just
    /// authenticated. Reads through to the host so the chat count is
    /// always in sync with what `currentSessions()` would return one
    /// instruction earlier.
    public func currentBridgeStateFrame() -> BridgeFrame {
        let count = host?.bridgeChatsCurrent.count ?? 0
        return BridgeFrame(.bridgeState(
            state: lastState.wireTag,
            chatCount: count,
            message: lastState.errorMessage
        ))
    }

    private func applyRuntimeState(_ state: BridgeRuntimeState) {
        lastState = state
        guard let emit else { return }
        let count = host?.bridgeChatsCurrent.count ?? 0
        emit(BridgeFrame(.bridgeState(
            state: state.wireTag,
            chatCount: count,
            message: state.errorMessage
        )))
    }

    /// Build the current `rateLimitsSnapshot` frame for a peer that
    /// just sent `requestRateLimits`. Reads through to the host so the
    /// payload is the freshest the host published, even if the bus
    /// publisher hasn't ticked yet (the daemon seeds its subject
    /// synchronously after `account/rateLimits/read` lands).
    public func currentRateLimitsFrame() -> BridgeFrame {
        let payload = host?.bridgeRateLimitsCurrent ?? lastRateLimits
        return BridgeFrame(.rateLimitsSnapshot(
            snapshot: payload.snapshot,
            byLimitId: payload.byLimitId
        ))
    }

    private func applyRateLimits(_ payload: WireRateLimitsPayload) {
        lastRateLimits = payload
        guard let emit else { return }
        // Push every fresh value to all desktop sessions. iPhone clients
        // ignore the frame (their switch lists it under the "drop"
        // catch-all), so a single broadcast is fine.
        emit(BridgeFrame(.rateLimitsUpdated(
            snapshot: payload.snapshot,
            byLimitId: payload.byLimitId
        )))
    }

    /// Client called `openSession`. Returns the current snapshot of
    /// messages so the session can reply with `messagesSnapshot`.
    /// When `limit` is set, only the trailing N messages are returned
    /// alongside `hasMore: true` if there are older messages on the
    /// server's side. `limit == nil` is the v1 whole-transcript mode
    /// and produces `hasMore: false`.
    public func subscribe(sessionId: String, limit: Int? = nil) -> (messages: [WireMessage], hasMore: Bool) {
        subscribedChatIds.insert(sessionId)
        let all = host?.bridgeChatsCurrent.first(where: { $0.id == sessionId })?.messages ?? []
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
    public func page(sessionId: String, before beforeMessageId: String, limit: Int) -> (messages: [WireMessage], hasMore: Bool) {
        guard limit > 0 else { return ([], false) }
        let all = host?.bridgeChatsCurrent.first(where: { $0.id == sessionId })?.messages ?? []
        guard let cursorIdx = all.firstIndex(where: { $0.id == beforeMessageId }) else {
            return ([], false)
        }
        let lower = max(0, cursorIdx - limit)
        let slice = Array(all[lower..<cursorIdx])
        let hasMore = lower > 0
        return (slice, hasMore)
    }

    public func unsubscribe(sessionId: String) {
        subscribedChatIds.remove(sessionId)
    }

    /// Client called `listSessions`. Returns the current chats list. The
    /// session replies with `sessionsSnapshot`.
    public func currentSessions() -> [WireSession] {
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
                    let delta = proj.messageCount - prev.messageCount
                    if delta > bridgeBatchAppendThreshold {
                        // Bulk gain (typical: lazy hydration finished and
                        // the chat went from 0 to N in one tick). Emitting
                        // N appends would make the client paint rows one
                        // by one. A single snapshot resets the transcript
                        // atomically and keeps the scroll anchor at the
                        // tail on the first render.
                        emit(BridgeFrame(.messagesSnapshot(
                            sessionId: snap.id,
                            messages: snap.messages,
                            hasMore: nil
                        )))
                    } else {
                        let added = snap.messages.suffix(delta)
                        for msg in added {
                            emit(BridgeFrame(.messageAppended(
                                sessionId: snap.id,
                                message: msg
                            )))
                        }
                    }
                } else if prev?.messageCount != proj.messageCount {
                    // Count decreased (rare: turn cancelled with placeholder
                    // dropped) or first observation. Send full snapshot.
                    // `hasMore: nil` tells the iPhone "this is a whole
                    // transcript, reset any pagination state you held".
                    emit(BridgeFrame(.messagesSnapshot(
                        sessionId: snap.id,
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
                        sessionId: snap.id,
                        messageId: lastId,
                        content: proj.lastContent,
                        reasoningText: proj.lastReasoning,
                        finished: proj.lastFinished
                    )))
                }
            }

            if metadataChanged {
                emit(BridgeFrame(.sessionUpdated(session: snap.chat)))
            }

            // Unsubscribed chats still get a sessionUpdated when surface
            // metadata (title, lastMessage, hasActiveTurn) changed.
            if !subscribedChatIds.contains(snap.id), prev != nil, !metadataChanged {
                emit(BridgeFrame(.sessionUpdated(session: snap.chat)))
            }
        }

        if listChanged {
            emit(BridgeFrame(.sessionsSnapshot(sessions: chats.map(\.chat))))
        }
    }
}
