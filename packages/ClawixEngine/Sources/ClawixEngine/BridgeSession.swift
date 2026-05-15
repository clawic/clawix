import Foundation
import ClawixCore

#if canImport(Network)
import Network

/// One client of the bridge (an iPhone or a co-located desktop GUI).
/// Owns the `NWConnection`, drives the receive loop, gates frames
/// behind a successful `auth`. The bridge accepts the stable bearer
/// or current short code minted by `PairingService`.
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
    public private(set) var clientId: String?
    public private(set) var installationId: String?
    public private(set) var deviceId: String?
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
        // Strict schema match for the v1 bridge. Any mismatch gets a
        // `versionMismatch` before close so the client knows to update.
        if frame.schemaVersion != bridgeSchemaVersion {
            send(BridgeFrame(.versionMismatch(serverVersion: bridgeSchemaVersion)))
            close(.protocolCode(.protocolError))
            return
        }
        if !isAuthenticated {
            if case .auth(let token, let name, let kind, let clientId, let installationId, let deviceId) = frame.body {
                handleAuth(
                    token: token,
                    deviceName: name,
                    clientKind: kind,
                    clientId: clientId,
                    installationId: installationId,
                    deviceId: deviceId
                )
            } else {
                send(BridgeFrame(.authFailed(reason: "auth-required-first")))
                close(.protocolCode(.policyViolation))
            }
            return
        }
        BridgeIntent.dispatch(body: frame.body, host: host, bus: bus, session: self)
    }

    private func handleAuth(
        token: String,
        deviceName: String?,
        clientKind: ClientKind,
        clientId: String,
        installationId: String,
        deviceId: String
    ) {
        guard [clientId, installationId, deviceId].allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            BridgeLog.write("auth-fail reason=invalid-client-identity name=\(deviceName ?? "?")")
            send(BridgeFrame(.authFailed(reason: "invalid-client-identity")))
            close(.protocolCode(.policyViolation))
            return
        }
        // The v1 auth field is `token`; it accepts either the long QR
        // bearer or the human-typeable short code.
        let valid = pairing.acceptToken(token) || pairing.acceptShortCode(token)
        guard valid else {
            BridgeLog.write("auth-fail reason=bad-token name=\(deviceName ?? "?")")
            send(BridgeFrame(.authFailed(reason: "bad-token")))
            close(.protocolCode(.policyViolation))
            return
        }
        isAuthenticated = true
        BridgeStats.shared.increment()
        self.deviceName = deviceName
        self.clientKind = clientKind
        self.clientId = clientId
        self.installationId = installationId
        self.deviceId = deviceId
        // Tell the peer where the host is in its bootstrap so an empty
        // chats list reads as "syncing" instead of "no chats". The bus
        // also re-emits this frame on every state transition, so a
        // peer that connected during boot sees `syncing → ready`.
        send(BridgeFrame(.authOk(hostDisplayName: HostIdentity.localizedName)))
        send(bus.currentBridgeStateFrame())
        send(BridgeFrame(.sessionsSnapshot(sessions: bus.currentSessions())))
        BridgeLog.write("peer-connect kind=\(clientKind.rawValue) clientId=\(clientId) deviceId=\(deviceId) name=\(deviceName ?? "?")")
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
        if isAuthenticated {
            BridgeStats.shared.decrement()
        }
        connection.cancel()
        onTerminated(id)
    }
}
#endif
