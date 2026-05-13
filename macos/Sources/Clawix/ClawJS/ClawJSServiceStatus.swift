import Foundation

/// The ClawJS services Phase 2 supervises in-process. Each is a
/// long-lived HTTP server bound to loopback. Ports are stable across
/// launches so Phase 3 (Settings UI) and Phase 4 (feature consumers)
/// can hardcode endpoints.
enum ClawJSService: String, CaseIterable, Identifiable {
    case database
    case memory
    case drive
    case secrets
    case telegram
    case audio
    case iot
    case index
    case publishing
    case sessions

    var id: String { rawValue }

    /// Loopback port from the ClawJS stable service registry. Clawix owns
    /// `24080-24099`; framework services use `24100-24199`.
    var port: UInt16 {
        switch self {
        case .sessions: return 24101
        case .database: return 24102
        case .secrets:  return 24103
        case .drive:    return 24104
        case .memory:   return 24105
        case .index:    return 24106
        case .publishing:   return 24111
        case .telegram: return 24150
        case .audio:    return 24151
        case .iot:      return 24152
        }
    }

    var displayName: String {
        switch self {
        case .database: return "Database"
        case .memory:   return "Memory"
        case .drive:    return "Drive"
        case .secrets:    return "Secrets"
        case .telegram: return "Telegram"
        case .audio:    return "Audio"
        case .iot:      return "IoT"
        case .index:    return "Index"
        case .publishing:   return "Publishing"
        case .sessions: return "Sessions"
        }
    }

    /// Path the supervisor probes to confirm liveness. Database and Drive
    /// both expose `/v1/health`; Memory does not yet expose a health
    /// route in the source, so we fall back to the same path on the
    /// expectation that ClawJS will normalize. Publishing publishes `/healthz`
    /// directly (it does not yet share the `/v1/health` convention).
    var healthPath: String {
        switch self {
        case .publishing: return "/healthz"
        default:      return "/v1/health"
        }
    }
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

    /// Service is alive on its canonical port and is owned by the
    /// background bridge daemon, not by the GUI process.
    case readyFromDaemon(port: UInt16)

    /// Process exited unexpectedly. The manager will restart with
    /// exponential backoff unless `restartCount` exceeds the budget.
    case crashed(reason: String)

    /// `BackgroundBridgeService.isActive == true`, but the service did
    /// not answer on its canonical loopback port.
    case daemonUnavailable(reason: String)

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

extension ClawJSServiceState {
    var isReady: Bool {
        switch self {
        case .ready, .readyFromDaemon:
            return true
        default:
            return false
        }
    }

    var unavailableReason: String? {
        switch self {
        case .blocked(let reason), .crashed(let reason), .daemonUnavailable(let reason):
            return reason
        case .idle:
            return "The service has not started yet."
        case .starting:
            return "The service is still starting."
        case .ready, .readyFromDaemon:
            return nil
        }
    }
}
