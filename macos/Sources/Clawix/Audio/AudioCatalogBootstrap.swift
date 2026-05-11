import Foundation
import ClawixEngine
#if canImport(Combine)
import Combine
#endif

/// One-shot orchestrator that wires `EngineHost.audioCatalogClient` to
/// the running `@clawjs/audio` supervisor service. Subscribes to the
/// supervisor's per-service snapshot stream and, the first time the
/// audio service reports `.ready` (or `.readyFromDaemon`), constructs
/// a `ClawJSAudioClient` against the right port and runs the legacy
/// `AudioMessageStore` migration in the background.
///
/// Lives in `Clawix` (not in `ClawixEngine`) because it depends on the
/// macOS-only `ClawJSServiceManager` to read the per-session bearer
/// token. The shared `EngineHost` protocol still exposes the client
/// via a default getter that reads `AudioCatalogBootstrap.shared.currentClient`.
@MainActor
final class AudioCatalogBootstrap: ObservableObject {

    static let shared = AudioCatalogBootstrap()

    @Published private(set) var currentClient: ClawJSAudioClient?
    @Published private(set) var migrationCount: Int?

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
        runMigration(client: client)
    }

    private func resolveBearerToken() -> String? {
        if let token = ClawJSServiceManager.shared.adminTokenIfSpawned(for: .audio) {
            return token
        }
        return try? ClawJSServiceManager.adminTokenFromDataDir(for: .audio)
    }

    private func runMigration(client: ClawJSAudioClient) {
        Task { @MainActor in
            do {
                let outcome = try await AudioCatalogMigration.migrateIfNeeded(client: client)
                switch outcome {
                case .migrated(let count):
                    self.migrationCount = count
                case .alreadyMigrated, .noLegacyData:
                    self.migrationCount = 0
                }
            } catch {
                // Migration is idempotent; on failure we leave the marker
                // absent so the next boot tries again. The error surfaces
                // through the supervisor's log file.
            }
        }
    }
}
