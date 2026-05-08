import Foundation
import SwiftUI
import GRDB
import SecretsCrypto
import SecretsModels
import SecretsPersistence
import SecretsProxyCore
import SecretsVault
import ClawixArgon2

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

    @Published private(set) var state: State = .loading
    @Published private(set) var lastError: String?
    @Published private(set) var store: SecretsStore?
    @Published private(set) var audit: AuditStore?
    @Published private(set) var grants: AgentGrantStore?
    @Published private(set) var vaults: [VaultRecord] = []
    @Published private(set) var secrets: [SecretRecord] = []
    @Published private(set) var trashedSecrets: [SecretRecord] = []
    @Published private(set) var integrityReport: AuditIntegrityReport?
    @Published var pendingApprovals: [PendingApprovalRequest] = []
    @Published private(set) var activeGrants: [AgentGrantRecord] = []
    @Published private(set) var openAnomalies: [Anomaly] = []
    private var seenAnomalyIDs: Set<String> = []

    private(set) var database: SecretsDatabase?
    private(set) var meta: VaultMetaSnapshot?
    private(set) var masterKey: LockableSecret?
    private(set) var auditMacKey: LockableSecret?

    var autoLockMinutes: Int = 5
    private var autoLockTask: Task<Void, Never>?
    private var lifecycle: VaultLifecycle?
    @Published private(set) var proxyBridge: ProxyBridgeServer?

    init() {
        self.lifecycle = VaultLifecycle(attaching: self)
        let bridge = ProxyBridgeServer(vault: self)
        bridge.start()
        self.proxyBridge = bridge
        Task { await load() }
    }

    func load() async {
        state = .loading
        do {
            try VaultPaths.ensureDirectory()
            let db = try SecretsDatabase(at: VaultPaths.databaseFile)
            self.database = db
            if let snapshot = try VaultMetaStore.read(from: db) {
                self.meta = snapshot
                state = .locked
            } else {
                state = .uninitialized
            }
        } catch {
            state = .openFailed(String(describing: error))
            lastError = String(describing: error)
        }
    }

    func setUp(masterPassword: String) async throws -> [String] {
        guard state == .uninitialized else { throw Error.invalidState }
        guard let database else { throw Error.databaseUnavailable }

        let params = Calibration.calibrate()
        let bootstrap = try VaultCrypto.setUp(
            masterPassword: masterPassword,
            kdfParams: params,
            deviceId: VaultPaths.deviceId(),
            appVersion: Self.bundleAppVersion()
        )
        try VaultMetaStore.write(bootstrap.meta, to: database)
        self.meta = bootstrap.meta
        self.masterKey = bootstrap.masterKey
        self.auditMacKey = bootstrap.auditMacKey
        try mountStore(
            database: database,
            masterKey: bootstrap.masterKey,
            auditMacKey: bootstrap.auditMacKey,
            meta: bootstrap.meta,
            seedDefaultVault: true
        )
        try? audit?.append(NewAuditEvent(kind: .vaultSetup, source: .system, success: true))
        state = .unlocked
        scheduleAutoLock()
        return bootstrap.recoveryPhrase
    }

    func unlock(masterPassword: String) async throws {
        guard let meta else { throw Error.notSetUp }
        guard state == .locked else { throw Error.invalidState }
        state = .unlocking
        do {
            let result = try VaultCrypto.unlock(masterPassword: masterPassword, meta: meta)
            self.masterKey = result.masterKey
            self.auditMacKey = result.auditMacKey
            if let database {
                try mountStore(
                    database: database,
                    masterKey: result.masterKey,
                    auditMacKey: result.auditMacKey,
                    meta: meta,
                    seedDefaultVault: false
                )
            }
            try? audit?.append(NewAuditEvent(kind: .vaultUnlock, source: .system, success: true))
            try? autoPurgeTrashIfNeeded()
            state = .unlocked
            scheduleAutoLock()
            Task { await AnomalyNotifier.requestAuthorizationIfNeeded() }
            _ = runAnomalyDetector()
        } catch {
            state = .locked
            lastError = String(describing: error)
            throw error
        }
    }

    func recover(phrase: [String]) async throws {
        guard let meta else { throw Error.notSetUp }
        let result = try VaultCrypto.recover(recoveryPhrase: phrase, meta: meta)
        self.masterKey = result.masterKey
        self.auditMacKey = result.auditMacKey
        if let database {
            try mountStore(
                database: database,
                masterKey: result.masterKey,
                auditMacKey: result.auditMacKey,
                meta: meta,
                seedDefaultVault: false
            )
        }
        try? audit?.append(NewAuditEvent(kind: .vaultRecoveryUsed, source: .system, success: true))
        state = .unlocked
        scheduleAutoLock()
    }

    func changePassword(newPassword: String) async throws -> [String] {
        guard state == .unlocked,
              let database,
              let currentMaster = masterKey,
              let currentMeta = meta
        else { throw Error.notUnlocked }

        let result = try VaultCrypto.changePassword(
            currentMasterKey: currentMaster,
            newPassword: newPassword,
            currentMeta: currentMeta
        )
        try VaultMetaStore.write(result.meta, to: database)
        self.meta = result.meta
        self.masterKey = result.masterKey
        // Rebuild store/audit with the new master + (preserved) audit MAC key.
        try mountStore(
            database: database,
            masterKey: result.masterKey,
            auditMacKey: result.auditMacKey,
            meta: result.meta,
            seedDefaultVault: false
        )
        try? audit?.append(NewAuditEvent(kind: .vaultPasswordChange, source: .system, success: true))
        return result.newRecoveryPhrase
    }

    func lock() {
        autoLockTask?.cancel()
        autoLockTask = nil
        // Emit lock event BEFORE zeroing the audit key so the chain stays intact.
        try? audit?.append(NewAuditEvent(kind: .vaultLock, source: .system, success: true))
        masterKey?.zero()
        auditMacKey?.zero()
        masterKey = nil
        auditMacKey = nil
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
        // Resolve any pending approvals as denied so blocked helper threads
        // don't hang forever after the vault locks behind them.
        for pending in pendingApprovals {
            pending.deny(reason: "vault locked while waiting for approval")
        }
        pendingApprovals = []
        if state == .unlocked || state == .unlocking {
            state = .locked
        }
    }

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
            } catch SecretsStoreError.duplicateInternalName {
                skipped += 1
            }
        }
        try? audit?.append(NewAuditEvent(
            kind: .vaultImport,
            source: .system,
            success: true,
            payload: AuditEventPayload(
                notes: "Imported \(imported) from \(preview.format), skipped \(skipped) duplicates"
            )
        ))
        reload()
        return preview
    }

    func exportEncryptedBackup(passphrase: String) throws -> Data {
        guard let store else { throw Error.notUnlocked }
        let snapshot = try store.snapshotForBackup()
        try? audit?.append(NewAuditEvent(
            kind: .vaultExport,
            source: .system,
            success: true,
            payload: AuditEventPayload(
                notes: "Exported \(snapshot.secrets.count) secret\(snapshot.secrets.count == 1 ? "" : "s")"
            )
        ))
        return try BackupCodec.pack(contents: snapshot, passphrase: passphrase)
    }

    @discardableResult
    func importEncryptedBackup(_ data: Data, passphrase: String) throws -> (created: Int, skipped: Int) {
        guard let store else { throw Error.notUnlocked }
        let contents = try BackupCodec.unpack(data: data, passphrase: passphrase)
        let result = try store.restoreBackup(contents)
        try? audit?.append(NewAuditEvent(
            kind: .vaultImport,
            source: .system,
            success: true,
            payload: AuditEventPayload(
                notes: "Imported \(result.created) from .clawixvault (skipped \(result.skipped))"
            )
        ))
        reload()
        return result
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
        do {
            let url = try ProxyBridgeServer.installCliSymlink()
            try? audit?.append(NewAuditEvent(
                kind: .adminEdit,
                source: .system,
                success: true,
                payload: AuditEventPayload(notes: "Installed CLI symlink at \(url.path)")
            ))
            return url
        } catch {
            lastError = String(describing: error)
            return nil
        }
    }

    /// Sweeps the recent audit log for anomalies. New anomalies (not
    /// seen this session) are recorded as `anomaly_detected` audit
    /// events and surface as macOS notifications when the user has
    /// granted UNUserNotificationCenter authorization.
    @discardableResult
    func runAnomalyDetector(notify: Bool = true) -> [Anomaly] {
        guard let audit else { return [] }
        let recent = (try? audit.recentEvents(limit: 1000)) ?? []
        let anomalies = AnomalyDetector.detect(events: recent)
        let fresh = anomalies.filter { !seenAnomalyIDs.contains($0.id) }
        for anomaly in fresh {
            seenAnomalyIDs.insert(anomaly.id)
            try? audit.append(NewAuditEvent(
                kind: .anomalyDetected,
                source: .system,
                secretId: anomaly.secretId,
                vaultId: nil,
                success: false,
                payload: AuditEventPayload(
                    notes: anomaly.summary,
                    secretInternalNameFrozen: anomaly.secretInternalName
                )
            ))
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
            if !report.isIntact {
                try? audit.append(NewAuditEvent(kind: .auditIntegrityFailed, source: .system, success: false))
            }
            return report
        } catch {
            lastError = String(describing: error)
            return nil
        }
    }

    private func autoPurgeTrashIfNeeded() throws {
        guard let store else { return }
        let cutoff = Clock.now() - (Int64(30) * 24 * 60 * 60 * 1000) // 30 days
        _ = try store.purgeTrashed(olderThan: cutoff)
    }

    private func mountStore(
        database: SecretsDatabase,
        masterKey: LockableSecret,
        auditMacKey: LockableSecret,
        meta: VaultMetaSnapshot,
        seedDefaultVault: Bool
    ) throws {
        let auditStore = AuditStore(
            database: database,
            auditMacKey: auditMacKey,
            chainGenesis: meta.auditChainGenesis,
            deviceId: meta.deviceId
        )
        let store = SecretsStore(database: database, masterKey: masterKey, audit: auditStore)
        let grantStore = AgentGrantStore(database: database)
        if seedDefaultVault {
            let existing = try store.listVaults(includeTrashed: true)
            if existing.isEmpty {
                _ = try store.createVault(name: "Personal")
            }
        }
        self.audit = auditStore
        self.store = store
        self.grants = grantStore
        self.vaults = try store.listVaults()
        SecretsFixtureLoader.loadIfNeeded(store: store, vaults: self.vaults)
        self.secrets = try store.listSecrets()
        self.trashedSecrets = try store.listSecrets(includeTrashed: true).filter { $0.trashedAt != nil }
        self.activeGrants = (try? grantStore.listActive()) ?? []
        // Sweep grants that expired while the vault was locked; emit grant_expired events.
        let resolver = ProxyResolver(store: store, audit: auditStore, grants: grantStore)
        _ = try? resolver.sweepAndAuditExpiredGrants()
    }

    func reloadGrants() {
        guard let grants else { return }
        self.activeGrants = (try? grants.listActive()) ?? []
    }

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

    private static func bundleAppVersion() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        if !version.isEmpty && !build.isEmpty {
            return "\(version) (\(build))"
        }
        return version.isEmpty ? build : version
    }
}

extension VaultManager {
    enum Error: Swift.Error, CustomStringConvertible {
        case invalidState
        case databaseUnavailable
        case notSetUp
        case notUnlocked

        var description: String {
            switch self {
            case .invalidState: return "VaultManager: invalid state for this operation"
            case .databaseUnavailable: return "VaultManager: database not available"
            case .notSetUp: return "VaultManager: vault has not been set up"
            case .notUnlocked: return "VaultManager: vault is not unlocked"
            }
        }
    }
}
