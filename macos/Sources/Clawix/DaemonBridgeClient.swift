import Foundation
import Network
import ClawixCore
import ClawixEngine

@MainActor
final class DaemonBridgeClient {
    private weak var appState: AppState?
    private let pairing: PairingService
    private var connection: NWConnection?
    private var isAuthenticated = false
    private var reconnectWork: DispatchWorkItem?
    private var bridgeState = "booting"

    init(appState: AppState, pairing: PairingService) {
        self.appState = appState
        self.pairing = pairing
    }

    func connect() {
        disconnect()
        let parameters = NWParameters.tcp
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        // NWProtocolWebSocket needs a URL endpoint, not bare hostPort.
        // With a hostPort endpoint the upgrade aborts on macOS/iOS 26
        // with ECONNABORTED right after the TCP handshake even against
        // a server the iOS app's NWBrowser candidates reach fine. The
        // iOS bridge client (BridgeClient.makeEndpoint) hit the same
        // wall and switched to NWEndpoint.url(URL("ws://host:port/"));
        // do the same here so the macOS desktop client doesn't break.
        let url = URL(string: "ws://127.0.0.1:\(pairing.port)/")!
        let connection = NWConnection(to: .url(url), using: parameters)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handle(state)
            }
        }
        connection.start(queue: .main)
    }

    func disconnect() {
        reconnectWork?.cancel()
        reconnectWork = nil
        connection?.cancel()
        connection = nil
        isAuthenticated = false
    }

    func openSession(_ sessionId: UUID) {
        // Always opt into pagination, same as the iPhone client. The
        // initial paint only needs the trailing window
        // (`bridgeInitialPageLimit`); older history streams in via
        // `loadOlderMessages` if the user scrolls up. Pulling the full
        // transcript on every session tap was the dominant cost behind
        // the "transcript reanchors visibly while building from the
        // top" symptom on Mac, even over loopback.
        send(.openSession(sessionId: sessionId.uuidString, limit: bridgeInitialPageLimit))
    }

    /// Fetch the next page of older messages for `chatId`. The cursor
    /// is the id of the oldest message the desktop currently has; the
    /// daemon replies with `messagesPage` carrying the slice prior to
    /// it (oldest first). No-op when not yet authenticated.
    @discardableResult
    func loadOlderMessages(chatId: UUID, beforeMessageId: String) -> Bool {
        send(.loadOlderMessages(
            sessionId: chatId.uuidString,
            beforeMessageId: beforeMessageId,
            limit: bridgeOlderPageLimit
        ))
    }

    func sendMessage(chatId: UUID, text: String, attachments: [WireAttachment] = []) {
        send(.sendMessage(sessionId: chatId.uuidString, text: text, attachments: attachments))
    }

    func archiveChat(_ chatId: UUID) {
        send(.archiveSession(sessionId: chatId.uuidString))
    }

    func unarchiveChat(_ chatId: UUID) {
        send(.unarchiveSession(sessionId: chatId.uuidString))
    }

    func interruptTurn(chatId: UUID) {
        send(.interruptTurn(sessionId: chatId.uuidString))
    }

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            receive()
            send(.auth(
                token: pairing.bearer,
                deviceName: Host.current().localizedName,
                clientKind: .desktop,
                clientId: nil,
                installationId: nil,
                deviceId: nil
            ))
        case .failed, .cancelled:
            isAuthenticated = false
            scheduleReconnect()
        default:
            break
        }
    }

    private func receive() {
        guard let connection else { return }
        connection.receiveMessage { [weak self] data, context, _, error in
            Task { @MainActor in
                guard let self else { return }
                if error != nil {
                    self.connection?.cancel()
                    return
                }
                if let metadata = context?.protocolMetadata.first as? NWProtocolWebSocket.Metadata {
                    switch metadata.opcode {
                    case .text, .binary:
                        break
                    default:
                        self.receive()
                        return
                    }
                }
                if let data, !data.isEmpty {
                    self.handle(data)
                }
                self.receive()
            }
        }
    }

    private func handle(_ data: Data) {
        guard let frame = try? BridgeCoder.decode(data) else { return }
        switch frame.body {
        case .authOk:
            isAuthenticated = true
            send(.listSessions)
            // The daemon owns the Codex backend in this mode, so the GUI
            // can no longer pull rate limits via its own ClawixService.
            // Ask the daemon for the current snapshot; subsequent
            // changes flow back as `rateLimitsUpdated` pushes.
            send(.requestRateLimits)
        case .sessionsSnapshot(let chats):
            if chats.isEmpty,
               bridgeState != "ready",
               let appState,
               !appState.chats.isEmpty || !appState.archivedChats.isEmpty {
                break
            }
            appState?.applyDaemonChats(chats)
            appState?.persistSnapshotDebounced()
        case .sessionUpdated(let session):
            appState?.applyDaemonChat(session)
            appState?.persistSnapshotDebounced()
        case .messagesSnapshot(let chatId, let messages, let hasMore):
            appState?.applyDaemonMessages(chatId: chatId, messages: messages, hasMore: hasMore)
            appState?.persistSnapshotDebounced()
        case .messagesPage(let chatId, let messages, let hasMore):
            appState?.applyDaemonMessagesPage(chatId: chatId, messages: messages, hasMore: hasMore)
            appState?.persistSnapshotDebounced()
        case .messageAppended(let chatId, let message):
            appState?.appendDaemonMessage(chatId: chatId, message: message)
            appState?.persistSnapshotDebounced()
        case .messageStreaming(let chatId, let messageId, let content, let reasoningText, let finished):
            appState?.applyDaemonStreaming(chatId: chatId,
                                           messageId: messageId,
                                           content: content,
                                           reasoningText: reasoningText,
                                           finished: finished)
        case .rateLimitsSnapshot(let snapshot, let byLimitId),
             .rateLimitsUpdated(let snapshot, let byLimitId):
            appState?.applyDaemonRateLimits(snapshot: snapshot, byLimitId: byLimitId)
        case .bridgeState(let state, _, _):
            bridgeState = state
        case .authFailed, .versionMismatch:
            connection?.cancel()
        default:
            break
        }
    }

    @discardableResult
    private func send(_ body: BridgeBody) -> Bool {
        guard let connection else { return false }
        guard isAuthenticated || {
            if case .auth = body { return true }
            return false
        }() else { return false }
        guard let data = try? BridgeCoder.encode(BridgeFrame(body)) else { return false }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "frame", metadata: [metadata])
        connection.send(content: data,
                        contentContext: context,
                        isComplete: true,
                        completion: .contentProcessed { _ in })
        return true
    }

    private func scheduleReconnect() {
        guard reconnectWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.reconnectWork = nil
                self?.connect()
            }
        }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }
}
