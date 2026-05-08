import Foundation
import Network
import ClawixCore

/// Local-network WS server that exposes an `EngineHost` (the macOS
/// `AppState` today, the LaunchAgent daemon's engine tomorrow) to the
/// iPhone companion and to a co-located desktop client. Phase 2 is
/// plaintext; TLS + cert pinning lands later.
@MainActor
public final class BridgeServer {
    private weak var host: EngineHost?
    private let port: NWEndpoint.Port
    private let pairing: PairingService
    private let publishBonjour: Bool
    private var listener: NWListener?
    private var bus: BridgeBus?
    private var sessions: [BridgeSession] = []

    public private(set) var isRunning: Bool = false

    /// - Parameter publishBonjour: when true (default), the listener
    ///   advertises itself over `_clawix-bridge._tcp` so the iPhone
    ///   companion's `NWBrowser` discovers it. The daemon currently
    ///   ships an `EmptyEngineHost` stub, so it skips Bonjour to
    ///   avoid racing the GUI for the iPhone's attention until it
    ///   owns real chat state.
    public init(
        host: EngineHost,
        port: UInt16 = 7777,
        pairing: PairingService = .shared,
        publishBonjour: Bool = true
    ) {
        self.host = host
        self.port = NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(rawValue: 7777)!
        self.pairing = pairing
        self.publishBonjour = publishBonjour
    }

    public func start() {
        guard !isRunning, let host else { return }
        do {
            let params = NWParameters.tcp
            let ws = NWProtocolWebSocket.Options()
            ws.autoReplyPing = true
            params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
            params.allowLocalEndpointReuse = true

            let listener = try NWListener(using: params, on: port)
            if publishBonjour {
                // Publish over Bonjour so the iPhone can discover us
                // by service type even if its stored LAN IP is stale
                // (Mac moved networks, DHCP gave a different lease).
                // The iPhone primes its Local Network permission
                // against this exact service type, so publishing here
                // makes the permission dialog reach the user the
                // first time.
                listener.service = NWListener.Service(
                    name: pairing.bonjourServiceName,
                    type: "_clawix-bridge._tcp"
                )
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.accept(connection)
                }
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let err) = state {
                    print("[BridgeServer] listener failed: \(err)")
                }
            }
            listener.start(queue: .main)
            self.listener = listener

            let bus = BridgeBus(host: host)
            bus.startObserving { [weak self] frame in
                self?.broadcast(frame)
            }
            self.bus = bus

            isRunning = true
            BridgeLog.write("server-listening tcp/\(port.rawValue) bonjour=\(publishBonjour)")
        } catch {
            BridgeLog.write("server-listen-failed \(error)")
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        bus?.stop()
        bus = nil
        for session in sessions {
            session.close(.protocolCode(.goingAway))
        }
        sessions.removeAll()
        BridgeStats.shared.reset()
        isRunning = false
    }

    private func accept(_ connection: NWConnection) {
        guard let host, let bus else {
            connection.cancel()
            return
        }
        let session = BridgeSession(
            connection: connection,
            host: host,
            bus: bus,
            pairing: pairing,
            onTerminated: { [weak self] sid in
                Task { @MainActor in
                    self?.sessions.removeAll { $0.id == sid }
                }
            }
        )
        sessions.append(session)
        session.start()
    }

    private func broadcast(_ frame: BridgeFrame) {
        for session in sessions where session.isAuthenticated {
            session.send(frame)
        }
    }
}
