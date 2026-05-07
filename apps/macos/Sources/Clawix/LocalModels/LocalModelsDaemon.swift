import Foundation

/// Foreground (in-process) lifecycle for the local LLM runtime. Owns the
/// `Process` instance that runs the downloaded binary in `serve` mode,
/// pipes stdout/stderr to a log file under `~/Library/Logs/Clawix/`, and
/// exposes a ready/stopped state machine the UI can bind to.
///
/// The daemon is bound to a non-default loopback port (11435) so it
/// cannot collide with any system-wide Ollama install on the standard
/// 11434. `HOME` is reset to our Application Support directory so the
/// daemon never reads or writes the user's `~/.ollama/` config.
///
/// Auto-start across reboots is handled by `LocalModelsLaunchAgent` via
/// `SMAppService`; this class is for the "while Clawix is open" path.
@MainActor
final class LocalModelsDaemon: ObservableObject {

    static let shared = LocalModelsDaemon()

    /// Loopback host. Constant; the daemon never listens off-host.
    static let host = "127.0.0.1"

    /// Hard-coded port. Picked one above the upstream default (11434) so
    /// a system-wide install keeps working independently of Clawix.
    static let port: UInt16 = 11_435

    enum State: Equatable {
        case stopped
        case starting
        case running
        case missingRuntime
        case crashed(message: String)
    }

    @Published private(set) var state: State = .stopped

    private var process: Process?
    private var logHandle: FileHandle?

    private init() {}

    // MARK: - Paths

    static var logFileURL: URL {
        let logs = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Logs/Clawix", isDirectory: true)
        return logs.appendingPathComponent("local-models.log", isDirectory: false)
    }

    /// `OLLAMA_MODELS` target. Lives next to the runtime so an uninstall
    /// only of the runtime doesn't wipe the user's downloaded weights.
    static var modelsDirectory: URL {
        LocalModelsRuntimeInstaller.applicationSupportRoot
            .appendingPathComponent("models", isDirectory: true)
    }

    /// Fake `HOME` for the daemon. Stops it from reading `~/.ollama/` of
    /// the user (auth keys, manifests of any system Ollama install).
    static var fakeHomeDirectory: URL {
        LocalModelsRuntimeInstaller.applicationSupportRoot
            .appendingPathComponent("home", isDirectory: true)
    }

    // MARK: - Public API

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    /// Starts the daemon. Idempotent for `running`/`starting`. Returns
    /// once the runtime is responsive on the loopback port (or the start
    /// times out, in which case `state` is `.crashed`).
    func start(numCtx: Int = 4096, keepAlive: String = "5m") async {
        switch state {
        case .running, .starting: return
        default: break
        }

        guard FileManager.default.isExecutableFile(
            atPath: LocalModelsRuntimeInstaller.binaryURL.path
        ) else {
            state = .missingRuntime
            return
        }

        state = .starting

        do {
            try Self.prepareDirectories()
            let process = try spawn(numCtx: numCtx, keepAlive: keepAlive)
            self.process = process

            if await waitUntilAlive(deadlineSeconds: 10) {
                state = .running
            } else {
                process.terminate()
                state = .crashed(message:
                    "Runtime did not respond on \(Self.host):\(Self.port) within 10 seconds. " +
                    "See ~/Library/Logs/Clawix/local-models.log for details.")
            }
        } catch {
            state = .crashed(message: "Could not start runtime: \(error.localizedDescription)")
        }
    }

    /// Stops the daemon by sending SIGTERM. The termination handler
    /// settled in `spawn(...)` flips state once the process is gone.
    func stop() {
        process?.terminate()
    }

    func toggle(_ on: Bool) async {
        if on { await start() } else { stop() }
    }

    // MARK: - Process plumbing

    private static func prepareDirectories() throws {
        let fm = FileManager.default
        try fm.createDirectory(
            at: logFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fm.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: fakeHomeDirectory, withIntermediateDirectories: true)

        if !fm.fileExists(atPath: logFileURL.path) {
            fm.createFile(atPath: logFileURL.path, contents: nil)
        }
    }

    private func spawn(numCtx: Int, keepAlive: String) throws -> Process {
        let process = Process()
        process.executableURL = LocalModelsRuntimeInstaller.binaryURL
        process.arguments = ["serve"]
        process.environment = Self.environment(numCtx: numCtx, keepAlive: keepAlive)

        // Append-mode write handle so we don't truncate previous runs'
        // logs when Clawix restarts.
        let handle = try FileHandle(forWritingTo: Self.logFileURL)
        try handle.seekToEnd()
        process.standardOutput = handle
        process.standardError = handle
        self.logHandle = handle

        process.terminationHandler = { [weak self] proc in
            Task { @MainActor [weak self] in
                guard let self, self.process === proc else { return }
                let status = proc.terminationStatus
                self.state = (status == 0 || proc.terminationReason == .uncaughtSignal)
                    ? .stopped
                    : .crashed(message: "Runtime exited with status \(status).")
                self.process = nil
                try? self.logHandle?.close()
                self.logHandle = nil
            }
        }

        try process.run()
        return process
    }

    /// Environment variables the daemon needs to be fully isolated from
    /// any user-installed Ollama. Exposed for the LaunchAgent so the
    /// daemon comes up the same way whether Clawix launched it directly
    /// or launchd did.
    static func environment(
        numCtx: Int = 4096,
        keepAlive: String = "5m"
    ) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["OLLAMA_HOST"] = "\(host):\(port)"
        env["OLLAMA_MODELS"] = modelsDirectory.path
        env["OLLAMA_KEEP_ALIVE"] = keepAlive
        env["OLLAMA_CONTEXT_LENGTH"] = String(numCtx)
        env["HOME"] = fakeHomeDirectory.path
        return env
    }

    // MARK: - Readiness

    private func waitUntilAlive(deadlineSeconds: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(deadlineSeconds)
        while Date() < deadline {
            if await ping() { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return false
    }

    private func ping() async -> Bool {
        let url = URL(string: "http://\(Self.host):\(Self.port)/api/version")!
        var req = URLRequest(url: url)
        req.timeoutInterval = 1
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
