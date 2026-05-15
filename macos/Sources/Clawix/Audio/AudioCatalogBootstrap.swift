import Foundation
import ClawixEngine
#if canImport(Combine)
import Combine
#endif

/// One-shot orchestrator that wires `EngineHost.audioCatalogClient` to
/// the running `@clawjs/audio` supervisor service. Subscribes to the
/// supervisor's per-service snapshot stream and, the first time the
/// audio service reports `.ready` (or `.readyFromDaemon`), constructs
/// a `ClawJSAudioClient` against the right port.
///
/// Lives in `Clawix` (not in `ClawixEngine`) because it depends on the
/// macOS-only `ClawJSServiceManager` to read the per-session bearer
/// token. The shared `EngineHost` protocol still exposes the client
/// via a default getter that reads `AudioCatalogBootstrap.shared.currentClient`.
@MainActor
final class AudioCatalogBootstrap: ObservableObject {

    static let shared = AudioCatalogBootstrap()

    @Published private(set) var currentClient: ClawJSAudioClient?
    private var cancellable: AnyCancellable?
    private var didStart = false

    private init() {}

    func start(manager: ClawJSServiceManager = .shared) {
        guard !didStart else { return }
        didStart = true
        cancellable = manager.$snapshots
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshots in
                self?.handle(snapshots: snapshots)
            }
    }

    private func handle(snapshots: [ClawJSService: ClawJSServiceSnapshot]) {
        guard let snap = snapshots[.audio] else { return }
        switch snap.state {
        case .ready(_, let port), .readyFromDaemon(let port):
            installClient(port: port)
        default:
            break
        }
    }

    private func installClient(port: UInt16) {
        if currentClient != nil { return }
        guard let token = resolveBearerToken() else { return }
        let origin = URL(string: "http://127.0.0.1:\(port)")!
        let client = ClawJSAudioClient(bearerToken: token, origin: origin)
        currentClient = client
    }

    private func resolveBearerToken() -> String? {
        if let token = ClawJSServiceManager.shared.adminTokenIfSpawned(for: .audio) {
            return token
        }
        return try? ClawJSServiceManager.adminTokenFromTokenFile(for: .audio)
    }

}
