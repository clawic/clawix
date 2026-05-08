import Foundation
import SecretsModels
import SecretsProxyCore
import SecretsVault

/// UDS bridge between the helper binary `clawix-secrets-proxy` and the macOS
/// app. Listens on `~/Library/Application Support/Clawix/secrets/proxy.sock`,
/// reads JSON-per-line frames, and dispatches each request to the live
/// `VaultManager` on the main actor. Returns `vault locked` errors when the
/// vault is not ready; the helper surfaces those to the caller.
@MainActor
final class ProxyBridgeServer: ObservableObject {

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var lastError: String?

    private let vault: VaultManager
    private var socketServer: UnixSocketServer?
    private let acceptQueue = DispatchQueue(label: "clawix.proxy-bridge.accept")
    private let connectionQueue = DispatchQueue(label: "clawix.proxy-bridge.conn", attributes: .concurrent)

    init(vault: VaultManager) {
        self.vault = vault
    }

    func start() {
        guard socketServer == nil else { return }
        let path = VaultPaths.proxySocketFile.path
        do {
            let server = try UnixSocketServer(path: path, queue: acceptQueue) { [weak self] fd in
                self?.handleConnection(fd)
            }
            self.socketServer = server
            self.isRunning = true
            self.lastError = nil
        } catch {
            self.lastError = String(describing: error)
            self.isRunning = false
        }
    }

    func stop() {
        socketServer?.stop()
        socketServer = nil
        isRunning = false
    }

    private nonisolated func handleConnection(_ fd: Int32) {
        // The accept queue receives the bare FD; hop to a per-connection
        // worker so the listener stays responsive under load.
        connectionQueue.async { [weak self] in
            guard let self else { return }
            UnixSocketReader.readLines(from: fd) { line -> Bool in
                let response = self.processLineSync(line)
                let encoded = (try? ProxyWireCodec.encode(response)) ?? Data()
                let cont = UnixSocketReader.writeLine(encoded, to: fd)
                return cont
            }
            UnixSocketReader.close(fd)
        }
    }

    private nonisolated func processLineSync(_ line: Data) -> ProxyResponse {
        let request: ProxyRequest
        do {
            request = try ProxyWireCodec.decodeRequest(from: line)
        } catch {
            return ProxyResponse.errorResponse("Malformed request: \(error)")
        }
        // Hop to MainActor synchronously to read VaultManager state. The Bridge
        // server is opt-in for reads only on this path; the per-connection
        // queue blocks on the dispatch.
        let semaphore = DispatchSemaphore(value: 0)
        var response: ProxyResponse = ProxyResponse.errorResponse("internal error")
        Task { @MainActor in
            response = await self.handleOnMainActor(request)
            semaphore.signal()
        }
        semaphore.wait()
        return response
    }

    private func handleOnMainActor(_ request: ProxyRequest) async -> ProxyResponse {
        // Doctor is the only op tolerated when locked: it tells the caller
        // exactly what state the vault is in.
        if request.op == .doctor {
            return doctorResponse()
        }
        guard vault.state == .unlocked, let store = vault.store else {
            return ProxyResponse.errorResponse("vault is locked or not yet set up; open Clawix to unlock")
        }
        let resolver = ProxyResolver(store: store, audit: vault.audit, grants: vault.grants)
        do {
            switch request.op {
            case .listSecrets:
                let described = try resolver.handleListSecrets(
                    search: request.search,
                    vaultName: request.vaultName,
                    kindRaw: request.kind
                )
                return ProxyResponse(ok: true, secrets: described)
            case .describeSecret:
                guard let name = request.name else {
                    return ProxyResponse.errorResponse("missing 'name' for describe-secret")
                }
                let described = try resolver.handleDescribeSecret(name: name)
                return ProxyResponse(ok: true, secret: described)
            case .resolvePlaceholders:
                guard let placeholders = request.placeholders, !placeholders.isEmpty else {
                    return ProxyResponse.errorResponse("missing placeholders")
                }
                let context = request.context ?? ResolveContext()
                if let token = request.agentToken, !token.isEmpty {
                    do {
                        _ = try resolver.validateAndConsumeAgentToken(
                            token,
                            sessionId: request.sessionId
                        )
                    } catch {
                        return ProxyResponse.errorResponse("agent token rejected: \(error)")
                    }
                }
                let result = try resolver.handleResolve(placeholders: placeholders, context: context)
                return ProxyResponse(
                    ok: true,
                    values: result.values,
                    sensitiveValues: result.sensitiveValues,
                    redactionLabels: result.redactionLabels
                )
            case .audit:
                guard let call = request.auditCall else {
                    return ProxyResponse.errorResponse("missing audit call summary")
                }
                try resolver.recordAuditCall(call, secretInternalNames: call.secretInternalNames)
                return ProxyResponse(ok: true)
            case .doctor:
                return doctorResponse()
            case .requestActivation:
                guard let activation = request.activation else {
                    return ProxyResponse.errorResponse("missing 'activation' payload for request-activation")
                }
                return await handleActivation(activation: activation, sessionId: request.sessionId, resolver: resolver)
            case .listGrants:
                let listed = try resolver.handleListGrants()
                return ProxyResponse(ok: true, grants: listed)
            case .revokeGrant:
                guard let raw = request.grantId, let id = UUID(uuidString: raw) else {
                    return ProxyResponse.errorResponse("missing or malformed 'grantId' for revoke-grant")
                }
                _ = try resolver.revokeGrant(id: id, sessionId: request.sessionId)
                vault.reloadGrants()
                return ProxyResponse(ok: true)
            }
        } catch {
            return ProxyResponse.errorResponse(String(describing: error))
        }
    }

    private func handleActivation(
        activation: ActivationRequest,
        sessionId: String?,
        resolver: ProxyResolver
    ) async -> ProxyResponse {
        // Validate up front (capability + secret exist) so we never bother the
        // user with an obviously-broken request.
        let prepared: (ProxyResolver.PendingActivation, AgentCapability)
        do {
            prepared = try resolver.prepareActivation(activation)
        } catch {
            return ProxyResponse.errorResponse(String(describing: error))
        }
        let outcome = await vault.requestActivationFromAgent(activation)
        switch outcome {
        case .approved:
            do {
                let issued = try resolver.issueAfterApproval(
                    request: activation,
                    capability: prepared.1,
                    sessionId: sessionId
                )
                vault.reloadGrants()
                let info = IssuedTokenInfo(
                    token: issued.plain,
                    grantId: issued.grant.id.uuidString.uppercased(),
                    agent: activation.agent,
                    capability: activation.capability,
                    secretInternalName: activation.secretInternalName,
                    expiresAt: issued.grant.expiresAt,
                    durationMinutes: activation.durationMinutes,
                    scope: activation.scope
                )
                return ProxyResponse(ok: true, issuedToken: info)
            } catch {
                return ProxyResponse.errorResponse("activation issued but grant write failed: \(error)")
            }
        case .denied(let reason):
            try? resolver.recordActivationDenied(
                request: activation,
                reason: reason,
                sessionId: sessionId
            )
            return ProxyResponse.errorResponse(reason ?? "activation denied by user")
        }
    }

    private func doctorResponse() -> ProxyResponse {
        let vaultExists = VaultPaths.vaultExists()
        let unlocked = vault.state == .unlocked
        let symlinkInstalled = ProxyBridgeServer.cliSymlinkInstalled()
        let report: DoctorReport
        if unlocked, let store = vault.store, let audit = vault.audit {
            let resolver = ProxyResolver(store: store, audit: audit)
            do {
                report = try resolver.handleDoctor(
                    symlinkPresent: symlinkInstalled,
                    helperPath: ProxyBridgeServer.bundledHelperPath()
                )
                return ProxyResponse(ok: true, doctor: report)
            } catch {
                return ProxyResponse.errorResponse(String(describing: error))
            }
        } else {
            report = DoctorReport(
                vaultExists: vaultExists,
                vaultLocked: vaultExists && !unlocked,
                symlinkInstalled: symlinkInstalled,
                helperPath: ProxyBridgeServer.bundledHelperPath()
            )
            return ProxyResponse(ok: true, doctor: report)
        }
    }

    static func cliSymlinkInstalled() -> Bool {
        let path = ("~/bin/clawix-secrets-proxy" as NSString).expandingTildeInPath
        return FileManager.default.fileExists(atPath: path)
    }

    static func bundledHelperPath() -> String? {
        let bundleHelper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/clawix-secrets-proxy").path
        if FileManager.default.fileExists(atPath: bundleHelper) {
            return bundleHelper
        }
        let cachesHelper = ("~/Library/Caches/Clawix-Dev/Clawix.app/Contents/Helpers/clawix-secrets-proxy" as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: cachesHelper) {
            return cachesHelper
        }
        return nil
    }

    static func installCliSymlink() throws -> URL {
        guard let helper = bundledHelperPath() else {
            throw NSError(domain: "ProxyBridgeServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "helper not found in app bundle"])
        }
        let binDir = ("~/bin" as NSString).expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: binDir, withIntermediateDirectories: true)
        let target = binDir + "/clawix-secrets-proxy"
        try? FileManager.default.removeItem(atPath: target)
        try FileManager.default.createSymbolicLink(atPath: target, withDestinationPath: helper)
        return URL(fileURLWithPath: target)
    }
}
