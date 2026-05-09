import Foundation

/// In-process supervisor for the ClawJS sidecar services
/// (database / memory / drive). One singleton owns three Process
/// instances, one log file per service, one `/healthz` poller per
/// service, and the restart-with-backoff state machine.
///
/// `commandLine(for:)` maps each service to the concrete command that
/// the bundled ClawJS runtime actually exposes. Services whose launch
/// surface is missing publish `.blocked(reason:)` instead of crashing.
///
/// When a background bridge daemon is actually reachable, the GUI first
/// probes daemon-owned ports. If the daemon is alive but does not serve a
/// ClawJS surface, the GUI falls back to owning that surface locally.
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

    /// Boots all services. Idempotent: a service in `.starting` or
    /// `.ready` is left alone. When the bridge daemon is reachable the GUI
    /// probes daemon-owned loopback ports first, then falls back locally for
    /// surfaces the daemon does not provide.
    func start() async {
        if bridgeService.isDaemonReachable {
            await startDaemonAwareServices()
            return
        }
        for service in ClawJSService.allCases {
            await launchLocal(service)
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
        if bridgeService.isDaemonReachable {
            healthTasks[service]?.cancel()
            update(service) { $0.state = .starting }
            healthTasks[service] = Task { [weak self] in
                await self?.pollDaemonOwnedService(service)
            }
            return
        }
        await launchLocal(service)
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

    private func launchLocal(_ service: ClawJSService, force: Bool = false) async {
        if !force {
            switch snapshots[service]?.state {
            case .starting, .ready, .readyFromDaemon:
                return
            default:
                break
            }
        }

        // Guard 1: the bundled tree must exist. dev.sh / build_release_app.sh
        // call `bundle_clawjs.sh` to plant Contents/Helpers/clawjs/; if that
        // step was skipped or failed, we cannot spawn anything.
        guard ClawJSRuntime.isAvailable else {
            update(service) {
                $0.state = .blocked(reason:
                    "ClawJS bundle is not available in this build. Rebuild with ClawJS bundling enabled.")
            }
            return
        }

        guard commandLine(for: service) != nil else {
            update(service) {
                $0.state = .blocked(reason:
                    "@clawjs/cli@\(ClawJSRuntime.expectedVersion) does not expose a launch command for \(service.displayName)")
            }
            return
        }

        await spawnAndSupervise(service)
    }

    private func startDaemonOwnedProbes() {
        for task in healthTasks.values { task.cancel() }
        healthTasks.removeAll()

        for service in ClawJSService.allCases {
            update(service) {
                $0.lastError = nil
                $0.state = .starting
            }
            healthTasks[service] = Task { [weak self] in
                await self?.pollDaemonOwnedService(service)
            }
        }
    }

    private func startDaemonAwareServices() async {
        for task in healthTasks.values { task.cancel() }
        healthTasks.removeAll()

        for service in ClawJSService.allCases {
            let url = URL(string: "http://127.0.0.1:\(service.port)\(service.healthPath)")!
            if await ping(url: url) {
                lastReadyAt[service] = Date()
                update(service) {
                    $0.state = .readyFromDaemon(port: service.port)
                    $0.lastError = nil
                }
                healthTasks[service] = Task { [weak self] in
                    await self?.pollDaemonOwnedService(service)
                }
            } else if ClawJSRuntime.isAvailable, commandLine(for: service) != nil {
                await launchLocal(service, force: true)
            } else {
                let reason = "\(service.displayName) is not reachable on 127.0.0.1:\(service.port) while the bridge daemon is active."
                update(service) {
                    $0.state = .daemonUnavailable(reason: reason)
                    $0.lastError = reason
                }
            }
        }
    }

    private func pollDaemonOwnedService(_ service: ClawJSService) async {
        let url = URL(string: "http://127.0.0.1:\(service.port)\(service.healthPath)")!
        let readyDeadline = Date().addingTimeInterval(6)
        var wasReady = false

        while !Task.isCancelled {
            let alive = await ping(url: url)
            if alive {
                wasReady = true
                lastReadyAt[service] = Date()
                update(service) {
                    $0.state = .readyFromDaemon(port: service.port)
                    $0.lastError = nil
                }
            } else if wasReady || Date() > readyDeadline {
                if ClawJSRuntime.isAvailable, commandLine(for: service) != nil {
                    await launchLocal(service, force: true)
                    return
                }
                let reason = "\(service.displayName) is not reachable on 127.0.0.1:\(service.port) while the bridge daemon is active."
                update(service) {
                    $0.state = .daemonUnavailable(reason: reason)
                    $0.lastError = reason
                }
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    /// Argv (without the leading node binary) to launch `service` as a
    /// long-lived HTTP server on `service.port`. Returns `nil` while the
    /// bundled runtime lacks that service's surface.
    private func commandLine(for service: ClawJSService) -> [String]? {
        guard Self.bundledLauncherScript(for: service) != nil else { return nil }

        var arguments = [
            ClawJSRuntime.cliScriptURL.path,
            "open", service.rawValue,
            "--host", "127.0.0.1",
            "--port", String(service.port),
            "--workspace", Self.workspaceURL.path,
            "--status-file", Self.statusFileURL(for: service).path,
        ]

        switch service {
        case .database:
            arguments += [
                "--data-dir", Self.dataDirectoryURL(for: service).path,
                "--files-dir", Self.dataDirectoryURL(for: service)
                    .appendingPathComponent("files", isDirectory: true).path,
            ]
            return arguments
        case .vault, .telegram:
            return arguments
        case .memory, .drive:
            arguments += ["--data-dir", Self.dataDirectoryURL(for: service).path]
            return arguments
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
            await self?.launchLocal(service)
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
        let env = ProcessInfo.processInfo.environment
        if env["CLAWIX_DUMMY_MODE"] == "1", let root = env["CLAWIX_CLAWJS_ROOT"], !root.isEmpty {
            return URL(fileURLWithPath: root, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
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
        try fm.createDirectory(
            at: dataDirectoryURL(for: service),
            withIntermediateDirectories: true
        )
    }

    private static func environment(for service: ClawJSService) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = applicationSupportRoot.appendingPathComponent("home").path
        env["CLAWJS_WORKSPACE"] = workspaceURL.path
        env["CLAWJS_PORT"] = String(service.port)
        env["CLAWJS_SERVICE"] = service.rawValue
        env["PORT"] = String(service.port)
        env["HOST"] = "127.0.0.1"
        env["DATABASE_HOST"] = "127.0.0.1"
        env["DATABASE_PORT"] = String(ClawJSService.database.port)
        env["DATABASE_DATA_DIR"] = dataDirectoryURL(for: .database).path
        env["DRIVE_HOST"] = "127.0.0.1"
        env["DRIVE_PORT"] = String(ClawJSService.drive.port)
        env["DRIVE_DATA_DIR"] = dataDirectoryURL(for: .drive).path
        env["VAULT_HOST"] = "127.0.0.1"
        env["VAULT_PORT"] = String(ClawJSService.vault.port)
        env["VAULT_DATA_DIR"] = dataDirectoryURL(for: .vault).path
        // The Telegram surface reads its own variables (the CLI normally
        // sets these, but pin them here too so a hand-launched `npm start`
        // lines up with what the Swift client expects).
        if service == .telegram {
            env["CLAWJS_TELEGRAM_PORT"] = String(service.port)
            env["CLAWJS_TELEGRAM_WORKSPACE"] = workspaceURL.path
        }
        return env
    }

    private static func dataDirectoryURL(for service: ClawJSService) -> URL {
        workspaceURL
            .appendingPathComponent(".clawjs", isDirectory: true)
            .appendingPathComponent(service.rawValue, isDirectory: true)
    }

    private static func bundledLauncherScript(for service: ClawJSService) -> URL? {
        let url = ClawJSRuntime.bundleRootURL.appendingPathComponent(
            "node_modules/@clawjs/cli/bin/\(service.rawValue)-server-launcher.mjs",
            isDirectory: false
        )
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
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
