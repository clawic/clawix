import Foundation
import SwiftUI
import Combine

/// Observable manager for the clawjs-iot daemon.
///
/// Mirrors `DatabaseManager` in shape: a state machine that observes
/// `ClawJSServiceManager.shared.snapshots[.iot]` and bootstraps once
/// the supervisor flips the service to `.ready` / `.readyFromDaemon`.
/// On bootstrap it loads the tool catalog so downstream consumers
/// (`RemoteToolsRegistry`, the future `.iotHome` screen) can read it
/// synchronously without re-fetching.
///
/// Phase 1 surface is intentionally minimal — only the catalog and the
/// service state. Phase 2 adds typed accessors for homes / things /
/// scenes / automations / approvals plus an SSE realtime consumer for
/// the `device.*` event stream.
@MainActor
final class IoTManager: ObservableObject {

    enum State: Equatable {
        case loading
        case bootstrapping
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var lastError: String?
    @Published private(set) var availableTools: [RemoteToolDescriptor] = []
    @Published private(set) var catalogGeneratedAt: Date?

    private(set) var client = IoTClient()

    private var supervisorObserver: AnyCancellable?
    private var bootstrapGeneration: UUID?

    init() {
        attachSupervisorObserver()
    }

    /// Watches `ClawJSServiceManager.shared.snapshots[.iot]` and kicks
    /// off `bootstrap()` whenever the supervisor flips IoT to `.ready`.
    /// If the daemon crashes and gets restarted we re-issue bootstrap
    /// so the catalog refresh picks up any new tools added by adapter
    /// hot-reload paths.
    private func attachSupervisorObserver() {
        let supervisor = ClawJSServiceManager.shared
        supervisorObserver = supervisor.$snapshots.sink { [weak self] snapshots in
            guard let self else { return }
            guard let snap = snapshots[.iot] else { return }
            switch snap.state {
            case .ready, .readyFromDaemon:
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if case .ready = self.state { return }
                    await self.bootstrap()
                }
            case .crashed, .blocked, .idle, .daemonUnavailable:
                self.availableTools = []
                self.catalogGeneratedAt = nil
                self.state = .failed(snap.state.unavailableReason ?? "IoT service is unavailable.")
            case .starting:
                if case .ready = self.state { /* drain catalog on next ready */ }
                self.state = .bootstrapping
            }
        }
    }

    /// Loads the tool catalog and (if Phase 1 grows mutating verbs in a
    /// later iteration) authenticates the HTTP client with a fresh
    /// bearer token. Idempotent.
    func bootstrap() async {
        if case .ready = state { return }
        state = .bootstrapping
        let generation = UUID()
        bootstrapGeneration = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, self.bootstrapGeneration == generation else { return }
            if case .bootstrapping = self.state {
                self.state = .failed("IoT service did not become ready within 8 seconds.")
            }
        }
        client.bearerToken = IoTAdminToken.currentAdminToken()
        do {
            let catalog = try await client.listTools()
            availableTools = catalog.tools
            catalogGeneratedAt = ISO8601DateFormatter().date(from: catalog.generatedAt)
            state = .ready
            lastError = nil
            bootstrapGeneration = nil
        } catch {
            state = .failed(error.localizedDescription)
            lastError = error.localizedDescription
            bootstrapGeneration = nil
        }
    }

    /// Refreshes the tool catalog without going through the full
    /// bootstrap dance. Useful when an adapter (Phase 2) reports it
    /// added a new device kind whose tools should appear immediately.
    func refreshCatalog() async {
        guard case .ready = state else { return }
        do {
            let catalog = try await client.listTools()
            availableTools = catalog.tools
            catalogGeneratedAt = ISO8601DateFormatter().date(from: catalog.generatedAt)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Pass-through invocation. Phase 1 does not gate by riskLevel; the
    /// daemon already enforces the policy table. Phase 2 introduces the
    /// approval flow which intercepts `sensitive` and `catastrophic`
    /// invocations on this side before they leave the app.
    func invokeTool(id: String, arguments: [String: Any]) async throws -> RemoteToolInvocationResult {
        try await client.invokeTool(id: id, arguments: arguments)
    }
}
