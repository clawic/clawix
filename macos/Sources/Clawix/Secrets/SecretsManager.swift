import Foundation
import SwiftUI
import SecretsModels
import SecretsVault
import SecretsProxyCore

/// SecretsManager owns the lifecycle of the local Secrets UI but delegates
/// every cryptographic and storage operation to the bundled ClawJS Vault
/// HTTP server. It keeps the surface that the existing SwiftUI views
/// consume (`store`, `audit`, `grants`, `vaults`, `secrets`, ...) so the
/// migration to ClawJS Vault is invisible to them.
///
/// Auth model: Clawix uses the per-session bearer token minted by the
/// signed host supervisor. Loopback alone is not trusted for Secrets.
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
final class SecretsManager: ObservableObject {
    struct EmergencyKit: Equatable {
        let recoveryPhrase: [String]
        let secretKey: String
    }

    /// Process-wide singleton. The SwiftUI root mounts this as a
    /// `@StateObject` (so views observe its `@Published` properties),
    /// while non-UI code (e.g., enhancement / transcription providers
    /// that need API keys at request time) reads it directly.
    static let shared = SecretsManager()

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
                return "Secrets service is not reachable on 127.0.0.1:\(ClawJSService.secrets.port)."
            default:
                return "Secrets service request failed: \(nsError.localizedDescription)"
            }
        }
        return error.localizedDescription
    }

    // MARK: - Internal

    var autoLockMinutes: Int = 5
    private var autoLockTask: Task<Void, Never>?
    private var lifecycle: SecretsLifecycle?
    private var loadGeneration: UUID?

    private let client: ClawJSSecretsClient

    init() {
        self.client = ClawJSSecretsClient.local()
        self.lifecycle = SecretsLifecycle(attaching: self)
        if Self.isDisabledForLaunch {
            self.state = .openFailed("Secrets service disabled for this launch.")
            self.lastError = "Secrets service disabled for this launch."
            return
        }
        Task { await load() }
    }

    init(client: ClawJSSecretsClient) {
        self.client = client
        self.lifecycle = SecretsLifecycle(attaching: self)
        if Self.isDisabledForLaunch {
            self.state = .openFailed("Secrets service disabled for this launch.")
            self.lastError = "Secrets service disabled for this launch."
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
                let message = "Secrets service did not become ready within 8 seconds."
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

    func setUp(masterPassword: String) async throws -> EmergencyKit {
        guard state == .uninitialized || state == .loading else { throw Error.invalidState }
        let result = try await client.setup(password: masterPassword, appVersion: Self.bundleAppVersion())
        try SecretsLocalSecretKey.store(result.secretKey)
        try await mountStores(seedDefaultVault: true)
        state = .unlocked
        scheduleAutoLock()
        return EmergencyKit(
            recoveryPhrase: result.recoveryPhrase.split(separator: " ").map { String($0) },
            secretKey: result.secretKey
        )
    }

    func unlock(masterPassword: String) async throws {
        guard state == .locked else { throw Error.invalidState }
        state = .unlocking
        do {
            guard let secretKey = try SecretsLocalSecretKey.load() else {
                throw Error.localSecretKeyMissing
            }
            try await client.unlock(password: masterPassword, secretKey: secretKey)
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

    func recover(phrase: [String], newPassword: String) async throws -> EmergencyKit {
        let joined = phrase.map { $0.lowercased() }.joined(separator: " ")
        let result = try await client.recover(phrase: joined, newPassword: newPassword)
        try SecretsLocalSecretKey.store(result.secretKey)
        try await mountStores(seedDefaultVault: false)
        state = .unlocked
        scheduleAutoLock()
        return EmergencyKit(
            recoveryPhrase: result.recoveryPhrase.split(separator: " ").map { String($0) },
            secretKey: result.secretKey
        )
    }

    func changePassword(newPassword: String) async throws -> EmergencyKit {
        // We don't have the old password here; the HTTP server requires it.
        // For now we surface an error; the UI can collect both passwords
        // and call `changePassword(old:new:)` directly on the client.
        _ = newPassword
        throw Error.notUnlocked
    }

    func changePassword(oldPassword: String, newPassword: String) async throws -> EmergencyKit {
        guard state == .unlocked else { throw Error.notUnlocked }
        guard let oldSecretKey = try SecretsLocalSecretKey.load() else {
            throw Error.localSecretKeyMissing
        }
        let result = try await client.changePassword(old: oldPassword, oldSecretKey: oldSecretKey, new: newPassword)
        try SecretsLocalSecretKey.store(result.secretKey)
        return EmergencyKit(
            recoveryPhrase: result.recoveryPhrase.split(separator: " ").map { String($0) },
            secretKey: result.secretKey
        )
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
            pending.deny(reason: "Secrets locked while waiting for approval")
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

    func exportEncryptedBackup(passphrase: String, reauthSatisfied: Bool = false) async throws -> Data {
        try await client.exportBackup(passphrase: passphrase, reauthSatisfied: reauthSatisfied)
    }

    @discardableResult
    func importEncryptedBackup(_ data: Data, passphrase: String, reauthSatisfied: Bool = false) async throws -> (created: Int, skipped: Int) {
        let response = try await client.importBackup(data: data, passphrase: passphrase, reauthSatisfied: reauthSatisfied)
        let imported = response.imported
        let created = (imported["secrets"]?.value as? Int) ?? 0
        Task { await self.load() }
        return (created: created, skipped: 0)
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
        let bundledCLI = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/clawjs/node_modules/@clawjs/cli/bin/claw.mjs")
        guard FileManager.default.fileExists(atPath: bundledCLI.path) else {
            lastError = "Bundled claw CLI not found in the app bundle."
            return nil
        }

        let binDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("bin", isDirectory: true)
        let linkURL = binDir.appendingPathComponent("claw", isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: linkURL.path) {
                try FileManager.default.removeItem(at: linkURL)
            }
            try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: bundledCLI)
            lastError = nil
            return linkURL
        } catch {
            lastError = String(describing: error)
            return nil
        }
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
            let containers = try await Task.detached(priority: .userInitiated) {
                try storeShim.listVaults(includeTrashed: true)
            }.value
            if containers.isEmpty {
                _ = try await Task.detached(priority: .userInitiated) {
                    try storeShim.createVault(name: "Personal")
                }.value
            }
        }

        self.store = storeShim
        self.audit = auditShim
        self.grants = grantsShim
        _ = AgentStore.shared.migrateLegacyConnectionAuths(store: storeShim)
        let vaults = try? await Task.detached(priority: .userInitiated) {
            try storeShim.listVaults()
        }.value
        let secrets = try? await Task.detached(priority: .userInitiated) {
            try storeShim.listSecrets()
        }.value
        let trashed = try? await Task.detached(priority: .userInitiated) {
            try storeShim.listSecrets(includeTrashed: true).filter { $0.trashedAt != nil }
        }.value
        let grants = try? await Task.detached(priority: .userInitiated) {
            try grantsShim.listActive()
        }.value
        self.vaults = vaults ?? []
        self.secrets = secrets ?? []
        self.trashedSecrets = trashed ?? []
        self.activeGrants = grants ?? []
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
        ProcessInfo.processInfo.environment["CLAWIX_SECRETS_DISABLE"] == "1"
    }
}

extension SecretsManager {
    enum Error: Swift.Error, CustomStringConvertible {
        case invalidState
        case notSetUp
        case notUnlocked
        case localSecretKeyMissing

        var description: String {
            switch self {
            case .invalidState: return "Secrets manager: invalid state for this operation"
            case .notSetUp: return "SecretsManager: Secrets has not been set up"
            case .notUnlocked: return "SecretsManager: Secrets is not unlocked"
            case .localSecretKeyMissing: return "SecretsManager: local Secret Key is missing. Use the Emergency Kit recovery flow."
            }
        }
    }
}
