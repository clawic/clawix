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
        let connection = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: pairing.port) ?? .any,
            using: parameters
        )
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

    func openChat(_ chatId: UUID) {
        send(.openChat(chatId: chatId.uuidString))
    }

    func sendPrompt(chatId: UUID, text: String) {
        send(.sendPrompt(chatId: chatId.uuidString, text: text))
    }

    func archiveChat(_ chatId: UUID) {
        send(.archiveChat(chatId: chatId.uuidString))
    }

    func unarchiveChat(_ chatId: UUID) {
        send(.unarchiveChat(chatId: chatId.uuidString))
    }

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            receive()
            send(.auth(token: pairing.bearer, deviceName: Host.current().localizedName, clientKind: .desktop))
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
            send(.listChats)
        case .chatsSnapshot(let chats):
            appState?.applyDaemonChats(chats)
        case .chatUpdated(let chat):
            appState?.applyDaemonChat(chat)
        case .messagesSnapshot(let chatId, let messages):
            appState?.applyDaemonMessages(chatId: chatId, messages: messages)
        case .messageAppended(let chatId, let message):
            appState?.appendDaemonMessage(chatId: chatId, message: message)
        case .messageStreaming(let chatId, let messageId, let content, let reasoningText, let finished):
            appState?.applyDaemonStreaming(chatId: chatId,
                                           messageId: messageId,
                                           content: content,
                                           reasoningText: reasoningText,
                                           finished: finished)
        case .authFailed, .versionMismatch:
            connection?.cancel()
        default:
            break
        }
    }

    private func send(_ body: BridgeBody) {
        guard let connection else { return }
        guard isAuthenticated || {
            if case .auth = body { return true }
            return false
        }() else { return }
        guard let data = try? BridgeCoder.encode(BridgeFrame(body)) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "frame", metadata: [metadata])
        connection.send(content: data,
                        contentContext: context,
                        isComplete: true,
                        completion: .contentProcessed { _ in })
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
