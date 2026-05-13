import Foundation
import SecretsCrypto

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

    /// Per-session admin tokens (32-byte URL-safe random) injected to the
    /// daemons that authenticate admin requests. Generated lazily the first
    /// time the GUI spawns each daemon. Replaces the previous Keychain-backed
    /// admin password so the app never touches the system Keychain.
    private var sessionAdminTokens: [ClawJSService: String] = [:]

    /// Maps each service to the env var name its daemon reads to recognise
    /// the per-session admin token. Services that don't use admin tokens
    /// (memory, telegram) are simply absent. The audio service
    /// re-uses the same mechanism: the shared secret is the admin token.
    private static let adminTokenEnvVar: [ClawJSService: String] = [
        .database: "CLAW_DATABASE_ADMIN_TOKEN",
        .drive: "CLAW_DRIVE_ADMIN_TOKEN",
        .secrets: "CLAW_SECRETS_ADMIN_TOKEN",
        .audio: "CLAW_AUDIO_SHARED_SECRET",
        .index: "CLAW_SEARCH_ADMIN_TOKEN",
        .sessions: "CLAW_SESSIONS_SHARED_SECRET",
    ]

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
        let stoppedLocalProcess = await stopTrackedProcess(for: service)
        update(service) {
            $0.restartCount = 0
            $0.lastError = nil
            $0.state = .idle
        }
        if stoppedLocalProcess {
            await launchLocal(service, force: true)
            return
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

    private func stopTrackedProcess(for service: ClawJSService) async -> Bool {
        guard let process = processes.removeValue(forKey: service) else { return false }

        process.terminationHandler = nil
        healthTasks[service]?.cancel()
        healthTasks[service] = nil

        if process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(2)
            while Date() < deadline, process.isRunning {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        try? logHandles[service]?.close()
        logHandles[service] = nil
        return true
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

        guard await preparePortForLocalLaunch(service) else { return }

        // IoT runs from the clawjs/iot package, not from @clawjs/cli, so
        // it bypasses the bundled-runtime guard below. Phase 1 reads the
        // location from a dev pointer dev.sh writes; production builds
        // will substitute a bundled copy under Contents/Resources/.
        if service == .iot {
            guard let projectDir = iotProjectDirectory() else {
                update(service) {
                    $0.state = .blocked(reason:
                        "IoT runtime pointer is missing. Re-run dev.sh to wire it.")
                }
                return
            }
            await spawnIot(projectDir: projectDir)
            return
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

    private func preparePortForLocalLaunch(_ service: ClawJSService) async -> Bool {
        let url = URL(string: "http://127.0.0.1:\(service.port)\(service.healthPath)")!
        guard await ping(url: url) else { return true }

        if Self.canAdoptExistingService(service) {
            lastReadyAt[service] = Date()
            update(service) {
                $0.state = .readyFromDaemon(port: service.port)
                $0.lastError = nil
            }
            healthTasks[service]?.cancel()
            healthTasks[service] = Task { [weak self] in
                await self?.pollDaemonOwnedService(service)
            }
            return false
        }

        guard let pid = Self.listenerPID(on: service.port),
              Self.isClawixSidecar(pid: pid) else {
            let reason = "\(service.displayName) port \(service.port) is already in use by another process."
            update(service) {
                $0.state = .crashed(reason: reason)
                $0.lastError = reason
            }
            return false
        }

        kill(pid, SIGTERM)
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, Self.isRunning(pid: pid) {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if Self.isRunning(pid: pid) {
            kill(pid, SIGKILL)
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return true
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
                if await Self.reclaimOrphanedSidecarIfPossible(service) {
                    await launchLocal(service, force: true)
                } else if Self.canAdoptExistingService(service) {
                    publishDaemonReady(service)
                } else {
                    markReachableServiceUnavailable(service)
                }
                if snapshots[service]?.state == .readyFromDaemon(port: service.port) {
                    healthTasks[service] = Task { [weak self] in
                        await self?.pollDaemonOwnedService(service)
                    }
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
                if await Self.reclaimOrphanedSidecarIfPossible(service) {
                    await launchLocal(service, force: true)
                    return
                } else if Self.canAdoptExistingService(service) {
                    wasReady = true
                    publishDaemonReady(service)
                } else {
                    markReachableServiceUnavailable(service)
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

    private func publishDaemonReady(_ service: ClawJSService) {
        lastReadyAt[service] = Date()
        update(service) {
            $0.state = .readyFromDaemon(port: service.port)
            $0.lastError = nil
        }
    }

    private func markReachableServiceUnavailable(_ service: ClawJSService) {
        let reason = "\(service.displayName) answered on 127.0.0.1:\(service.port), but its admin token is not available."
        update(service) {
            $0.state = .daemonUnavailable(reason: reason)
            $0.lastError = reason
        }
    }

    private nonisolated static func reclaimOrphanedSidecarIfPossible(_ service: ClawJSService) async -> Bool {
        guard let pid = Self.listenerPID(on: service.port),
              Self.isClawixSidecar(pid: pid),
              Self.parentPID(of: pid) == 1 else {
            return false
        }

        kill(pid, SIGTERM)
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, Self.isRunning(pid: pid) {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if Self.isRunning(pid: pid) {
            kill(pid, SIGKILL)
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return true
    }

    /// Argv (without the leading node binary) to launch `service` as a
    /// long-lived HTTP server on `service.port`. Returns `nil` while the
    /// bundled runtime lacks that service's surface.
    private func commandLine(for service: ClawJSService) -> [String]? {
        // IoT does not flow through @clawjs/cli; the dedicated `spawnIot`
        // path owns its argv. Returning nil here keeps the existing
        // `commandLine(for:) != nil` guard a no-op for IoT.
        if service == .iot { return nil }
        // Publishing lives at `node_modules/publishing/dist/server.js`; it has no
        // launcher under `@clawjs/cli/bin/`. Spawn the server entry directly
        // with the bundled node binary so the rest of the supervisor (env,
        // logs, healthz) keeps working as-is.
        if service == .publishing {
            let serverJs = ClawJSRuntime.bundleRootURL
                .appendingPathComponent("node_modules/publishing/dist/server.js", isDirectory: false)
            guard FileManager.default.fileExists(atPath: serverJs.path) else { return nil }
            return [serverJs.path]
        }
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
                "--data-dir", Self.mainDataDirectoryURL.path,
                "--db-path", Self.mainDatabaseURL.path,
                "--files-dir", Self.mainFilesDirectoryURL.path,
            ]
            return arguments
        case .secrets, .telegram:
            return arguments
        case .memory, .drive, .sessions:
            arguments += ["--data-dir", Self.dataDirectoryURL(for: service).path]
            if service == .sessions {
                arguments += [
                    "--db-path", Self.dataDirectoryURL(for: service)
                        .appendingPathComponent("sessions.sqlite", isDirectory: false).path,
                ]
            }
            return arguments
        case .audio:
            arguments += [
                "--data-dir", Self.dataDirectoryURL(for: service).path,
                "--blobs-dir", Self.dataDirectoryURL(for: service)
                    .appendingPathComponent("blobs", isDirectory: true).path,
            ]
            return arguments
        case .index:
            arguments += [
                "--data-dir", Self.dataDirectoryURL(for: service).path,
                "--db-path", Self.dataDirectoryURL(for: service)
                    .appendingPathComponent("index.sqlite", isDirectory: false).path,
            ]
            return arguments
        case .iot, .publishing:
            // Unreachable: both are guarded above with dedicated launch
            // paths. Kept for switch exhaustiveness.
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

            let adminToken = ensureAdminToken(for: service)
            if let adminToken {
                try Self.writeAdminToken(adminToken, for: service)
            }

            let process = Process()
            process.executableURL = ClawJSRuntime.nodeBinaryURL
            process.arguments = extraArgs
            process.currentDirectoryURL = Self.workspaceURL
            process.environment = Self.environment(for: service, adminToken: adminToken)

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

    /// Single workspace shared by services for process cwd and runtime
    /// artifacts that are not the canonical ClawJS data store.
    static var workspaceURL: URL {
        applicationSupportRoot.appendingPathComponent("workspace", isDirectory: true)
    }

    static var applicationSupportRoot: URL {
        let env = ProcessInfo.processInfo.environment
        if env["CLAWIX_DUMMY_MODE"] == "1", let root = env["CLAWIX_CLAW_ROOT"], !root.isEmpty {
            return URL(fileURLWithPath: root, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clawix/clawjs", isDirectory: true)
    }

    static var mainDataDirectoryURL: URL {
        applicationSupportRoot
    }

    static var mainDatabaseURL: URL {
        mainDataDirectoryURL.appendingPathComponent("clawjs.sqlite", isDirectory: false)
    }

    static var mainFilesDirectoryURL: URL {
        mainDataDirectoryURL.appendingPathComponent("files", isDirectory: true)
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
        try fm.createDirectory(
            at: mainFilesDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    static func cliEnvironment() -> [String: String] {
        environment(for: .database, adminToken: nil)
    }

    private static func environment(for service: ClawJSService, adminToken: String?) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = applicationSupportRoot.appendingPathComponent("home").path
        env["CLAWJS_WORKSPACE"] = workspaceURL.path
        env["CLAW_DATA_DIR"] = mainDataDirectoryURL.path
        env["CLAWIX_CLAW_DATA_DIR"] = mainDataDirectoryURL.path
        env["CLAW_DB_PATH"] = mainDatabaseURL.path
        env["CLAW_FILES_DIR"] = mainFilesDirectoryURL.path
        env["CLAWJS_PORT"] = String(service.port)
        env["CLAWJS_SERVICE"] = service.rawValue
        env["CLAWJS_SECRETS_PROXY_PATH"] = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("bin/secrets-proxy", isDirectory: false)
            .path
        env["PORT"] = String(service.port)
        env["HOST"] = "127.0.0.1"
        env["CLAW_DATABASE_HOST"] = "127.0.0.1"
        env["CLAW_DATABASE_PORT"] = String(ClawJSService.database.port)
        env["CLAW_DATABASE_DATA_DIR"] = mainDataDirectoryURL.path
        env["CLAW_DATABASE_DB_PATH"] = mainDatabaseURL.path
        env["CLAW_DATABASE_FILES_DIR"] = mainFilesDirectoryURL.path
        env["CLAW_DRIVE_HOST"] = "127.0.0.1"
        env["CLAW_DRIVE_PORT"] = String(ClawJSService.drive.port)
        env["CLAW_DRIVE_DATA_DIR"] = dataDirectoryURL(for: .drive).path
        env["CLAW_SESSIONS_HOST"] = "127.0.0.1"
        env["CLAW_SESSIONS_PORT"] = String(ClawJSService.sessions.port)
        env["CLAW_SESSIONS_DATA_DIR"] = dataDirectoryURL(for: .sessions).path
        env["CLAW_SESSIONS_DB_PATH"] = dataDirectoryURL(for: .sessions)
            .appendingPathComponent("sessions.sqlite", isDirectory: false).path
        env["CLAW_SECRETS_HOST"] = "127.0.0.1"
        env["CLAW_SECRETS_PORT"] = String(ClawJSService.secrets.port)
        env["CLAW_SECRETS_DATA_DIR"] = dataDirectoryURL(for: .secrets).path
        env["CLAW_SECRETS_DB_PATH"] = dataDirectoryURL(for: .secrets)
            .appendingPathComponent("secrets.sqlite", isDirectory: false).path
        env["CLAW_SECRETS_BASE_URL"] = "http://127.0.0.1:\(ClawJSService.secrets.port)"
        env["CLAW_SECRETS_TENANT_ID"] = ClawJSSecretsClient.defaultTenantId
        // The Telegram surface reads its own variables (the CLI normally
        // sets these, but pin them here too so a hand-launched `npm start`
        // lines up with what the Swift client expects).
        if service == .telegram {
            env["CLAW_TELEGRAM_PORT"] = String(service.port)
            env["CLAW_TELEGRAM_WORKSPACE"] = workspaceURL.path
        }
        // Publishing reads its own CLAW_PUBLISHING_* env vars; its admin token lives
        // alongside the data dir in `.admin-token` so the Swift client can
        // read it via `adminTokenFromDataDir(for: .publishing)`. The dataDir
        // doubles as the SQLite location (publishing uses `core.sqlite`
        // inside it on first boot).
        if service == .publishing {
            let publishingData = dataDirectoryURL(for: .publishing).path
            env["CLAW_PUBLISHING_HOST"] = "127.0.0.1"
            env["CLAW_PUBLISHING_PORT"] = String(service.port)
            env["CLAW_PUBLISHING_DATA_DIR"] = publishingData
            env["CLAW_PUBLISHING_TOKEN_STORE"] = (publishingData as NSString)
                .appendingPathComponent(".admin-token")
        }
        if let adminToken, let envVar = adminTokenEnvVar[service] {
            env[envVar] = adminToken
            if service == .secrets {
                env["CLAW_SECRETS_TOKEN"] = adminToken
            }
        }
        return env
    }

    /// Per-session admin token for `service` if this manager spawned the
    /// daemon. `nil` for services without admin auth, or when the GUI is
    /// not the daemon owner (e.g., background bridge mode).
    func adminTokenIfSpawned(for service: ClawJSService) -> String? {
        sessionAdminTokens[service]
    }

    /// Returns the existing per-session token or generates a fresh one and
    /// stores it. `nil` for services that don't authenticate admin via token.
    private func ensureAdminToken(for service: ClawJSService) -> String? {
        guard Self.adminTokenEnvVar[service] != nil else { return nil }
        if let existing = sessionAdminTokens[service] { return existing }
        let token = SecureRandom.bytes(32).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        sessionAdminTokens[service] = token
        return token
    }

    /// Filesystem fallback for the admin token, used when the GUI is not
    /// the daemon owner (background bridge has the daemon alive). The
    /// daemon writes a 0600 file on its own first launch; we read it.
    static func adminTokenFromDataDir(for service: ClawJSService) throws -> String {
        let url = dataDirectoryURL(for: service).appendingPathComponent(".admin-token", isDirectory: false)
        let raw = try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count >= 32 else {
            throw NSError(domain: "ClawJSServiceManager", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Admin token at \(url.path) is too short."
        ])
        }
        return raw
    }

    /// Persists the per-session admin token for sibling processes such as
    /// the Tasks mini-app. The token stays under the private Clawix app
    /// support data dir and is overwritten every time this process owns a
    /// fresh sidecar launch.
    private static func writeAdminToken(_ token: String, for service: ClawJSService) throws {
        let url = dataDirectoryURL(for: service).appendingPathComponent(".admin-token", isDirectory: false)
        try Data(token.utf8).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func canAdoptExistingService(_ service: ClawJSService) -> Bool {
        guard adminTokenEnvVar[service] != nil else { return true }
        return (try? adminTokenFromDataDir(for: service)).map { !$0.isEmpty } ?? false
    }

    private nonisolated static func listenerPID(on port: UInt16) -> pid_t? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "/usr/sbin/lsof -nP -tiTCP:\(port) -sTCP:LISTEN 2>/dev/null | head -n 1"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let value = Int32(raw) else { return nil }
        return value
    }

    private nonisolated static func isClawixSidecar(pid: pid_t) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", "command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let command = String(data: data, encoding: .utf8) ?? ""
        return command.contains("/Clawix.app/Contents/Resources/clawjs/")
            || command.contains("/Application Support/Clawix/clawjs/")
    }

    private nonisolated static func parentPID(of pid: pid_t) -> pid_t? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", "ppid="]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let value = Int32(raw) else { return nil }
        return value
    }

    private nonisolated static func isRunning(pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }

    private static func dataDirectoryURL(for service: ClawJSService) -> URL {
        if service == .database {
            return mainDataDirectoryURL
        }
        return workspaceURL
            .appendingPathComponent(".claw", isDirectory: true)
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

    // MARK: - IoT launch path

    /// Spawns the clawjs-iot daemon. Distinct from `spawnAndSupervise`
    /// because IoT lives outside @clawjs/cli: its argv, cwd, and the
    /// node binary all differ from the bundled-runtime services.
    private func spawnIot(projectDir: URL) async {
        let serverJs = projectDir.appendingPathComponent("dist/server.js", isDirectory: false)
        update(.iot) { $0.state = .starting; $0.lastError = nil }

        do {
            try Self.prepareDirectories(for: .iot)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["node", serverJs.path]
            process.currentDirectoryURL = projectDir
            process.environment = Self.iotEnvironment()

            let logURL = Self.logFileURL(for: .iot)
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            process.standardOutput = handle
            process.standardError = handle
            logHandles[.iot] = handle

            process.terminationHandler = { [weak self] proc in
                Task { @MainActor [weak self] in
                    self?.handleTermination(of: .iot, process: proc)
                }
            }

            try process.run()
            processes[.iot] = process

            healthTasks[.iot]?.cancel()
            healthTasks[.iot] = Task { [weak self] in
                await self?.pollHealth(for: .iot, pid: process.processIdentifier)
            }
        } catch {
            update(.iot) {
                $0.state = .crashed(reason: "spawn failed: \(error.localizedDescription)")
                $0.lastError = error.localizedDescription
            }
            scheduleRestart(.iot)
        }
    }

    /// Resolves the on-disk clawjs/iot project directory. Phase 1 reads
    /// a dev pointer dev.sh writes; production builds substitute a
    /// bundled copy under Contents/Resources/clawjs-iot/. Returns nil
    /// when neither location is present or the dist/server.js is
    /// missing, which keeps the service `.blocked` rather than crashing.
    private func iotProjectDirectory() -> URL? {
        let pointerURL = Self.applicationSupportRoot
            .appendingPathComponent("dev-pointers", isDirectory: true)
            .appendingPathComponent("iot.dir", isDirectory: false)
        if let raw = try? String(contentsOf: pointerURL, encoding: .utf8) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let candidate = URL(fileURLWithPath: trimmed, isDirectory: true)
                if FileManager.default.fileExists(atPath: candidate
                    .appendingPathComponent("dist/server.js").path) {
                    return candidate
                }
            }
        }
        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/clawjs-iot", isDirectory: true)
        if FileManager.default.fileExists(atPath: bundled
            .appendingPathComponent("dist/server.js").path) {
            return bundled
        }
        return nil
    }

    /// Environment for the spawned IoT daemon. Pins host+port+data dir
    /// so the supervisor's health probe and downstream clients agree on
    /// the same loopback endpoint. Mirrors the per-service env wiring
    /// `environment(for:adminToken:)` does for the @clawjs/cli surface
    /// without inheriting workspace-flavoured variables that IoT does
    /// not consume.
    private static func iotEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["IOT_HOST"] = "127.0.0.1"
        env["IOT_PORT"] = String(ClawJSService.iot.port)
        let dataDir = dataDirectoryURL(for: .iot)
        env["IOT_DATA_DIR"] = dataDir.path
        env["IOT_DB_PATH"] = dataDir.appendingPathComponent("iot.sqlite", isDirectory: false).path
        return env
    }
}
