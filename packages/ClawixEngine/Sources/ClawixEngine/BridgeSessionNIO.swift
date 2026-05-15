#if !canImport(Network)
import Foundation
import NIOCore
import NIOWebSocket
import ClawixCore

/// Linux-side bridge session. Public API mirrors the Apple-side session;
/// all auth/diff/dispatch logic that does NOT depend on transport lives
/// in `BridgeIntent` and is shared.
@MainActor
public final class BridgeSession: Identifiable {
    public let id = UUID()
    private weak var host: EngineHost?
    private let bus: BridgeBus
    private let pairing: PairingService
    private let onTerminated: (UUID) -> Void
    private var channel: Channel?

    public private(set) var isAuthenticated: Bool = false
    public private(set) var deviceName: String?
    public private(set) var clientKind: ClientKind?
    private var didTerminate = false

    public init(
        channel: Channel,
        host: EngineHost,
        bus: BridgeBus,
        pairing: PairingService,
        onTerminated: @escaping (UUID) -> Void
    ) {
        self.channel = channel
        self.host = host
        self.bus = bus
        self.pairing = pairing
        self.onTerminated = onTerminated
    }

    public func start() {}

    func attach(channel: Channel) {
        self.channel = channel
    }

    func handleInbound(data: Data) {
        let frame: BridgeFrame
        do {
            frame = try BridgeCoder.decode(data)
        } catch {
            send(BridgeFrame(.errorEvent(code: "decode", message: "\(error)")))
            return
        }
        if frame.protocolVersion > bridgeProtocolVersion {
            send(BridgeFrame(.versionMismatch(serverVersion: bridgeProtocolVersion)))
            close(.protocolError)
            return
        }
        if !isAuthenticated {
            if case .auth(let token, let name, let kind, _, _, _) = frame.body {
                handleAuth(token: token, deviceName: name, clientKind: kind)
            } else {
                send(BridgeFrame(.authFailed(reason: "auth-required-first")))
                close(.policyViolation)
            }
            return
        }
        BridgeIntent.dispatch(body: frame.body, host: host, bus: bus, session: self)
    }

    private func handleAuth(token: String, deviceName: String?, clientKind: ClientKind?) {
        let valid = pairing.acceptToken(token) || pairing.acceptShortCode(token)
        guard valid else {
            BridgeLog.write("auth-fail reason=bad-token name=\(deviceName ?? "?")")
            send(BridgeFrame(.authFailed(reason: "bad-token")))
            close(.policyViolation)
            return
        }
        isAuthenticated = true
        BridgeStats.shared.increment()
        self.deviceName = deviceName
        self.clientKind = clientKind ?? .companion
        let hostName = ProcessInfo.processInfo.hostName
        send(BridgeFrame(.authOk(hostDisplayName: hostName)))
        send(BridgeFrame(.sessionsSnapshot(sessions: bus.currentSessions())))
        send(bus.currentBridgeStateFrame())
        BridgeLog.write("peer-connect kind=\(self.clientKind?.rawValue ?? "companion") name=\(deviceName ?? "?")")
    }

    public func send(_ frame: BridgeFrame) {
        guard let channel else { return }
        let data: Data
        do {
            data = try BridgeCoder.encode(frame)
        } catch {
            return
        }
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        let wsFrame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
        channel.writeAndFlush(wsFrame, promise: nil)
    }

    public func close(_ code: WebSocketErrorCode = .normalClosure) {
        guard let channel else { return }
        var buffer = channel.allocator.buffer(capacity: 2)
        buffer.write(webSocketErrorCode: code)
        let wsFrame = WebSocketFrame(fin: true, opcode: .connectionClose, data: buffer)
        channel.writeAndFlush(wsFrame).whenComplete { [weak self] _ in
            channel.close(promise: nil)
            Task { @MainActor in self?.terminate() }
        }
    }

    func terminateExternal() {
        terminate()
    }

    private func terminate() {
        guard !didTerminate else { return }
        didTerminate = true
        if isAuthenticated {
            BridgeStats.shared.decrement()
        }
        try? channel?.close().wait()
        channel = nil
        onTerminated(id)
    }
}
#endif
