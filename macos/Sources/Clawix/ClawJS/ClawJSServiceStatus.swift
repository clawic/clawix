import Foundation

/// The three ClawJS services Phase 2 supervises in-process. Each is a
/// long-lived HTTP server bound to loopback. Ports are stable across
/// launches so Phase 3 (Settings UI) and Phase 4 (feature consumers)
/// can hardcode endpoints.
enum ClawJSService: String, CaseIterable, Identifiable {
    case database
    case memory
    case drive
    case vault

    var id: String { rawValue }

    /// Loopback port. Picked far from the bridge's `7778` so a
    /// runaway service does not collide with the daemon.
    var port: UInt16 {
        switch self {
        case .database: return 7790
        case .memory:   return 7791
        case .drive:    return 7792
        case .vault:    return 7793
        }
    }

    var displayName: String {
        switch self {
        case .database: return "Database"
        case .memory:   return "Memory"
        case .drive:    return "Drive"
        case .vault:    return "Vault"
        }
    }

    /// Path the supervisor probes to confirm liveness. Database and Drive
    /// both expose `/v1/health`; Memory does not yet expose a health
    /// route in the source, so we fall back to the same path on the
    /// expectation that ClawJS will normalize. If a service starts and
    /// the probe is wrong, the supervisor's "did not become ready"
    /// timeout flips it to `.crashed` quickly and the log explains.
    var healthPath: String { "/v1/health" }
}

/// Lifecycle state Phase 3's UI binds to. Keep this enum small and the
/// transitions obvious; the manager is the only writer.
enum ClawJSServiceState: Equatable {
    /// Manager has not attempted to launch this service yet (e.g.
    /// pre-`start()` or after a clean tearDown).
    case idle

    /// The bundled CLI does not currently expose a way to launch this
    /// service. The reason explains which gap blocks us; the manager
    /// will retry the moment that gap closes (one method swap inside
    /// `ClawJSServiceManager`).
    case blocked(reason: String)

    /// Spawn requested, waiting for `/healthz` to confirm liveness.
    case starting

    /// Service alive on its port.
    case ready(pid: pid_t, port: UInt16)

    /// Process exited unexpectedly. The manager will restart with
    /// exponential backoff unless `restartCount` exceeds the budget.
    case crashed(reason: String)

    /// `BackgroundBridgeService.isActive == true`: the bridge daemon
    /// owns long-lived services in that mode (Phase 5). The GUI
    /// supervisor stays out so we never have two owners of the same
    /// loopback port.
    case suspendedForDaemon
}

/// Per-service snapshot the manager publishes. UI reads only; mutation
/// happens through the manager's `update(_:_:)` helper.
struct ClawJSServiceSnapshot: Equatable, Identifiable {
    let service: ClawJSService
    var state: ClawJSServiceState
    var lastTransitionAt: Date
    var restartCount: Int
    var lastError: String?

    var id: ClawJSService.ID { service.id }
}
