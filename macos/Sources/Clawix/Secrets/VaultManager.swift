import Foundation
import SwiftUI
import SecretsModels
import SecretsVault
import SecretsProxyCore

/// VaultManager owns the lifecycle of the local Secrets UI but delegates
/// every cryptographic and storage operation to the bundled ClawJS Vault
/// HTTP server. It keeps the surface that the existing SwiftUI views
/// consume (`store`, `audit`, `grants`, `vaults`, `secrets`, ...) so the
/// migration to ClawJS Vault is invisible to them.
///
/// Auth model: a process-wide bearer token is unused (the local Vault
/// trusts loopback callers). Future remote consumers can plug in a token.
@MainActor
final class PendingApprovalRequest: ObservableObject, Identifiable {
    nonisolated let id = UUID()
    let request: ActivationRequest
    let arrivedAt: Date
    private let continuation: CheckedContinuation<ProxyResolver.ActivationOutcome, Never>

    init(request: ActivationRequest, continuation: CheckedContinuation<ProxyResolver.ActivationOutcome, Never>) {
        self.request = request
        self.continuation = continuation
        self.arrivedAt = Date()
    }

    func approve() {
        continuation.resume(returning: .approved)
    }

    func deny(reason: String? = nil) {
        continuation.resume(returning: .denied(reason: reason))
    }
}

@MainActor
final class VaultManager: ObservableObject {

    enum State: Equatable {
        case loading
        case uninitialized
        case locked
        case unlocking
        case unlocked
        case openFailed(String)
    }

    // MARK: - Published surface (compatible with existing SwiftUI views)

    @Published private(set) var state: State = .loading
    @Published private(set) var lastError: String?
    @Published private(set) var store: ClawJSSecretsStore?
    @Published private(set) var audit: ClawJSAuditStore?
    @Published private(set) var grants: ClawJSGrantStore?
    @Published private(set) var vaults: [VaultRecord] = []
    @Published private(set) var secrets: [SecretRecord] = []
    @Published private(set) var trashedSecrets: [SecretRecord] = []
    @Published private(set) var integrityReport: AuditIntegrityReport?
    @Published var pendingApprovals: [PendingApprovalRequest] = []
    @Published private(set) var activeGrants: [AgentGrantRecord] = []
    @Published private(set) var openAnomalies: [Anomaly] = []
    private var seenAnomalyIDs: Set<String> = []

    private static func userFacingError(_ error: Swift.Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
            return localized
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch URLError.Code(rawValue: nsError.code) {
            case .cannotConnectToHost, .networkConnectionLost, .timedOut, .notConnectedToInternet:
                return "Vault service is not reachable on 127.0.0.1:\(ClawJSService.vault.port)."
            default:
                return "Vault service request failed: \(nsError.localizedDescription)"
            }
        }
        return error.localizedDescription
    }

    // MARK: - Internal

    var autoLockMinutes: Int = 5
    private var autoLockTask: Task<Void, Never>?
    private var lifecycle: VaultLifecycle?
    private var loadGeneration: UUID?

    private let client: ClawJSVaultClient

    init() {
        self.client = ClawJSVaultClient.local()
        self.lifecycle = VaultLifecycle(attaching: self)
        if Self.isDisabledForLaunch {
            self.state = .openFailed("Vault service disabled for this launch.")
            self.lastError = "Vault service disabled for this launch."
            return
        }
        Task { await load() }
    }

    init(client: ClawJSVaultClient) {
        self.client = client
        self.lifecycle = VaultLifecycle(attaching: self)
        if Self.isDisabledForLaunch {
            self.state = .openFailed("Vault service disabled for this launch.")
            self.lastError = "Vault service disabled for this launch."
            return
        }
        Task { await load() }
    }

    // MARK: - Lifecycle

    func load() async {
        state = .loading
        let generation = UUID()
        loadGeneration = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, self.loadGeneration == generation else { return }
            if case .loading = self.state {
                let message = "Vault service did not become ready within 8 seconds."
                self.state = .openFailed(message)
                self.lastError = message
            }
        }
        do {
            let info = try await client.state()
            if !info.initialized {
                #if DEBUG
                if ProcessInfo.processInfo.environment["CLAWIX_DUMMY_MODE"] == "1" {
                    await autoBootstrapDummyVault()
                    return
                }
                #endif
                state = .uninitialized
                loadGeneration = nil
                return
            }
            if info.unlocked {
                try await mountStores(seedDefaultVault: false)
                state = .unlocked
                scheduleAutoLock()
            } else {
                state = .locked
            }
            loadGeneration = nil
        } catch {
            let message = Self.userFacingError(error)
            state = .openFailed(message)
            lastError = message
            loadGeneration = nil
        }
    }

    #if DEBUG
    private func autoBootstrapDummyVault() async {
        let throwaway = "dummy-throwaway-\(UUID().uuidString)"
        do {
            _ = try await setUp(masterPassword: throwaway)
            autoLockMinutes = 0
        } catch {
            lastError = Self.userFacingError(error)
            state = .uninitialized
        }
    }
    #endif

    func setUp(masterPassword: String) async throws -> [String] {
        guard state == .uninitialized || state == .loading else { throw Error.invalidState }
        let result = try await client.setup(password: masterPassword, appVersion: Self.bundleAppVersion())
        try await mountStores(seedDefaultVault: true)
        state = .unlocked
        scheduleAutoLock()
        return result.recoveryPhrase.split(separator: " ").map { String($0) }
    }

    func unlock(masterPassword: String) async throws {
        guard state == .locked else { throw Error.invalidState }
        state = .unlocking
        do {
            try await client.unlock(password: masterPassword)
            try await mountStores(seedDefaultVault: false)
            state = .unlocked
            scheduleAutoLock()
            Task { await AnomalyNotifier.requestAuthorizationIfNeeded() }
            _ = runAnomalyDetector()
        } catch {
            state = .locked
            lastError = Self.userFacingError(error)
            throw error
        }
    }

    func recover(phrase: [String]) async throws {
        let joined = phrase.map { $0.lowercased() }.joined(separator: " ")
        try await client.recover(phrase: joined)
        try await mountStores(seedDefaultVault: false)
        state = .unlocked
        scheduleAutoLock()
    }

    func changePassword(newPassword: String) async throws -> [String] {
        // We don't have the old password here; the HTTP server requires it.
        // For now we surface an error; the UI can collect both passwords
        // and call `changePassword(old:new:)` directly on the client.
        _ = newPassword
        throw Error.notUnlocked
    }

    func changePassword(oldPassword: String, newPassword: String) async throws -> [String] {
        guard state == .unlocked else { throw Error.notUnlocked }
        let result = try await client.changePassword(old: oldPassword, new: newPassword)
        return result.recoveryPhrase.split(separator: " ").map { String($0) }
    }

    func lock() {
        autoLockTask?.cancel()
        autoLockTask = nil
        Task { try? await self.client.lock() }
        store = nil
        audit = nil
        grants = nil
        vaults = []
        secrets = []
        trashedSecrets = []
        integrityReport = nil
        activeGrants = []
        openAnomalies = []
        seenAnomalyIDs = []
        for pending in pendingApprovals {
            pending.deny(reason: "vault locked while waiting for approval")
        }
        pendingApprovals = []
        if state == .unlocked || state == .unlocking {
            state = .locked
        }
    }

    // MARK: - Reload

    func reload() {
        guard let store else { return }
        do {
            self.vaults = try store.listVaults()
            self.secrets = try store.listSecrets()
            self.trashedSecrets = try store.listSecrets(includeTrashed: true).filter { $0.trashedAt != nil }
        } catch {
            lastError = String(describing: error)
        }
    }

    // MARK: - Imports / exports

    enum ImportFormat: Equatable {
        case onePassword
        case bitwarden
        case env
    }

    @discardableResult
    func importSecrets(from contents: String, format: ImportFormat) throws -> ImportPreview {
        guard let store else { throw Error.notUnlocked }
        let preview: ImportPreview = try {
            switch format {
            case .onePassword: return try OnePasswordCSVImporter.parse(contents)
            case .bitwarden: return try BitwardenCSVImporter.parse(contents)
            case .env: return try EnvFileImporter.parse(contents)
            }
        }()
        let target: VaultRecord
        if let first = vaults.first {
            target = first
        } else {
            target = try store.createVault(name: "Personal")
        }
        var imported = 0
        var skipped = 0
        for draft in preview.drafts {
            do {
                _ = try store.createSecret(in: target, draft: draft)
                imported += 1
            } catch {
                skipped += 1
            }
        }
        reload()
        _ = imported // expose if we need a richer preview later
        _ = skipped
        return preview
    }

    func exportEncryptedBackup(passphrase: String) throws -> Data {
        // The HTTP backend does not yet expose backup; surface a clear
        // error rather than masquerade with empty data.
        _ = passphrase
        throw ClawJSBackendError.server("Encrypted backup not yet supported on the ClawJS Vault HTTP backend")
    }

    @discardableResult
    func importEncryptedBackup(_ data: Data, passphrase: String) throws -> (created: Int, skipped: Int) {
        _ = data
        _ = passphrase
        throw ClawJSBackendError.server("Encrypted backup import not yet supported on the ClawJS Vault HTTP backend")
    }

    func staleSecrets(olderThanDays days: Int) -> [SecretRecord] {
        let cutoff = Clock.now() - Int64(days) * 24 * 60 * 60 * 1000
        return secrets.filter { secret in
            guard let last = secret.lastUsedAt else { return secret.createdAt < cutoff }
            return last < cutoff
        }
    }

    @discardableResult
    func installCliSymlink() -> URL? {
        // No-op now: the bundled `claw` CLI lives inside the .app at
        // Contents/Helpers/clawjs and is invoked by the Mac app directly.
        return nil
    }

    // MARK: - Anomaly detector + integrity

    @discardableResult
    func runAnomalyDetector(notify: Bool = true) -> [Anomaly] {
        guard let audit else { return [] }
        let recent = (try? audit.recentEvents(limit: 1000)) ?? []
        let anomalies = AnomalyDetector.detect(events: recent)
        let fresh = anomalies.filter { !seenAnomalyIDs.contains($0.id) }
        for anomaly in fresh {
            seenAnomalyIDs.insert(anomaly.id)
            if notify {
                AnomalyNotifier.deliver(anomaly)
            }
        }
        self.openAnomalies = anomalies
        return anomalies
    }

    @discardableResult
    func runIntegrityCheck() -> AuditIntegrityReport? {
        guard let audit else { return nil }
        do {
            let report = try audit.verifyIntegrity()
            self.integrityReport = report
            return report
        } catch {
            lastError = String(describing: error)
            return nil
        }
    }

    // MARK: - Activation requests

    func requestActivationFromAgent(_ activation: ActivationRequest) async -> ProxyResolver.ActivationOutcome {
        await withCheckedContinuation { continuation in
            let pending = PendingApprovalRequest(request: activation, continuation: continuation)
            self.pendingApprovals.append(pending)
        }
    }

    func resolvePending(_ pending: PendingApprovalRequest, outcome: ProxyResolver.ActivationOutcome) {
        switch outcome {
        case .approved: pending.approve()
        case .denied(let reason): pending.deny(reason: reason)
        }
        pendingApprovals.removeAll { $0.id == pending.id }
    }

    // MARK: - Auto-lock

    func touch() {
        scheduleAutoLock()
    }

    private func scheduleAutoLock() {
        autoLockTask?.cancel()
        let minutes = autoLockMinutes
        guard minutes > 0 else {
            autoLockTask = nil
            return
        }
        let nanos = UInt64(minutes) * 60 * 1_000_000_000
        autoLockTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            await self?.lockFromTimer()
        }
    }

    private func lockFromTimer() {
        guard !Task.isCancelled else { return }
        lock()
    }

    func reloadGrants() {
        guard let grants else { return }
        self.activeGrants = (try? grants.listActive()) ?? []
    }

    // MARK: - Mount

    private func mountStores(seedDefaultVault: Bool) async throws {
        let storeShim = ClawJSSecretsStore(client: client)
        let auditShim = ClawJSAuditStore(client: client)
        let grantsShim = ClawJSGrantStore(client: client)

        if seedDefaultVault {
            let containers = try storeShim.listVaults(includeTrashed: true)
            if containers.isEmpty {
                _ = try storeShim.createVault(name: "Personal")
            }
        }

        self.store = storeShim
        self.audit = auditShim
        self.grants = grantsShim
        self.vaults = (try? storeShim.listVaults()) ?? []
        self.secrets = (try? storeShim.listSecrets()) ?? []
        self.trashedSecrets = (try? storeShim.listSecrets(includeTrashed: true).filter { $0.trashedAt != nil }) ?? []
        self.activeGrants = (try? grantsShim.listActive()) ?? []
    }

    // MARK: - Helpers

    private static func bundleAppVersion() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        if !version.isEmpty && !build.isEmpty {
            return "\(version) (\(build))"
        }
        return version.isEmpty ? build : version
    }

    private static var isDisabledForLaunch: Bool {
        ProcessInfo.processInfo.environment["CLAWIX_VAULT_DISABLE"] == "1"
    }
}

extension VaultManager {
    enum Error: Swift.Error, CustomStringConvertible {
        case invalidState
        case notSetUp
        case notUnlocked

        var description: String {
            switch self {
            case .invalidState: return "VaultManager: invalid state for this operation"
            case .notSetUp: return "VaultManager: vault has not been set up"
            case .notUnlocked: return "VaultManager: vault is not unlocked"
            }
        }
    }
}
