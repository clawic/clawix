import Foundation
import Network
import ClawixCore

/// Local-network WS server that exposes `AppState` to the iOS
/// companion. Phase 2 is plaintext (no TLS, no Bonjour); Phase 5 will
/// add TLS with cert pinning + bearer auth.
@MainActor
final class BridgeServer {
    private weak var appState: AppState?
    private let port: NWEndpoint.Port
    private var listener: NWListener?
    private var bus: BridgeBus?
    private var sessions: [BridgeSession] = []

    private(set) var isRunning: Bool = false

    init(appState: AppState, port: UInt16 = 7777) {
        self.appState = appState
        self.port = NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(rawValue: 7777)!
    }

    func start() {
        guard !isRunning, let appState else { return }
        do {
            let params = NWParameters.tcp
            let ws = NWProtocolWebSocket.Options()
            ws.autoReplyPing = true
            params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
            params.allowLocalEndpointReuse = true

            let listener = try NWListener(using: params, on: port)
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

            let bus = BridgeBus(appState: appState)
            bus.startObserving { [weak self] frame in
                self?.broadcast(frame)
            }
            self.bus = bus

            isRunning = true
            print("[BridgeServer] listening on tcp/\(port.rawValue)")
        } catch {
            print("[BridgeServer] failed to start: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        bus?.stop()
        bus = nil
        for session in sessions {
            session.close(.protocolCode(.goingAway))
        }
        sessions.removeAll()
        isRunning = false
    }

    private func accept(_ connection: NWConnection) {
        guard let appState, let bus else {
            connection.cancel()
            return
        }
        let session = BridgeSession(
            connection: connection,
            appState: appState,
            bus: bus,
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
