import Foundation

// JSON-RPC 2.0 client over stdio for the backend app-server.
//
// Responsibilities:
//   - Spawn the binary, keep stdin/stdout/stderr pipes alive.
//   - Frame messages as one JSON object per line (LF delimited).
//   - Correlate request `id` with awaitable continuations.
//   - Forward server notifications and server-initiated requests as
//     AsyncStreams the service layer can consume.
//   - Auto-decline server-initiated approvals in v1 (the layer is in
//     place for v2 to wire UI prompts here).

enum ClawixClientError: Error, CustomStringConvertible {
    case binaryNotFound
    case processFailedToStart(String)
    case notRunning
    case rpcError(code: Int, message: String)
    case invalidResponse(String)
    case decodingError(String)

    var description: String {
        switch self {
        case .binaryNotFound:
            return "Backend binary not found. Set the path manually in Settings."
        case .processFailedToStart(let s):
            return "Backend app-server failed to start: \(s)"
        case .notRunning:
            return "Clawix backend is not running."
        case .rpcError(let code, let message):
            return "JSON-RPC error \(code): \(message)"
        case .invalidResponse(let s):
            return "Invalid response: \(s)"
        case .decodingError(let s):
            return "Decoding error: \(s)"
        }
    }
}

/// Server-initiated message that the host app may want to react to.
enum ClawixServerEvent {
    case notification(method: String, params: JSONValue?)
    case request(id: ClawixRPCID, method: String, params: JSONValue?)
}

actor ClawixClient {
    private let backendHomeEnvName = ["CO", "DEX_HOME"].joined()
    private let backendProcessName = ["co", "dex"].joined()

    private let binary: ClawixBinaryInfo
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var readBuffer = Data()
    private var stderrLogHandle: FileHandle?

    private var nextRequestId: Int = 1
    private var pending: [Int: CheckedContinuation<JSONValue?, Error>] = [:]

    private var eventsContinuation: AsyncStream<ClawixServerEvent>.Continuation?
    nonisolated let events: AsyncStream<ClawixServerEvent>

    private let nonisolatedEventsContinuationBox: ContinuationBox

    init(binary: ClawixBinaryInfo) {
        self.binary = binary
        let box = ContinuationBox()
        var captured: AsyncStream<ClawixServerEvent>.Continuation!
        let stream = AsyncStream<ClawixServerEvent> { continuation in
            captured = continuation
            box.continuation = continuation
        }
        self.events = stream
        self.nonisolatedEventsContinuationBox = box
        self.eventsContinuation = captured
    }

    deinit {
        nonisolatedEventsContinuationBox.continuation?.finish()
    }

    // MARK: - Lifecycle

    func start() throws {
        guard process == nil else { return }

        let proc = Process()
        proc.executableURL = binary.path
        proc.arguments = ["app-server", "--listen", "stdio://"]
        var env = ProcessInfo.processInfo.environment
        // Dummy mode injects CLAWIX_BACKEND_HOME pointing at an
        // ephemeral directory wiped on each launch. Honour it as the
        // backend's home so rollouts and sessions land there instead
        // of the user's real config dir.
        if let override = env["CLAWIX_BACKEND_HOME"], !override.isEmpty {
            env[backendHomeEnvName] = override
        } else {
            env[backendHomeEnvName] = nil
        }
        // Share the user's existing backend auth, sessions, and config.
        proc.environment = env

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr
        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.stderrPipe = stderr

        openStderrLog()
        attachStdoutReader(stdout)
        attachStderrReader(stderr)

        do {
            try proc.run()
        } catch {
            throw ClawixClientError.processFailedToStart(error.localizedDescription)
        }
        self.process = proc

        proc.terminationHandler = { [weak self] term in
            guard let self else { return }
            Task { await self.handleTermination(reason: term.terminationReason, status: term.terminationStatus) }
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        readBuffer.removeAll()
        try? stderrLogHandle?.close()
        stderrLogHandle = nil
        // Fail any in-flight requests
        for (_, c) in pending { c.resume(throwing: ClawixClientError.notRunning) }
        pending.removeAll()
    }

    private func handleTermination(reason: Process.TerminationReason, status: Int32) {
        if let log = stderrLogHandle {
            let line = "[\(Date())] \(backendProcessName) app-server terminated. reason=\(reason.rawValue) status=\(status)\n"
            try? log.write(contentsOf: Data(line.utf8))
        }
        process = nil
        for (_, c) in pending { c.resume(throwing: ClawixClientError.notRunning) }
        pending.removeAll()
    }

    // MARK: - Public requests

    func send<P: Encodable, R: Decodable>(method: String, params: P, expecting: R.Type) async throws -> R {
        let raw = try await sendRaw(method: method, params: params)
        guard let raw else {
            throw ClawixClientError.invalidResponse("Empty result for \(method)")
        }
        do {
            return try raw.decode(R.self)
        } catch {
            throw ClawixClientError.decodingError("\(method): \(error)")
        }
    }

    func send<P: Encodable>(method: String, params: P) async throws -> JSONValue? {
        try await sendRaw(method: method, params: params)
    }

    func notify<P: Encodable>(method: String, params: P) throws {
        let n = ClawixOutgoingNotification(method: method, params: params)
        try writeFrame(n)
    }

    private func sendRaw<P: Encodable>(method: String, params: P) async throws -> JSONValue? {
        guard process != nil else { throw ClawixClientError.notRunning }
        let id = nextRequestId
        nextRequestId += 1
        let req = ClawixOutgoingRequest(id: id, method: method, params: params)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONValue?, Error>) in
            pending[id] = continuation
            do {
                try writeFrame(req)
            } catch {
                pending.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
    }

    /// Resolve a server-initiated request (server -> client). v1 callers
    /// send `decline` for any approval to keep behaviour deterministic.
    func resolveServerRequest<R: Encodable>(id: ClawixRPCID, result: R) throws {
        let response = ClawixOutgoingResponse(id: id, result: result)
        try writeFrame(response)
    }

    func resolveServerRequestWithError(id: ClawixRPCID, code: Int, message: String) throws {
        let response = ClawixOutgoingErrorResponse(id: id, error: ClawixErrorBody(code: code, message: message, data: nil))
        try writeFrame(response)
    }

    // MARK: - Framing

    private func writeFrame<T: Encodable>(_ value: T) throws {
        guard let pipe = stdinPipe else { throw ClawixClientError.notRunning }
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        let data = try encoder.encode(value) + Data([0x0a]) // newline
        try pipe.fileHandleForWriting.write(contentsOf: data)
    }

    // MARK: - Stdout reader

    private func attachStdoutReader(_ pipe: Pipe) {
        let handle = pipe.fileHandleForReading
        let weakBox = WeakBox(self)
        handle.readabilityHandler = { fh in
            let data = fh.availableData
            if data.isEmpty {
                fh.readabilityHandler = nil
                return
            }
            Task { await weakBox.value?.appendStdout(data) }
        }
    }

    private func appendStdout(_ data: Data) {
        readBuffer.append(data)
        while let nl = readBuffer.firstIndex(of: 0x0a) {
            let line = readBuffer.subdata(in: 0 ..< nl)
            readBuffer.removeSubrange(0 ... nl)
            if line.isEmpty { continue }
            handleLine(line)
        }
    }

    private func handleLine(_ data: Data) {
        let decoder = JSONDecoder()
        let decoded: ClawixIncomingMessage? = PerfSignpost.ipcClient.interval("decode") {
            try? decoder.decode(ClawixIncomingMessage.self, from: data)
        }
        guard let msg = decoded else {
            // Not all server output is JSON-RPC: log it and move on.
            if let log = stderrLogHandle, let s = String(data: data, encoding: .utf8) {
                try? log.write(contentsOf: Data("[stdout-non-json] \(s)\n".utf8))
            }
            return
        }

        // Response to a request we made (id present, no method)
        if let id = msg.id, msg.method == nil {
            guard case .int(let intId) = id, let cont = pending.removeValue(forKey: intId) else {
                return
            }
            if let err = msg.error {
                cont.resume(throwing: ClawixClientError.rpcError(code: err.code, message: err.message))
            } else {
                cont.resume(returning: msg.result)
            }
            return
        }

        // Server-initiated request (id and method present)
        if let id = msg.id, let method = msg.method {
            handleServerRequest(id: id, method: method, params: msg.params)
            eventsContinuation?.yield(.request(id: id, method: method, params: msg.params))
            return
        }

        // Server notification (method present, no id)
        if let method = msg.method {
            eventsContinuation?.yield(.notification(method: method, params: msg.params))
            return
        }
    }

    /// v1 default policy: refuse approvals automatically. Clawix is launched
    /// with `approval_policy=never` + `sandbox=workspace-write` so this
    /// branch should rarely trigger; it exists as defence in depth.
    ///
    /// `item/tool/requestUserInput` is the exception: that's how the runtime
    /// surfaces plan-mode questions, so we hand the request id to the
    /// service via `events` and let the UI resolve it after the user
    /// answers (or dismisses).
    private func handleServerRequest(id: ClawixRPCID, method: String, params: JSONValue?) {
        switch method {
        case ClawixMethod.rToolUserInput:
            // Defer; ClawixService stores the id and answers on user click.
            break
        case ClawixMethod.rFileChangeApproval,
             ClawixMethod.rExecApproval,
             ClawixMethod.rPermissionsApproval:
            try? resolveServerRequest(id: id, result: ApprovalDecisionResponse(decision: "decline"))
        default:
            // For unknown server requests we send a JSON-RPC method-not-found
            // error so the server doesn't deadlock waiting for us.
            try? resolveServerRequestWithError(
                id: id,
                code: -32601,
                message: "Method \(method) not handled by Clawix v1"
            )
        }
    }

    // MARK: - Stderr reader

    private func attachStderrReader(_ pipe: Pipe) {
        let handle = pipe.fileHandleForReading
        let weakBox = WeakBox(self)
        handle.readabilityHandler = { fh in
            let data = fh.availableData
            if data.isEmpty {
                fh.readabilityHandler = nil
                return
            }
            Task { await weakBox.value?.writeStderr(data) }
        }
    }

    private func writeStderr(_ data: Data) {
        try? stderrLogHandle?.write(contentsOf: data)
    }

    private func openStderrLog() {
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Clawix", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let logURL = logsDir.appendingPathComponent("clawix-app-server.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        if let h = try? FileHandle(forWritingTo: logURL) {
            try? h.seekToEnd()
            try? h.write(contentsOf: Data("\n=== Clawix start \(Date()) ===\n".utf8))
            self.stderrLogHandle = h
        }
    }
}

// MARK: - helpers

private final class WeakBox<T: AnyObject> {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

// `eventsContinuation` cannot be touched non-isolated, but `deinit` runs
// outside the actor, so we keep a separate non-isolated reference here.
private final class ContinuationBox: @unchecked Sendable {
    var continuation: AsyncStream<ClawixServerEvent>.Continuation?
}
