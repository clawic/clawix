import Foundation
import Network
import ClawixCore

/// One iPhone client. Owns the `NWConnection`, drives the receive loop,
/// gates frames behind a successful `auth`. The Phase 2 plaintext build
/// accepts any bearer token; Phase 5 will validate it against the
/// keychain-backed `BearerStore`.
@MainActor
final class BridgeSession: Identifiable {
    let id = UUID()
    private let connection: NWConnection
    private weak var appState: AppState?
    private let bus: BridgeBus
    private let onTerminated: (UUID) -> Void

    private(set) var isAuthenticated: Bool = false
    private(set) var deviceName: String?
    private var didTerminate = false

    init(
        connection: NWConnection,
        appState: AppState,
        bus: BridgeBus,
        onTerminated: @escaping (UUID) -> Void
    ) {
        self.connection = connection
        self.appState = appState
        self.bus = bus
        self.onTerminated = onTerminated
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                Task { @MainActor in self?.terminate() }
            default:
                break
            }
        }
        connection.start(queue: .main)
        receiveLoop()
    }

    private nonisolated func receiveLoop() {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }
            if error != nil {
                Task { @MainActor in self.terminate() }
                return
            }
            if let metadata = context?.protocolMetadata.first as? NWProtocolWebSocket.Metadata,
               metadata.opcode == .close {
                Task { @MainActor in self.terminate() }
                return
            }
            if let data, !data.isEmpty {
                Task { @MainActor in self.handleFrame(data: data) }
            }
            self.receiveLoop()
        }
    }

    private func handleFrame(data: Data) {
        let frame: BridgeFrame
        do {
            frame = try BridgeCoder.decode(data)
        } catch {
            send(BridgeFrame(.errorEvent(code: "decode", message: "\(error)")))
            return
        }
        if frame.schemaVersion != bridgeSchemaVersion {
            send(BridgeFrame(.versionMismatch(serverVersion: bridgeSchemaVersion)))
            close(.protocolCode(.protocolError))
            return
        }
        if !isAuthenticated {
            if case .auth(let token, let name) = frame.body {
                handleAuth(token: token, deviceName: name)
            } else {
                send(BridgeFrame(.authFailed(reason: "auth-required-first")))
                close(.protocolCode(.policyViolation))
            }
            return
        }
        BridgeIntent.dispatch(body: frame.body, appState: appState, bus: bus, session: self)
    }

    private func handleAuth(token: String, deviceName: String?) {
        // Phase 2: plaintext. Any non-empty token is accepted to let
        // the smoke-test client connect. Phase 5 swaps this for a
        // keychain-backed bearer compare.
        guard !token.isEmpty else {
            send(BridgeFrame(.authFailed(reason: "empty-token")))
            close(.protocolCode(.policyViolation))
            return
        }
        isAuthenticated = true
        self.deviceName = deviceName
        send(BridgeFrame(.authOk(macName: Host.current().localizedName)))
        send(BridgeFrame(.chatsSnapshot(chats: bus.currentChats())))
    }

    func send(_ frame: BridgeFrame) {
        let data: Data
        do {
            data = try BridgeCoder.encode(frame)
        } catch {
            return
        }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "send", metadata: [metadata])
        connection.send(
            content: data,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { _ in }
        )
    }

    func close(_ code: NWProtocolWebSocket.CloseCode = .protocolCode(.normalClosure)) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .close)
        metadata.closeCode = code
        let context = NWConnection.ContentContext(identifier: "close", metadata: [metadata])
        connection.send(
            content: nil,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { [weak self] _ in
                Task { @MainActor in self?.terminate() }
            }
        )
    }

    private func terminate() {
        guard !didTerminate else { return }
        didTerminate = true
        connection.cancel()
        onTerminated(id)
    }
}
