import Foundation
import Darwin
import SecretsProxyCore

// MARK: - Socket path resolution

let socketPath: String = {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home
        .appendingPathComponent("Library/Application Support/Clawix/secrets/proxy.sock")
        .path
}()

// MARK: - Output helpers

let stderrFD: Int32 = 2

func eprint(_ message: String) {
    let data = Data((message + "\n").utf8)
    data.withUnsafeBytes { buf in
        _ = Darwin.write(stderrFD, buf.baseAddress, data.count)
    }
}

func writeLineToStdout(_ text: String) {
    let data = Data((text + "\n").utf8)
    data.withUnsafeBytes { buf in
        _ = Darwin.write(1, buf.baseAddress, data.count)
    }
}

// MARK: - Socket client

final class ProxyClient {
    let path: String
    private var fd: Int32 = -1
    private var inbox = Data()

    init(path: String) {
        self.path = path
    }

    func connect() throws {
        let s = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        if s < 0 { throw ClientError.connectFailed("socket() errno=\(errno)") }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathCapacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < pathCapacity else {
            Darwin.close(s)
            throw ClientError.connectFailed("socket path too long: \(path)")
        }
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { dst in
                _ = strlcpy(dst, path, pathCapacity)
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(s, $0, len)
            }
        }
        if result < 0 {
            Darwin.close(s)
            throw ClientError.connectFailed(
                "could not connect to \(path) (errno=\(errno)). Open Clawix to start the proxy bridge."
            )
        }
        self.fd = s
    }

    func send(_ request: ProxyRequest) throws -> ProxyResponse {
        if fd < 0 { try connect() }
        let payload = try ProxyWireCodec.encode(request)
        var remaining = payload
        while !remaining.isEmpty {
            let written = remaining.withUnsafeBytes { buf -> Int in
                Darwin.write(fd, buf.baseAddress, remaining.count)
            }
            if written <= 0 { throw ClientError.ioFailed("write errno=\(errno)") }
            remaining.removeFirst(written)
        }
        return try readResponse()
    }

    func readResponse() throws -> ProxyResponse {
        let chunkSize = 8192
        while true {
            if let nl = inbox.firstIndex(of: 0x0A) {
                let line = inbox[..<nl]
                inbox.removeSubrange(...nl)
                return try ProxyWireCodec.decodeResponse(from: Data(line))
            }
            var chunk = [UInt8](repeating: 0, count: chunkSize)
            let n = chunk.withUnsafeMutableBufferPointer { ptr -> Int in
                Darwin.read(fd, ptr.baseAddress, chunkSize)
            }
            if n <= 0 { throw ClientError.ioFailed("connection closed before response (errno=\(errno))") }
            inbox.append(chunk, count: n)
        }
    }

    func close() {
        if fd >= 0 { Darwin.close(fd) }
        fd = -1
    }

    enum ClientError: Swift.Error, CustomStringConvertible {
        case connectFailed(String)
        case ioFailed(String)

        var description: String {
            switch self {
            case .connectFailed(let s): return "connect failed: \(s)"
            case .ioFailed(let s): return "io failed: \(s)"
            }
        }
    }
}

// MARK: - Argument parsing

struct ParsedArgs {
    var op: String
    var values: [String: [String]] = [:]
    var passthroughAfterDoubleDash: [String] = []
    var positional: [String] = []

    func single(_ name: String) -> String? { values[name]?.first }
    func multi(_ name: String) -> [String] { values[name] ?? [] }
    func bool(_ name: String) -> Bool { values[name] != nil }
}

func parseArgs(_ argv: [String]) -> ParsedArgs? {
    guard argv.count >= 2 else { return nil }
    var head = 1
    let knownOps: Set<String> = [
        "list-secrets", "describe-secret", "request", "exec", "doctor",
        "request-activation", "list-grants", "revoke-grant",
        "help", "--help", "-h"
    ]
    let op: String
    if knownOps.contains(argv[1]) {
        op = argv[1]
        head = 2
    } else {
        return nil
    }
    var parsed = ParsedArgs(op: op == "--help" || op == "-h" ? "help" : op)
    var afterDoubleDash = false
    var i = head
    while i < argv.count {
        let a = argv[i]
        if afterDoubleDash {
            parsed.passthroughAfterDoubleDash.append(a)
            i += 1
            continue
        }
        if a == "--" { afterDoubleDash = true; i += 1; continue }
        if a.hasPrefix("--") {
            let key = String(a.dropFirst(2))
            // Bool flag (next arg starts with -- or is missing).
            let next = i + 1 < argv.count ? argv[i + 1] : nil
            if next == nil || next!.hasPrefix("--") || next! == "--" {
                parsed.values[key, default: []].append("")
                i += 1
            } else {
                parsed.values[key, default: []].append(next!)
                i += 2
            }
        } else {
            parsed.positional.append(a)
            i += 1
        }
    }
    return parsed
}

// MARK: - Commands

func runListSecrets(_ args: ParsedArgs) -> Int32 {
    let client = ProxyClient(path: socketPath)
    var req = ProxyRequest(op: .listSecrets)
    req.search = args.single("search")
    req.vaultName = args.single("vault")
    req.kind = args.single("kind")
    do {
        let response = try client.send(req)
        client.close()
        guard response.ok else {
            eprint("error: \(response.error ?? "unknown")")
            return 2
        }
        let secrets = response.secrets ?? []
        if args.bool("json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
            let data = (try? encoder.encode(secrets)) ?? Data("[]".utf8)
            writeLineToStdout(String(data: data, encoding: .utf8) ?? "[]")
        } else {
            if secrets.isEmpty {
                writeLineToStdout("(no secrets match)")
            }
            for s in secrets {
                let allowed = s.allowedHosts.isEmpty ? "any" : s.allowedHosts.joined(separator: ", ")
                writeLineToStdout("- \(s.internalName)  [\(s.kind)]  \(s.title)  hosts=\(allowed)")
            }
        }
        return 0
    } catch {
        eprint("error: \(error)")
        return 3
    }
}

func runDescribeSecret(_ args: ParsedArgs) -> Int32 {
    guard let name = args.single("name") ?? args.positional.first else {
        eprint("usage: clawix-secrets-proxy describe-secret --name <internal_name>")
        return 1
    }
    var req = ProxyRequest(op: .describeSecret)
    req.name = name
    let client = ProxyClient(path: socketPath)
    do {
        let response = try client.send(req)
        client.close()
        guard response.ok, let secret = response.secret else {
            eprint("error: \(response.error ?? "unknown")")
            return 2
        }
        if args.bool("json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
            let data = (try? encoder.encode(secret)) ?? Data("{}".utf8)
            writeLineToStdout(String(data: data, encoding: .utf8) ?? "{}")
        } else {
            writeLineToStdout("internal_name: \(secret.internalName)")
            writeLineToStdout("title:         \(secret.title)")
            writeLineToStdout("kind:          \(secret.kind)")
            writeLineToStdout("vault:         \(secret.vaultName)")
            writeLineToStdout("read_only:     \(secret.readOnly)")
            writeLineToStdout("compromised:   \(secret.isCompromised)")
            writeLineToStdout("allowed hosts:   \(secret.allowedHosts.joined(separator: ", "))")
            writeLineToStdout("allowed headers: \(secret.allowedHeaders.joined(separator: ", "))")
            writeLineToStdout("placement: url=\(secret.allowInUrl) body=\(secret.allowInBody) env=\(secret.allowInEnv)")
            writeLineToStdout("fields:")
            for f in secret.fields {
                let marker = f.isSecret ? "*" : " "
                writeLineToStdout("  \(marker) \(f.name)  [\(f.fieldKind), placement=\(f.placement)]")
            }
        }
        return 0
    } catch {
        eprint("error: \(error)")
        return 3
    }
}

func runExec(_ args: ParsedArgs) -> Int32 {
    let envArgs = args.multi("env")
    let cmdAndArgs = args.passthroughAfterDoubleDash
    guard !cmdAndArgs.isEmpty else {
        eprint("usage: clawix-secrets-proxy exec [--env \"K={{secret}}\"]... [--host HOST] [--agent-token TOKEN] -- CMD [ARGS...]")
        return 1
    }
    let host = args.single("host") ?? ""
    let sessionId = args.single("session") ?? UUID().uuidString
    let agentToken = args.single("agent-token")

    // Parse env: each --env "KEY={{placeholder}}" or "KEY=literal".
    // Collect placeholders for resolution.
    struct EnvPair { let key: String; let template: String }
    var pairs: [EnvPair] = []
    for raw in envArgs {
        guard let eq = raw.firstIndex(of: "=") else {
            eprint("error: malformed --env '\(raw)' (expected KEY=value)")
            return 1
        }
        pairs.append(EnvPair(
            key: String(raw[..<eq]),
            template: String(raw[raw.index(after: eq)...])
        ))
    }
    let templates = pairs.map { $0.template }
    let tokens = PlaceholderResolver.tokens(in: templates)

    let context = ResolveContext(
        host: host.isEmpty ? nil : host,
        method: nil,
        headerNames: [],
        inUrl: false,
        inBody: false,
        inEnv: true,
        insecureTransport: false,
        localNetwork: false
    )

    let client = ProxyClient(path: socketPath)
    var resolvedValues: [String: String] = [:]
    var redactionEntries: [RedactionEntry] = []
    var resolvedSecretNames: [String] = []
    if !tokens.isEmpty {
        var resolveReq = ProxyRequest(op: .resolvePlaceholders)
        resolveReq.placeholders = tokens
        resolveReq.context = context
        resolveReq.sessionId = sessionId
        resolveReq.agentToken = agentToken
        do {
            let resp = try client.send(resolveReq)
            guard resp.ok, let values = resp.values else {
                eprint("error: \(resp.error ?? "unknown")")
                client.close()
                return 4
            }
            resolvedValues = values
            let labels = resp.redactionLabels ?? [:]
            for token in tokens {
                guard let v = values[token.raw] else { continue }
                let label = labels[token.raw] ?? Redactor.label(forSecretInternalName: token.secretInternalName)
                redactionEntries.append(RedactionEntry(value: v, label: label))
                if !resolvedSecretNames.contains(token.secretInternalName) {
                    resolvedSecretNames.append(token.secretInternalName)
                }
            }
        } catch {
            eprint("error: \(error)")
            return 3
        }
    }

    // Build the env block for the subprocess. Inherit current environment so
    // PATH / HOME / etc still work, then override with the resolved keys.
    var env = ProcessInfo.processInfo.environment
    for pair in pairs {
        env[pair.key] = PlaceholderResolver.substitute(pair.template, with: resolvedValues)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = cmdAndArgs
    process.environment = env

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    let started = Date()
    let exitStatus: Int32
    do {
        try process.run()
    } catch {
        eprint("error: could not exec \(cmdAndArgs.first ?? "?"): \(error)")
        client.close()
        return 5
    }
    process.waitUntilExit()
    exitStatus = process.terminationStatus
    let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)

    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
    let outRedacted = Redactor.redact(data: outData, with: redactionEntries)
    let errRedacted = Redactor.redact(data: errData, with: redactionEntries)
    FileHandle.standardOutput.write(outRedacted)
    FileHandle.standardError.write(errRedacted)

    var auditCall = ProxyAuditCallSummary(
        kind: "proxy_exec",
        success: exitStatus == 0,
        host: host.isEmpty ? nil : host,
        method: nil,
        redactedRequest: "exec \(Redactor.redact(cmdAndArgs.joined(separator: " "), with: redactionEntries))",
        responseSize: outData.count + errData.count,
        latencyMs: elapsedMs,
        errorCode: exitStatus == 0 ? nil : "exit_\(exitStatus)",
        sessionId: sessionId,
        secretInternalNames: resolvedSecretNames
    )
    var auditReq = ProxyRequest(op: .audit)
    auditReq.auditCall = auditCall
    auditReq.sessionId = sessionId
    _ = try? client.send(auditReq)
    client.close()
    return exitStatus
}

func runRequestActivation(_ args: ParsedArgs) -> Int32 {
    guard let agent = args.single("agent"),
          let secret = args.single("secret"),
          let capability = args.single("capability"),
          let reason = args.single("reason")
    else {
        eprint("usage: clawix-secrets-proxy request-activation --agent <id> --secret <internal_name> --capability <cap> --reason \"<text>\" [--duration-minutes N] [--scope key=value]...")
        return 1
    }
    let duration = Int(args.single("duration-minutes") ?? "10") ?? 10
    let scopeArgs = args.multi("scope")
    var scope: [String: String] = [:]
    for raw in scopeArgs {
        guard let eq = raw.firstIndex(of: "=") else {
            eprint("error: malformed --scope '\(raw)' (expected key=value)")
            return 1
        }
        let key = String(raw[..<eq])
        let value = String(raw[raw.index(after: eq)...])
        scope[key] = value
    }
    let activation = ActivationRequest(
        agent: agent,
        secretInternalName: secret,
        capability: capability,
        reason: reason,
        durationMinutes: duration,
        scope: scope
    )
    var req = ProxyRequest(op: .requestActivation)
    req.activation = activation
    req.sessionId = args.single("session") ?? UUID().uuidString
    let client = ProxyClient(path: socketPath)
    do {
        eprint("Activation request sent. Approve in the Clawix app to receive the token.")
        let response = try client.send(req)
        client.close()
        guard response.ok, let info = response.issuedToken else {
            eprint("error: \(response.error ?? "unknown")")
            return 4
        }
        if args.bool("json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
            let data = (try? encoder.encode(info)) ?? Data("{}".utf8)
            writeLineToStdout(String(data: data, encoding: .utf8) ?? "{}")
        } else {
            writeLineToStdout("token:        \(info.token)")
            writeLineToStdout("grant_id:     \(info.grantId)")
            writeLineToStdout("expires_at:   \(info.expiresAt)")
            writeLineToStdout("agent:        \(info.agent)")
            writeLineToStdout("capability:   \(info.capability)")
            writeLineToStdout("secret:       \(info.secretInternalName)")
            writeLineToStdout("duration_min: \(info.durationMinutes)")
            if !info.scope.isEmpty {
                writeLineToStdout("scope:")
                for (k, v) in info.scope.sorted(by: { $0.key < $1.key }) {
                    writeLineToStdout("  \(k) = \(v)")
                }
            }
        }
        return 0
    } catch {
        eprint("error: \(error)")
        return 3
    }
}

func runListGrants(_ args: ParsedArgs) -> Int32 {
    let req = ProxyRequest(op: .listGrants)
    let client = ProxyClient(path: socketPath)
    do {
        let response = try client.send(req)
        client.close()
        guard response.ok else {
            eprint("error: \(response.error ?? "unknown")")
            return 2
        }
        let listed = response.grants ?? []
        if args.bool("json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
            let data = (try? encoder.encode(listed)) ?? Data("[]".utf8)
            writeLineToStdout(String(data: data, encoding: .utf8) ?? "[]")
        } else {
            if listed.isEmpty {
                writeLineToStdout("(no grants)")
            }
            for g in listed {
                let revoked = g.revokedAt != nil
                let now = Int64(Date().timeIntervalSince1970 * 1000)
                let active = !revoked && g.expiresAt > now
                let badge = active ? "ACTIVE" : (revoked ? "REVOKED" : "EXPIRED")
                writeLineToStdout("[\(badge)] \(g.grantId)  agent=\(g.agent)  cap=\(g.capability)  secret=\(g.secretInternalName)  used=\(g.usedCount)")
            }
        }
        return 0
    } catch {
        eprint("error: \(error)")
        return 3
    }
}

func runRevokeGrant(_ args: ParsedArgs) -> Int32 {
    guard let id = args.single("grant-id") ?? args.positional.first else {
        eprint("usage: clawix-secrets-proxy revoke-grant --grant-id <UUID>")
        return 1
    }
    var req = ProxyRequest(op: .revokeGrant)
    req.grantId = id
    let client = ProxyClient(path: socketPath)
    do {
        let response = try client.send(req)
        client.close()
        guard response.ok else {
            eprint("error: \(response.error ?? "unknown")")
            return 2
        }
        writeLineToStdout("revoked grant \(id)")
        return 0
    } catch {
        eprint("error: \(error)")
        return 3
    }
}

func runDoctor(_ args: ParsedArgs) -> Int32 {
    var req = ProxyRequest(op: .doctor)
    req.sessionId = args.single("session")
    let client = ProxyClient(path: socketPath)
    do {
        let response = try client.send(req)
        client.close()
        guard response.ok, let report = response.doctor else {
            eprint("error: \(response.error ?? "unknown")")
            return 2
        }
        if args.bool("json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
            let data = (try? encoder.encode(report)) ?? Data("{}".utf8)
            writeLineToStdout(String(data: data, encoding: .utf8) ?? "{}")
        } else {
            writeLineToStdout("vault_exists:        \(report.vaultExists)")
            writeLineToStdout("vault_locked:        \(report.vaultLocked)")
            writeLineToStdout("symlink_installed:   \(report.symlinkInstalled)")
            if let n = report.totalSecrets { writeLineToStdout("total_secrets:       \(n)") }
            if let n = report.totalAuditEvents { writeLineToStdout("total_audit_events:  \(n)") }
            if let intact = report.auditChainIntact {
                writeLineToStdout("audit_chain_intact:  \(intact)")
            }
            if let h = report.helperPath { writeLineToStdout("helper_path:         \(h)") }
            if let d = report.deviceId { writeLineToStdout("device_id:           \(d)") }
        }
        return 0
    } catch {
        eprint("error: \(error)")
        return 3
    }
}

func runRequest(_ args: ParsedArgs) -> Int32 {
    guard let urlString = args.single("url"), let url = URL(string: urlString) else {
        eprint("usage: clawix-secrets-proxy request --url <URL> [--method GET|POST|...] [--header \"K: V\"]... [--body STR | --body-file PATH] [--timeout SEC]")
        return 1
    }
    let method = (args.single("method") ?? "GET").uppercased()
    let headerArgs = args.multi("header")
    let bodyArg = args.single("body")
    let bodyFileArg = args.single("body-file")
    let timeoutSec = Double(args.single("timeout") ?? "30") ?? 30
    let sessionId = args.single("session") ?? UUID().uuidString
    let allowInsecure = args.bool("allow-insecure")
    let allowLocalNetwork = args.bool("allow-local")
    let agentToken = args.single("agent-token")

    // Parse headers preserving raw form (for placeholder scanning) and split
    // form (for HTTP delivery).
    var headerPairs: [(String, String)] = []
    var headerNames: [String] = []
    for raw in headerArgs {
        guard let colon = raw.firstIndex(of: ":") else {
            eprint("error: malformed --header '\(raw)' (expected 'Name: value')")
            return 1
        }
        let name = String(raw[..<colon]).trimmingCharacters(in: .whitespaces)
        let value = String(raw[raw.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        headerPairs.append((name, value))
        headerNames.append(name)
    }

    var bodyText: String? = bodyArg
    if let bodyFileArg, !bodyFileArg.isEmpty {
        do {
            bodyText = try String(contentsOfFile: bodyFileArg, encoding: .utf8)
        } catch {
            eprint("error: could not read --body-file: \(error)")
            return 1
        }
    }

    // Collect placeholders from URL + headers + body.
    var allText: [String] = [urlString]
    for (_, v) in headerPairs { allText.append(v) }
    if let body = bodyText { allText.append(body) }
    let tokens = PlaceholderResolver.tokens(in: allText)

    let host = url.host ?? ""
    let scheme = url.scheme?.lowercased() ?? "https"
    let isInsecure = scheme == "http"
    let isLocal = host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local")
    let inUrl = PlaceholderResolver.tokens(in: urlString).count > 0
    let inBody = (bodyText.flatMap { PlaceholderResolver.tokens(in: $0) } ?? []).count > 0
    let inEnv = false
    let context = ResolveContext(
        host: host,
        method: method,
        headerNames: headerNames,
        inUrl: inUrl,
        inBody: inBody,
        inEnv: inEnv,
        insecureTransport: isInsecure,
        localNetwork: isLocal
    )

    if isInsecure && !allowInsecure {
        eprint("error: refusing to use insecure http://. Pass --allow-insecure to override (still subject to vault policy).")
        return 1
    }
    if isLocal && !allowLocalNetwork {
        eprint("error: refusing to call a local-network host. Pass --allow-local to override (still subject to vault policy).")
        return 1
    }

    let client = ProxyClient(path: socketPath)
    var resolveReq = ProxyRequest(op: .resolvePlaceholders)
    resolveReq.placeholders = tokens
    resolveReq.context = context
    resolveReq.sessionId = sessionId
    resolveReq.agentToken = agentToken
    let resolveResp: ProxyResponse
    do {
        resolveResp = try client.send(resolveReq)
    } catch {
        eprint("error: \(error)")
        return 3
    }
    guard resolveResp.ok else {
        eprint("error: \(resolveResp.error ?? "unknown")")
        client.close()
        return 4
    }
    let values = resolveResp.values ?? [:]
    let labels = resolveResp.redactionLabels ?? [:]
    let sensitive = resolveResp.sensitiveValues ?? []

    let resolvedURLString = PlaceholderResolver.substitute(urlString, with: values)
    guard let resolvedURL = URL(string: resolvedURLString) else {
        eprint("error: substituted URL is invalid: \(resolvedURLString)")
        client.close()
        return 1
    }
    let resolvedHeaders: [(String, String)] = headerPairs.map { (n, v) in
        (n, PlaceholderResolver.substitute(v, with: values))
    }
    let resolvedBody = bodyText.map { PlaceholderResolver.substitute($0, with: values) }

    var redactionEntries: [RedactionEntry] = []
    var resolvedSecretNames: [String] = []
    for token in tokens {
        guard let value = values[token.raw] else { continue }
        let label = labels[token.raw] ?? Redactor.label(forSecretInternalName: token.secretInternalName)
        redactionEntries.append(RedactionEntry(value: value, label: label))
        if !resolvedSecretNames.contains(token.secretInternalName) {
            resolvedSecretNames.append(token.secretInternalName)
        }
    }
    // Also include any sensitive values reported by the resolver that aren't
    // already covered by a token (defensive).
    for v in sensitive where !redactionEntries.contains(where: { $0.value == v }) {
        redactionEntries.append(RedactionEntry(value: v, label: "[REDACTED]"))
    }

    var urlRequest = URLRequest(url: resolvedURL)
    urlRequest.httpMethod = method
    urlRequest.timeoutInterval = timeoutSec
    for (n, v) in resolvedHeaders {
        urlRequest.setValue(v, forHTTPHeaderField: n)
    }
    if let body = resolvedBody {
        urlRequest.httpBody = Data(body.utf8)
    }

    let started = Date()
    let semaphore = DispatchSemaphore(value: 0)
    var result: (Data?, URLResponse?, Error?) = (nil, nil, nil)
    let task = URLSession.shared.dataTask(with: urlRequest) { data, response, error in
        result = (data, response, error)
        semaphore.signal()
    }
    task.resume()
    _ = semaphore.wait(timeout: .now() + timeoutSec + 1)
    let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)

    var auditCall = ProxyAuditCallSummary(
        kind: "proxy_request",
        host: host,
        method: method,
        latencyMs: elapsedMs,
        sessionId: sessionId,
        secretInternalNames: resolvedSecretNames
    )
    var status: Int32 = 0
    if let error = result.2 {
        let masked = Redactor.redact(String(describing: error), with: redactionEntries)
        eprint("error: \(masked)")
        auditCall.success = false
        auditCall.errorCode = String(describing: type(of: error))
        status = 5
    } else if let http = result.1 as? HTTPURLResponse, let data = result.0 {
        let bodyString = String(data: data, encoding: .utf8) ?? "<binary \(data.count) bytes>"
        let redactedBody = Redactor.redact(bodyString, with: redactionEntries)
        let headerLines = http.allHeaderFields.map { (k, v) -> String in
            "\(k): \(Redactor.redact(String(describing: v), with: redactionEntries))"
        }.sorted().joined(separator: "\n")
        writeLineToStdout("HTTP/\(http.statusCode)")
        writeLineToStdout(headerLines)
        writeLineToStdout("")
        writeLineToStdout(redactedBody)
        auditCall.success = http.statusCode < 400
        auditCall.responseSize = data.count
        let redactedRequest = """
        \(method) \(Redactor.redact(resolvedURLString, with: redactionEntries))
        \(resolvedHeaders.map { "\($0.0): \(Redactor.redact($0.1, with: redactionEntries))" }.joined(separator: "\n"))
        """
        auditCall.redactedRequest = redactedRequest
        if http.statusCode >= 400 {
            auditCall.errorCode = "HTTP_\(http.statusCode)"
            status = 6
        }
    }

    var auditReq = ProxyRequest(op: .audit)
    auditReq.auditCall = auditCall
    auditReq.sessionId = sessionId
    _ = try? client.send(auditReq)
    client.close()
    return status
}

// MARK: - Entry

func printHelp() {
    writeLineToStdout("""
clawix-secrets-proxy · vault-aware HTTP proxy and secret resolver

Usage:
  clawix-secrets-proxy list-secrets [--search <text>] [--vault <name>] [--kind <kind>] [--json]
  clawix-secrets-proxy describe-secret --name <internal_name> [--json]
  clawix-secrets-proxy request --url <URL> [--method GET|POST|...] [--header "K: V"]... [--body STR | --body-file PATH] [--timeout SEC] [--allow-insecure] [--allow-local] [--agent-token TOKEN]
  clawix-secrets-proxy exec [--env "KEY={{secret}}"]... [--host HOST] [--agent-token TOKEN] -- CMD [ARGS...]
  clawix-secrets-proxy request-activation --agent <id> --secret <internal_name> --capability <cap> --reason "<text>" [--duration-minutes N] [--scope key=value]... [--json]
  clawix-secrets-proxy list-grants [--json]
  clawix-secrets-proxy revoke-grant --grant-id <UUID>
  clawix-secrets-proxy doctor [--json]

Placeholders in --url, --header values, --body resolve via the vault:
  {{secret_internal_name}}            -> primary secret field
  {{secret_internal_name.field_name}} -> a specific field

The vault must be unlocked in the running Clawix app for any operation
except `doctor`. All output is automatically redacted.
""")
}

let argv = CommandLine.arguments
guard let parsed = parseArgs(argv) else {
    printHelp()
    exit(1)
}

let exitCode: Int32
switch parsed.op {
case "help":
    printHelp()
    exitCode = 0
case "list-secrets":
    exitCode = runListSecrets(parsed)
case "describe-secret":
    exitCode = runDescribeSecret(parsed)
case "request":
    exitCode = runRequest(parsed)
case "exec":
    exitCode = runExec(parsed)
case "doctor":
    exitCode = runDoctor(parsed)
case "request-activation":
    exitCode = runRequestActivation(parsed)
case "list-grants":
    exitCode = runListGrants(parsed)
case "revoke-grant":
    exitCode = runRevokeGrant(parsed)
default:
    printHelp()
    exitCode = 1
}
exit(exitCode)
