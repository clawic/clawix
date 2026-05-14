import AIProviders
import Foundation
import SecretsModels
import SecretsVault

/// Concrete `AIAccountStore` that persists provider accounts as
/// `SecretRecord`s in the existing Clawix vault. Each account is one
/// secret keyed by `internalName: "provider:<id>:<uuid>"`.
///
/// We split fields into two groups:
///
/// - Plaintext metadata (label, isEnabled, createdAt, lastUsedAt,
///   accountEmail, baseURL, authMethod) — `isSecret: false`.
/// - Credentials (apiKey, access_token, refresh_token, expires_at,
///   scope) — `isSecret: true, isConcealed: true`.
///
/// The vault has no field-level edit API; mutations are done by
/// trashing the old secret and creating a new one carrying the same
/// `accountId`. The audit trail still tells the right story because
/// the trash event names the account, and the new secret carries the
/// same `internalName`.
@MainActor
final class AIAccountSecretsStore: AIAccountStore {

    static let shared = AIAccountSecretsStore()

    /// Container name for provider accounts. Uses the same "Clawix
    /// System" container `SystemSecrets` does, so users see one
    /// folder of app-owned secrets instead of two.
    static let containerName = "Clawix System"

    nonisolated init() {}

    // MARK: - List

    nonisolated func listAccounts() throws -> [ProviderAccount] {
        try perform { try self._listAccountsOnMain() }
    }

    nonisolated func listAccounts(for provider: ProviderID) throws -> [ProviderAccount] {
        try listAccounts().filter { $0.providerId == provider }
    }

    @MainActor
    private func _listAccountsOnMain() throws -> [ProviderAccount] {
        guard let store = SecretsManager.shared.store else {
            // Vault locked. Treat as "no accounts visible".
            return []
        }
        let secrets = (try? store.listSecrets(includeTrashed: false)) ?? []
        return secrets.compactMap { secret -> ProviderAccount? in
            guard let decoded = InternalName.decode(secret.internalName) else { return nil }
            do {
                let fields = try store.fetchFields(forSecret: secret.id, version: secret.currentVersionId)
                return Self.buildAccount(decoded: decoded, secret: secret, fields: fields, store: store)
            } catch {
                return nil
            }
        }
    }

    // MARK: - Create

    @discardableResult
    nonisolated func createAccount(_ draft: ProviderAccountDraft) throws -> ProviderAccount {
        try perform { try self._createOnMain(draft) }
    }

    @MainActor
    private func _createOnMain(_ draft: ProviderAccountDraft) throws -> ProviderAccount {
        guard let store = SecretsManager.shared.store else {
            throw AIAccountStoreError.vaultLocked
        }
        let trimmedLabel = draft.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmedLabel.isEmpty ? Self.fallbackLabel(for: draft.providerId, store: store) : trimmedLabel
        let existing = try _listAccountsOnMain().filter { $0.providerId == draft.providerId }
        if existing.contains(where: { $0.label.caseInsensitiveCompare(label) == .orderedSame }) {
            throw AIAccountStoreError.duplicateLabel
        }

        let accountId = UUID()
        let createdAt = Date()
        let container = try ensureContainer(in: store)

        let kind: SecretKind = (draft.authMethod == .apiKey || draft.authMethod == .none) ? .apiKey : .oauthToken
        let fields = Self.encodeFields(
            authMethod: draft.authMethod,
            label: label,
            isEnabled: true,
            createdAt: createdAt,
            lastUsedAt: nil,
            accountEmail: draft.accountEmail,
            baseURLOverride: draft.baseURLOverride,
            apiKey: draft.apiKey,
            accessToken: draft.accessToken,
            refreshToken: draft.refreshToken,
            expiresAt: draft.expiresAt,
            scope: draft.scope
        )

        let providerName = ProviderCatalog.definition(for: draft.providerId)?.displayName ?? draft.providerId.rawValue
        let title = "\(providerName) · \(label)"

        let internalName = InternalName.encode(providerId: draft.providerId, accountId: accountId)
        let secretDraft = DraftSecret(
            kind: kind,
            internalName: internalName,
            title: title,
            fields: fields
        )
        _ = try store.createSecret(in: container, draft: secretDraft)

        return ProviderAccount(
            id: accountId,
            providerId: draft.providerId,
            label: label,
            authMethod: draft.authMethod,
            isEnabled: true,
            createdAt: createdAt,
            lastUsedAt: nil,
            baseURLOverride: draft.baseURLOverride,
            accountEmail: draft.accountEmail
        )
    }

    // MARK: - Update metadata

    @discardableResult
    nonisolated func updateAccount(
        id: UUID,
        label: String?,
        isEnabled: Bool?,
        baseURLOverride: URL??,
        accountEmail: String??
    ) throws -> ProviderAccount {
        try perform {
            try self._updateMetadataOnMain(
                id: id,
                label: label,
                isEnabled: isEnabled,
                baseURLOverride: baseURLOverride,
                accountEmail: accountEmail
            )
        }
    }

    @MainActor
    private func _updateMetadataOnMain(
        id: UUID,
        label: String?,
        isEnabled: Bool?,
        baseURLOverride: URL??,
        accountEmail: String??
    ) throws -> ProviderAccount {
        guard let store = SecretsManager.shared.store else { throw AIAccountStoreError.vaultLocked }
        guard let (existing, secret, fields) = try findAccount(id: id, store: store) else {
            throw AIAccountStoreError.accountNotFound
        }

        let newLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? existing.label
        if let label, label.caseInsensitiveCompare(existing.label) != .orderedSame {
            let siblings = try _listAccountsOnMain().filter { $0.providerId == existing.providerId && $0.id != id }
            if siblings.contains(where: { $0.label.caseInsensitiveCompare(newLabel) == .orderedSame }) {
                throw AIAccountStoreError.duplicateLabel
            }
        }
        let newEnabled = isEnabled ?? existing.isEnabled
        let newBaseURL: URL? = baseURLOverride.map { $0 } ?? existing.baseURLOverride
        let newEmail: String? = accountEmail.map { $0 } ?? existing.accountEmail

        let credentials = revealCredentialsRaw(secret: secret, fields: fields, store: store)
        try replaceSecret(
            store: store,
            existing: existing,
            secret: secret,
            label: newLabel,
            isEnabled: newEnabled,
            createdAt: existing.createdAt,
            lastUsedAt: existing.lastUsedAt,
            accountEmail: newEmail,
            baseURLOverride: newBaseURL,
            apiKey: credentials.apiKey,
            accessToken: credentials.accessToken,
            refreshToken: credentials.refreshToken,
            expiresAt: credentials.expiresAt,
            scope: credentials.scope
        )
        return ProviderAccount(
            id: id,
            providerId: existing.providerId,
            label: newLabel,
            authMethod: existing.authMethod,
            isEnabled: newEnabled,
            createdAt: existing.createdAt,
            lastUsedAt: existing.lastUsedAt,
            baseURLOverride: newBaseURL,
            accountEmail: newEmail
        )
    }

    // MARK: - Update credentials

    nonisolated func updateCredentials(
        accountId: UUID,
        apiKey: String?,
        accessToken: String?,
        refreshToken: String?,
        expiresAt: Date?,
        scope: String?
    ) throws {
        try perform {
            try self._updateCredentialsOnMain(
                accountId: accountId,
                apiKey: apiKey,
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: expiresAt,
                scope: scope
            )
        }
    }

    @MainActor
    private func _updateCredentialsOnMain(
        accountId: UUID,
        apiKey: String?,
        accessToken: String?,
        refreshToken: String?,
        expiresAt: Date?,
        scope: String?
    ) throws {
        guard let store = SecretsManager.shared.store else { throw AIAccountStoreError.vaultLocked }
        guard let (existing, secret, _) = try findAccount(id: accountId, store: store) else {
            throw AIAccountStoreError.accountNotFound
        }
        try replaceSecret(
            store: store,
            existing: existing,
            secret: secret,
            label: existing.label,
            isEnabled: existing.isEnabled,
            createdAt: existing.createdAt,
            lastUsedAt: existing.lastUsedAt,
            accountEmail: existing.accountEmail,
            baseURLOverride: existing.baseURLOverride,
            apiKey: apiKey,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            scope: scope
        )
    }

    // MARK: - Touch

    nonisolated func touch(accountId: UUID) throws {
        try perform { try self._touchOnMain(accountId: accountId) }
    }

    @MainActor
    private func _touchOnMain(accountId: UUID) throws {
        guard let store = SecretsManager.shared.store else { return }
        guard let (existing, secret, fields) = try findAccount(id: accountId, store: store) else { return }
        let credentials = revealCredentialsRaw(secret: secret, fields: fields, store: store)
        try replaceSecret(
            store: store,
            existing: existing,
            secret: secret,
            label: existing.label,
            isEnabled: existing.isEnabled,
            createdAt: existing.createdAt,
            lastUsedAt: Date(),
            accountEmail: existing.accountEmail,
            baseURLOverride: existing.baseURLOverride,
            apiKey: credentials.apiKey,
            accessToken: credentials.accessToken,
            refreshToken: credentials.refreshToken,
            expiresAt: credentials.expiresAt,
            scope: credentials.scope
        )
    }

    // MARK: - Delete

    nonisolated func deleteAccount(id: UUID) throws {
        try perform { try self._deleteOnMain(id: id) }
    }

    @MainActor
    private func _deleteOnMain(id: UUID) throws {
        guard let store = SecretsManager.shared.store else { throw AIAccountStoreError.vaultLocked }
        guard let (_, secret, _) = try findAccount(id: id, store: store) else {
            throw AIAccountStoreError.accountNotFound
        }
        try store.trashSecret(id: secret.id)
    }

    // MARK: - Reveal credentials

    nonisolated func revealCredentials(accountId: UUID) throws -> AIAccountCredentials {
        try perform { try self._revealOnMain(accountId: accountId) }
    }

    @MainActor
    private func _revealOnMain(accountId: UUID) throws -> AIAccountCredentials {
        guard let store = SecretsManager.shared.store else { throw AIAccountStoreError.vaultLocked }
        guard let (_, secret, fields) = try findAccount(id: accountId, store: store) else {
            throw AIAccountStoreError.accountNotFound
        }
        let credentials = revealCredentialsRaw(secret: secret, fields: fields, store: store, emitAudit: true)
        if credentials.isEmpty {
            throw AIAccountStoreError.credentialMissing
        }
        return credentials
    }

    nonisolated func credentialExpiresAt(accountId: UUID) throws -> Date? {
        try perform { try self._credentialExpiresAtOnMain(accountId: accountId) }
    }

    @MainActor
    private func _credentialExpiresAtOnMain(accountId: UUID) throws -> Date? {
        guard let store = SecretsManager.shared.store else { throw AIAccountStoreError.vaultLocked }
        guard let (_, _, fields) = try findAccount(id: accountId, store: store) else {
            throw AIAccountStoreError.accountNotFound
        }
        guard let raw = fields.first(where: { !$0.isSecret && $0.fieldName == "expires_at" })?.publicValue else {
            return nil
        }
        return ISO8601.parse(raw)
    }

    nonisolated func hasCredentialField(accountId: UUID, fieldName: String) throws -> Bool {
        try perform { try self._hasCredentialFieldOnMain(accountId: accountId, fieldName: fieldName) }
    }

    @MainActor
    private func _hasCredentialFieldOnMain(accountId: UUID, fieldName: String) throws -> Bool {
        guard let store = SecretsManager.shared.store else { throw AIAccountStoreError.vaultLocked }
        guard let (_, _, fields) = try findAccount(id: accountId, store: store) else {
            throw AIAccountStoreError.accountNotFound
        }
        return fields.first(where: { (field: SecretFieldRecord) in
            field.isSecret && field.fieldName == fieldName && field.valueCiphertext != nil
        }) != nil
    }

    // MARK: - Helpers

    @MainActor
    private func ensureContainer(in store: ClawJSSecretsStore) throws -> VaultRecord {
        let containers = (try? store.listVaults()) ?? []
        if let existing = containers.first(where: { $0.name == Self.containerName }) {
            return existing
        }
        return try store.createVault(name: Self.containerName)
    }

    @MainActor
    private func findAccount(id: UUID, store: ClawJSSecretsStore) throws
        -> (account: ProviderAccount, secret: SecretRecord, fields: [SecretFieldRecord])?
    {
        let secrets = (try? store.listSecrets(includeTrashed: false)) ?? []
        for secret in secrets {
            guard let decoded = InternalName.decode(secret.internalName) else { continue }
            guard decoded.accountId == id else { continue }
            let fields = try store.fetchFields(forSecret: secret.id, version: secret.currentVersionId)
            guard let account = Self.buildAccount(decoded: decoded, secret: secret, fields: fields, store: store) else {
                return nil
            }
            return (account, secret, fields)
        }
        return nil
    }

    @MainActor
    private func replaceSecret(
        store: ClawJSSecretsStore,
        existing: ProviderAccount,
        secret: SecretRecord,
        label: String,
        isEnabled: Bool,
        createdAt: Date,
        lastUsedAt: Date?,
        accountEmail: String?,
        baseURLOverride: URL?,
        apiKey: String?,
        accessToken: String?,
        refreshToken: String?,
        expiresAt: Date?,
        scope: String?
    ) throws {
        let fields = Self.encodeFields(
            authMethod: existing.authMethod,
            label: label,
            isEnabled: isEnabled,
            createdAt: createdAt,
            lastUsedAt: lastUsedAt,
            accountEmail: accountEmail,
            baseURLOverride: baseURLOverride,
            apiKey: apiKey,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            scope: scope
        )
        let providerName = ProviderCatalog.definition(for: existing.providerId)?.displayName ?? existing.providerId.rawValue
        let title = "\(providerName) · \(label)"
        let kind: SecretKind = (existing.authMethod == .apiKey || existing.authMethod == .none) ? .apiKey : .oauthToken
        let internalName = secret.internalName
        try store.trashSecret(id: secret.id)
        let container = try ensureContainer(in: store)
        let draft = DraftSecret(
            kind: kind,
            internalName: internalName,
            title: title,
            fields: fields
        )
        _ = try store.createSecret(in: container, draft: draft)
    }

    /// Reveal helper used internally (and on the public `reveal` path).
    /// `emitAudit` is left to the public path; internal refreshes don't
    /// double-log a reveal that the caller already audited.
    @MainActor
    private func revealCredentialsRaw(
        secret: SecretRecord,
        fields: [SecretFieldRecord],
        store: ClawJSSecretsStore,
        emitAudit: Bool = false
    ) -> AIAccountCredentials {
        var creds = AIAccountCredentials()
        for field in fields where field.isSecret {
            let revealed: String?
            if emitAudit {
                revealed = (try? store.revealField(field, purpose: .reveal))?.value
            } else {
                revealed = (try? store.revealField(field, purpose: .reveal))?.value
            }
            switch field.fieldName {
            case "value": creds.apiKey = revealed
            case "access_token": creds.accessToken = revealed
            case "refresh_token": creds.refreshToken = revealed
            default: break
            }
        }
        for field in fields where !field.isSecret {
            switch field.fieldName {
            case "expires_at":
                if let str = field.publicValue, let date = ISO8601.parse(str) {
                    creds.expiresAt = date
                }
            case "scope":
                creds.scope = field.publicValue
            default: break
            }
        }
        return creds
    }

    nonisolated private func perform<T>(_ work: @MainActor () throws -> T) throws -> T {
        if Thread.isMainThread {
            return try MainActor.assumeIsolated { try work() }
        }
        return try DispatchQueue.main.sync {
            try MainActor.assumeIsolated { try work() }
        }
    }

    // MARK: - Field encoding/decoding

    /// Builds the canonical list of fields for a provider account
    /// secret. Uses the `sortOrder` to keep a stable visual ordering
    /// in any future Secrets UI that browses the system container.
    @MainActor
    private static func encodeFields(
        authMethod: AuthMethod,
        label: String,
        isEnabled: Bool,
        createdAt: Date,
        lastUsedAt: Date?,
        accountEmail: String?,
        baseURLOverride: URL?,
        apiKey: String?,
        accessToken: String?,
        refreshToken: String?,
        expiresAt: Date?,
        scope: String?
    ) -> [DraftField] {
        var fields: [DraftField] = []
        var order = 0
        func plain(_ name: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            fields.append(DraftField(
                name: name,
                fieldKind: .text,
                placement: .none,
                isSecret: false,
                isConcealed: false,
                publicValue: value,
                sortOrder: order
            ))
            order += 1
        }
        func secret(_ name: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            fields.append(DraftField(
                name: name,
                fieldKind: .password,
                placement: .header,
                isSecret: true,
                isConcealed: true,
                secretValue: value,
                sortOrder: order
            ))
            order += 1
        }
        plain("label", label)
        plain("authMethod", authMethod.storageTag)
        plain("isEnabled", isEnabled ? "true" : "false")
        plain("createdAt", ISO8601.format(createdAt))
        plain("lastUsedAt", lastUsedAt.map(ISO8601.format))
        plain("accountEmail", accountEmail)
        plain("baseURL", baseURLOverride?.absoluteString)
        plain("expires_at", expiresAt.map(ISO8601.format))
        plain("scope", scope)
        secret("value", apiKey)
        secret("access_token", accessToken)
        secret("refresh_token", refreshToken)
        return fields
    }

    @MainActor
    private static func buildAccount(
        decoded: InternalName.Decoded,
        secret: SecretRecord,
        fields: [SecretFieldRecord],
        store: ClawJSSecretsStore
    ) -> ProviderAccount? {
        var label: String?
        var authMethod: AuthMethod?
        var isEnabled = true
        var createdAt: Date?
        var lastUsedAt: Date?
        var accountEmail: String?
        var baseURLOverride: URL?
        for field in fields where !field.isSecret {
            guard let value = field.publicValue else { continue }
            switch field.fieldName {
            case "label": label = value
            case "authMethod": authMethod = AuthMethod(storageTag: value)
            case "isEnabled": isEnabled = (value == "true")
            case "createdAt": createdAt = ISO8601.parse(value)
            case "lastUsedAt": lastUsedAt = ISO8601.parse(value)
            case "accountEmail": accountEmail = value
            case "baseURL": baseURLOverride = URL(string: value)
            default: break
            }
        }
        guard let resolvedLabel = label, let resolvedMethod = authMethod else {
            return nil
        }
        return ProviderAccount(
            id: decoded.accountId,
            providerId: decoded.providerId,
            label: resolvedLabel,
            authMethod: resolvedMethod,
            isEnabled: isEnabled,
            createdAt: createdAt ?? secret.createdAt.date ?? Date(),
            lastUsedAt: lastUsedAt,
            baseURLOverride: baseURLOverride,
            accountEmail: accountEmail
        )
    }

    private static func fallbackLabel(for provider: ProviderID, store: ClawJSSecretsStore) -> String {
        let secrets = (try? store.listSecrets(includeTrashed: false)) ?? []
        let count = secrets.compactMap { InternalName.decode($0.internalName) }
            .filter { $0.providerId == provider }
            .count
        return count == 0 ? "Personal" : "Account \(count + 1)"
    }
}

// MARK: - ISO8601 helpers

private enum ISO8601 {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func format(_ date: Date) -> String {
        formatter.string(from: date)
    }

    static func parse(_ string: String) -> Date? {
        if let date = formatter.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}

// MARK: - Misc helpers

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private extension Timestamp {
    /// `Timestamp` (ms since epoch in this codebase) → Date.
    var date: Date? {
        Date(timeIntervalSince1970: TimeInterval(self) / 1000)
    }
}
