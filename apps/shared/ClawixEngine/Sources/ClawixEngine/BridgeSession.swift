import Foundation
import Network
import ClawixCore

/// One client of the bridge (an iPhone or a co-located desktop GUI).
/// Owns the `NWConnection`, drives the receive loop, gates frames
/// behind a successful `auth`. The Phase 2 build accepts any bearer
/// matching `PairingService.shared.bearer`; TLS + cert pinning lands
/// later.
@MainActor
public final class BridgeSession: Identifiable {
    public let id = UUID()
    private let connection: NWConnection
    private weak var host: EngineHost?
    private let bus: BridgeBus
    private let pairing: PairingService
    private let onTerminated: (UUID) -> Void

    public private(set) var isAuthenticated: Bool = false
    public private(set) var deviceName: String?
    public private(set) var clientKind: ClientKind?
    private var didTerminate = false

    public init(
        connection: NWConnection,
        host: EngineHost,
        bus: BridgeBus,
        pairing: PairingService,
        onTerminated: @escaping (UUID) -> Void
    ) {
        self.connection = connection
        self.host = host
        self.bus = bus
        self.pairing = pairing
        self.onTerminated = onTerminated
    }

    public func start() {
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
        // Strict major-version match. v1 frames decode under v2 (every
        // new field is optional), so we only refuse frames we genuinely
        // can't interpret. Anything else gets a `versionMismatch`
        // before close so the client knows to update.
        if frame.schemaVersion > bridgeSchemaVersion {
            send(BridgeFrame(.versionMismatch(serverVersion: bridgeSchemaVersion)))
            close(.protocolCode(.protocolError))
            return
        }
        if !isAuthenticated {
            if case .auth(let token, let name, let kind) = frame.body {
                handleAuth(token: token, deviceName: name, clientKind: kind)
            } else {
                send(BridgeFrame(.authFailed(reason: "auth-required-first")))
                close(.protocolCode(.policyViolation))
            }
            return
        }
        BridgeIntent.dispatch(body: frame.body, host: host, bus: bus, session: self)
    }

    private func handleAuth(token: String, deviceName: String?, clientKind: ClientKind?) {
        guard pairing.acceptToken(token) else {
            send(BridgeFrame(.authFailed(reason: "bad-token")))
            close(.protocolCode(.policyViolation))
            return
        }
        isAuthenticated = true
        self.deviceName = deviceName
        // Absent kind = legacy v1 client = treat as iOS so existing
        // iPhones keep working unchanged.
        self.clientKind = clientKind ?? .ios
        send(BridgeFrame(.authOk(macName: Host.current().localizedName)))
        send(BridgeFrame(.chatsSnapshot(chats: bus.currentChats())))
    }

    public func send(_ frame: BridgeFrame) {
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

    public func close(_ code: NWProtocolWebSocket.CloseCode = .protocolCode(.normalClosure)) {
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
