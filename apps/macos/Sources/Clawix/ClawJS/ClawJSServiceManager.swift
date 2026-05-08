import Foundation

/// In-process supervisor for the ClawJS sidecar services
/// (database / memory / drive). One singleton owns three Process
/// instances, one log file per service, one `/healthz` poller per
/// service, and the restart-with-backoff state machine.
///
/// Today, `commandLine(for:)` returns `nil` for every service because
/// `@clawjs/cli@\(ClawJSRuntime.expectedVersion)` does not yet expose a
/// service-launch surface. The manager publishes `.blocked(reason:)`
/// for each, and the spawn pipeline below stays dormant. The moment the
/// CLI ships `claw open <service>` (or per-service serve commands),
/// updating that one method enables the entire supervisor with no
/// further plumbing changes here.
///
/// When `BackgroundBridgeService.isActive == true`, services move to
/// `.suspendedForDaemon`: Phase 5 will host them inside `clawix-bridged`
/// so iOS pairing benefits from shared state.
@MainActor
final class ClawJSServiceManager: ObservableObject {

    static let shared = ClawJSServiceManager()

    /// Per-service published state. Phase 3's UI observes this dict;
    /// Phase 4 consumers read `state == .ready(_, port)` to know they
    /// can connect.
    @Published private(set) var snapshots: [ClawJSService: ClawJSServiceSnapshot]

    /// Restart budget per service. After this many crashes inside one
    /// boot the manager gives up and parks the service in `.crashed`
    /// with an explanatory reason instead of looping forever.
    static let restartBudget = 5

    /// Backoff schedule (seconds): 1, 2, 4, 8, 16, capped at 60. Used
    /// when a process crashes; reset to zero after the service stays
    /// healthy for `healthyResetWindow`.
    private static let backoffSchedule: [UInt64] = [1, 2, 4, 8, 16, 32, 60]
    private static let healthyResetWindow: TimeInterval = 60

    private var processes: [ClawJSService: Process] = [:]
    private var logHandles: [ClawJSService: FileHandle] = [:]
    private var healthTasks: [ClawJSService: Task<Void, Never>] = [:]
    private var restartTasks: [ClawJSService: Task<Void, Never>] = [:]
    private var lastReadyAt: [ClawJSService: Date] = [:]

    private let bridgeService: BackgroundBridgeService

    private init(bridgeService: BackgroundBridgeService = .shared) {
        self.bridgeService = bridgeService
        let now = Date()
        var seed: [ClawJSService: ClawJSServiceSnapshot] = [:]
        for service in ClawJSService.allCases {
            seed[service] = ClawJSServiceSnapshot(
                service: service,
                state: .idle,
                lastTransitionAt: now,
                restartCount: 0,
                lastError: nil
            )
        }
        self.snapshots = seed
    }

    // MARK: - Public API

    /// Boots all three services. Idempotent: a service in `.starting`
    /// or `.ready` is left alone. Skips entirely when the bridge daemon
    /// is active (Phase 5 owns services in that mode).
    func start() async {
        if bridgeService.isActive {
            for service in ClawJSService.allCases {
                update(service) { $0.state = .suspendedForDaemon }
            }
            return
        }
        for service in ClawJSService.allCases {
            await launch(service)
        }
    }

    /// Forces a single service back through the launch pipeline. Resets
    /// the restart counter so a service in `.crashed (budget exhausted)`
    /// gets another shot. Used by the Settings UI's "Restart" button.
    func restart(_ service: ClawJSService) async {
        restartTasks[service]?.cancel()
        restartTasks[service] = nil
        if let process = processes[service], process.isRunning {
            process.terminate()
        }
        update(service) {
            $0.restartCount = 0
            $0.lastError = nil
            $0.state = .idle
        }
        await launch(service)
    }

    /// Synchronous SIGTERM to every running service plus cancellation of
    /// pending restart / healthz tasks. Safe to call from
    /// `applicationWillTerminate` (which cannot `await`). macOS SIGKILLs
    /// any straggler when the parent process exits, so this is enough
    /// for the shutdown path; the `tearDown()` async variant exists for
    /// explicit teardown during tests or hot-reload flows.
    nonisolated func terminateAllSynchronously() {
        MainActor.assumeIsolated {
            for task in restartTasks.values { task.cancel() }
            restartTasks.removeAll()
            for task in healthTasks.values { task.cancel() }
            healthTasks.removeAll()
            for process in processes.values where process.isRunning {
                process.terminate()
            }
        }
    }

    /// SIGTERM with a 3 s grace, then SIGKILL stragglers. Cancels every
    /// pending restart and `/healthz` task so nothing tries to re-spawn
    /// while the app is going down. Used by tests and hot-reload paths;
    /// the production `applicationWillTerminate` uses
    /// `terminateAllSynchronously()` instead because it cannot await.
    func tearDown() async {
        for task in restartTasks.values { task.cancel() }
        restartTasks.removeAll()
        for task in healthTasks.values { task.cancel() }
        healthTasks.removeAll()

        let running = processes
        processes.removeAll()

        for process in running.values {
            process.terminate()
        }

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline,
              running.values.contains(where: { $0.isRunning }) {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        for process in running.values where process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        for handle in logHandles.values {
            try? handle.close()
        }
        logHandles.removeAll()

        for service in ClawJSService.allCases {
            update(service) { $0.state = .idle }
        }
    }

    // MARK: - Per-service launch

    private func launch(_ service: ClawJSService) async {
        switch snapshots[service]?.state {
        case .starting, .ready:
            return
        default:
            break
        }

        // Guard 1: the bundled tree must exist. dev.sh / build_release_app.sh
        // call `bundle_clawjs.sh` to plant Contents/Helpers/clawjs/; if that
        // step was skipped or failed, we cannot spawn anything.
        guard ClawJSRuntime.isAvailable else {
            update(service) {
                $0.state = .blocked(reason:
                    "ClawJS bundle missing at \(ClawJSRuntime.bundleRootURL.path). Run bundle_clawjs.sh.")
            }
            return
        }

        // Guard 2: the CLI must expose a service-launch command. As long
        // as `commandLine(for:)` returns nil, the supervisor stays in
        // `.blocked` and nothing is spawned. This is THE swap point when
        // ClawJS publishes the service-launch surface.
        guard commandLine(for: service) != nil else {
            update(service) {
                $0.state = .blocked(reason:
                    "@clawjs/cli@\(ClawJSRuntime.expectedVersion) does not expose a service-launch command yet")
            }
            return
        }

        await spawnAndSupervise(service)
    }

    /// Argv (without the leading node binary) to launch `service` as a
    /// long-lived HTTP server on `service.port`. Returns `nil` while the
    /// bundled CLI lacks the surface.
    ///
    /// THIS IS THE ONE METHOD TO UPDATE WHEN THE PUBLISHED `@clawjs/cli`
    /// SHIPS A SERVICE-LAUNCH SURFACE. Suggested shape once it lands:
    ///
    ///     [
    ///       ClawJSRuntime.cliScriptURL.path,
    ///       "open", service.rawValue,
    ///       "--port", String(service.port),
    ///       "--workspace", Self.workspaceURL.path,
    ///       "--status-file", Self.statusFileURL(for: service).path,
    ///     ]
    private func commandLine(for service: ClawJSService) -> [String]? {
        // Vault and Database are wired: `claw open <service>` launches the
        // bundled server with deterministic port + workspace + status
        // file. Memory and Drive stay blocked until @clawjs/cli ships
        // their service-launch surface; flipping each to non-nil here is
        // the only change needed when that happens.
        switch service {
        case .vault, .database:
            return [
                ClawJSRuntime.cliScriptURL.path,
                "open", service.rawValue,
                "--port", String(service.port),
                "--workspace", Self.workspaceURL.path,
                "--status-file", Self.statusFileURL(for: service).path,
            ]
        case .memory, .drive:
            return nil
        }
    }

    // MARK: - Spawn + supervise

    /// Full spawn pipeline. Dormant today (commandLine returns nil), but
    /// fully wired so flipping that one method enables the whole flow.
    private func spawnAndSupervise(_ service: ClawJSService) async {
        guard let extraArgs = commandLine(for: service) else { return }
        update(service) { $0.state = .starting; $0.lastError = nil }

        do {
            try Self.prepareDirectories(for: service)

            let process = Process()
            process.executableURL = ClawJSRuntime.nodeBinaryURL
            process.arguments = extraArgs
            process.currentDirectoryURL = Self.workspaceURL
            process.environment = Self.environment(for: service)

            let logURL = Self.logFileURL(for: service)
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            process.standardOutput = handle
            process.standardError = handle
            logHandles[service] = handle

            process.terminationHandler = { [weak self] proc in
                Task { @MainActor [weak self] in
                    self?.handleTermination(of: service, process: proc)
                }
            }

            try process.run()
            processes[service] = process

            // Healthz poller flips state to `.ready` once the service
            // responds; it also detects soft hangs (process alive but no
            // longer answering) and triggers a restart.
            healthTasks[service]?.cancel()
            healthTasks[service] = Task { [weak self] in
                await self?.pollHealth(for: service, pid: process.processIdentifier)
            }
        } catch {
            update(service) {
                $0.state = .crashed(reason: "spawn failed: \(error.localizedDescription)")
                $0.lastError = error.localizedDescription
            }
            scheduleRestart(service)
        }
    }

    private func handleTermination(of service: ClawJSService, process proc: Process) {
        guard processes[service] === proc else { return }
        processes[service] = nil
        try? logHandles[service]?.close()
        logHandles[service] = nil
        healthTasks[service]?.cancel()
        healthTasks[service] = nil

        let status = proc.terminationStatus
        let signalled = proc.terminationReason == .uncaughtSignal
        if status == 0 || signalled {
            // Clean exit (most likely tearDown). Park as idle, no restart.
            update(service) { $0.state = .idle }
            return
        }
        update(service) {
            $0.state = .crashed(reason: "exit status \(status)")
            $0.lastError = "exit \(status)"
        }
        scheduleRestart(service)
    }

    private func scheduleRestart(_ service: ClawJSService) {
        guard var snap = snapshots[service] else { return }
        // Reset the counter if the service was alive long enough since
        // its last `.ready` transition.
        if let lastReady = lastReadyAt[service],
           Date().timeIntervalSince(lastReady) > Self.healthyResetWindow {
            snap.restartCount = 0
            snapshots[service] = snap
        }
        guard snap.restartCount < Self.restartBudget else {
            update(service) {
                $0.state = .crashed(reason: "restart budget (\(Self.restartBudget)) exhausted; not retrying")
            }
            return
        }
        let delay = Self.backoffSchedule[min(snap.restartCount, Self.backoffSchedule.count - 1)]
        update(service) { $0.restartCount += 1 }

        restartTasks[service]?.cancel()
        restartTasks[service] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.launch(service)
        }
    }

    // MARK: - Healthz

    private func pollHealth(for service: ClawJSService, pid: pid_t) async {
        let url = URL(string: "http://127.0.0.1:\(service.port)\(service.healthPath)")!
        var consecutiveFailures = 0
        let readyDeadline = Date().addingTimeInterval(15)
        var hasReachedReady = false

        while !Task.isCancelled {
            // Bail out if the process is gone — the termination handler
            // takes care of state transitions.
            guard let process = processes[service], process.isRunning else { return }

            let alive = await ping(url: url)
            if alive {
                consecutiveFailures = 0
                if !hasReachedReady {
                    hasReachedReady = true
                    lastReadyAt[service] = Date()
                    update(service) { $0.state = .ready(pid: pid, port: service.port) }
                }
            } else {
                consecutiveFailures += 1
                if !hasReachedReady, Date() > readyDeadline {
                    update(service) {
                        $0.state = .crashed(reason: "did not become ready within 15s")
                    }
                    process.terminate()
                    return
                }
                if hasReachedReady, consecutiveFailures >= 5 {
                    update(service) {
                        $0.state = .crashed(reason: "/healthz silent for 5 consecutive checks")
                    }
                    process.terminate()
                    return
                }
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private func ping(url: URL) async -> Bool {
        var req = URLRequest(url: url)
        req.timeoutInterval = 1
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Paths and environment

    /// Single workspace shared by all three services. SQLite files
    /// land under `<workspace>/.clawjs/data/`.
    static var workspaceURL: URL {
        applicationSupportRoot.appendingPathComponent("workspace", isDirectory: true)
    }

    static var applicationSupportRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clawix/clawjs", isDirectory: true)
    }

    static func logFileURL(for service: ClawJSService) -> URL {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Clawix", isDirectory: true)
        return logs.appendingPathComponent("clawjs-\(service.rawValue).log", isDirectory: false)
    }

    static func statusFileURL(for service: ClawJSService) -> URL {
        applicationSupportRoot
            .appendingPathComponent("status", isDirectory: true)
            .appendingPathComponent("\(service.rawValue).json", isDirectory: false)
    }

    private static func prepareDirectories(for service: ClawJSService) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try fm.createDirectory(
            at: logFileURL(for: service).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fm.createDirectory(
            at: statusFileURL(for: service).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private static func environment(for service: ClawJSService) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = applicationSupportRoot.appendingPathComponent("home").path
        env["CLAWJS_WORKSPACE"] = workspaceURL.path
        env["CLAWJS_PORT"] = String(service.port)
        env["CLAWJS_SERVICE"] = service.rawValue
        return env
    }

    // MARK: - State mutation

    private func update(
        _ service: ClawJSService,
        _ mutate: (inout ClawJSServiceSnapshot) -> Void
    ) {
        guard var snap = snapshots[service] else { return }
        let previousState = snap.state
        mutate(&snap)
        if snap.state != previousState {
            snap.lastTransitionAt = Date()
        }
        snapshots[service] = snap
    }
}
