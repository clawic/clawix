import Foundation
import GRDB
import SecretsCrypto
import SecretsModels
import SecretsPersistence

public enum FieldAccessPurpose: Sendable, Hashable {
    case reveal
    case copy
}

public enum SecretsStoreError: Swift.Error, Equatable, CustomStringConvertible {
    case secretNotFound
    case fieldNotFound
    case duplicateInternalName(String)
    case vaultNotFound
    case lockedItemKey
    case versionNotFound

    public var description: String {
        switch self {
        case .secretNotFound: return "SecretsStore: secret not found"
        case .fieldNotFound: return "SecretsStore: field not found"
        case .duplicateInternalName(let name): return "SecretsStore: a secret named '\(name)' already exists"
        case .vaultNotFound: return "SecretsStore: vault not found"
        case .lockedItemKey: return "SecretsStore: could not unwrap item key"
        case .versionNotFound: return "SecretsStore: version not found"
        }
    }
}

public final class SecretsStore {

    public let database: SecretsDatabase
    private let masterKey: LockableSecret
    public let audit: AuditStore?

    public init(database: SecretsDatabase, masterKey: LockableSecret, audit: AuditStore? = nil) {
        self.database = database
        self.masterKey = masterKey
        self.audit = audit
    }

    // MARK: Vaults

    @discardableResult
    public func createVault(
        name: String,
        icon: String? = nil,
        color: String? = nil,
        sortOrder: Int = 0
    ) throws -> VaultRecord {
        let now = Clock.now()
        let vault = VaultRecord(
            name: name,
            icon: icon,
            color: color,
            sortOrder: sortOrder,
            createdAt: now,
            updatedAt: now
        )
        try database.write { db in try vault.insert(db) }
        try audit?.append(NewAuditEvent(
            kind: .adminCreate,
            source: .admin,
            vaultId: vault.id,
            success: true,
            payload: AuditEventPayload(notes: "Vault created: \(name)")
        ))
        return vault
    }

    public func listVaults(includeTrashed: Bool = false) throws -> [VaultRecord] {
        try database.read { db in
            var query: QueryInterfaceRequest<VaultRecord> = VaultRecord.all()
            if !includeTrashed {
                query = query.filter(Column("trashedAt") == nil)
            }
            return try query
                .order(Column("sortOrder").asc, Column("name").asc)
                .fetchAll(db)
        }
    }

    public func renameVault(id: EntityID, to newName: String) throws {
        let oldName = try database.write { db -> String in
            guard var vault = try VaultRecord.fetchOne(db, key: id.uuidString.uppercased()) else {
                throw SecretsStoreError.vaultNotFound
            }
            let previous = vault.name
            vault.name = newName
            vault.updatedAt = Clock.now()
            try vault.update(db)
            return previous
        }
        try audit?.append(NewAuditEvent(
            kind: .adminEdit,
            source: .admin,
            vaultId: id,
            success: true,
            payload: AuditEventPayload(notes: "Renamed vault from '\(oldName)' to '\(newName)'")
        ))
    }

    // MARK: Secrets

    @discardableResult
    public func createSecret(in vault: VaultRecord, draft: DraftSecret) throws -> SecretRecord {
        let secretId = EntityID.newID()
        let versionId = EntityID.newID()
        let now = Clock.now()

        // Per-item key wrapped by master.
        let itemKeyBytes = SecureRandom.bytes(32)
        let itemKey = LockableSecret(bytes: itemKeyBytes)
        let wrappedItemKey = try AEAD.seal(
            plaintext: itemKeyBytes,
            key: masterKey,
            aad: aadForItemKey(secretId: secretId)
        )

        var secret = SecretRecord(
            id: secretId,
            vaultId: vault.id,
            kind: draft.kind,
            brandPreset: draft.brandPreset,
            internalName: draft.internalName,
            title: draft.title,
            wrappedItemKey: wrappedItemKey,
            currentVersionId: versionId,
            createdAt: now,
            updatedAt: now
        )
        secret.tags = draft.tags

        let version = SecretVersionRecord(
            id: versionId,
            secretId: secretId,
            versionNumber: 1,
            reason: .create,
            diffSummary: "Created with \(draft.fields.count) fields",
            createdAt: now,
            createdBy: .ui
        )

        let fieldRecords = try draft.fields.enumerated().map { (idx, draftField) -> SecretFieldRecord in
            try buildFieldRecord(
                draftField: draftField,
                secretId: secretId,
                versionId: versionId,
                itemKey: itemKey,
                sortOrder: idx
            )
        }

        let notesRecord: SecretNotesRecord? = try draft.notes.flatMap { notes -> SecretNotesRecord in
            let cipher = try AEAD.seal(
                plaintext: Data(notes.utf8),
                key: itemKey,
                aad: aadForNotes(secretId: secretId, versionId: versionId)
            )
            return SecretNotesRecord(secretId: secretId, versionId: versionId, ciphertext: cipher)
        }

        try database.write { db in
            do {
                try secret.insert(db)
            } catch {
                if let dbErr = error as? DatabaseError, dbErr.resultCode == .SQLITE_CONSTRAINT {
                    throw SecretsStoreError.duplicateInternalName(draft.internalName)
                }
                throw error
            }
            try version.insert(db)
            for record in fieldRecords {
                try record.insert(db)
            }
            if let notes = notesRecord {
                try notes.insert(db)
            }
        }

        try audit?.append(NewAuditEvent(
            kind: .adminCreate,
            source: .admin,
            secretId: secret.id,
            vaultId: vault.id,
            versionId: versionId,
            success: true,
            payload: AuditEventPayload(
                notes: "Created with \(draft.fields.count) field\(draft.fields.count == 1 ? "" : "s")",
                secretInternalNameFrozen: draft.internalName,
                secretKindFrozen: draft.kind
            )
        ))

        return secret
    }

    public func listSecrets(
        in vault: VaultRecord? = nil,
        includeTrashed: Bool = false,
        includeArchived: Bool = false
    ) throws -> [SecretRecord] {
        try database.read { db in
            var query: QueryInterfaceRequest<SecretRecord> = SecretRecord.all()
            if let vault {
                query = query.filter(Column("vaultId") == vault.id.uuidString.uppercased())
            }
            if !includeTrashed {
                query = query.filter(Column("trashedAt") == nil)
            }
            if !includeArchived {
                query = query.filter(Column("isArchived") == false)
            }
            return try query
                .order(Column("title").collating(.localizedCaseInsensitiveCompare).asc)
                .fetchAll(db)
        }
    }

    public func fetchSecret(id: EntityID) throws -> SecretRecord? {
        try database.read { db in
            try SecretRecord.fetchOne(db, key: id.uuidString.uppercased())
        }
    }

    public func fetchSecret(byInternalName name: String, accountId: Int64 = 0) throws -> SecretRecord? {
        try database.read { db in
            try SecretRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("internalName") == name)
                .filter(Column("trashedAt") == nil)
                .fetchOne(db)
        }
    }

    public func decryptFieldSilently(_ field: SecretFieldRecord) throws -> String? {
        let revealed = try internalRevealField(field)
        return revealed.value
    }

    public func fetchFields(forSecret secretId: EntityID, version versionId: EntityID) throws -> [SecretFieldRecord] {
        try database.read { db in
            try SecretFieldRecord
                .filter(Column("secretId") == secretId.uuidString.uppercased())
                .filter(Column("versionId") == versionId.uuidString.uppercased())
                .order(Column("sortOrder").asc)
                .fetchAll(db)
        }
    }

    public func revealField(_ field: SecretFieldRecord, purpose: FieldAccessPurpose = .reveal) throws -> RevealedField {
        let revealed = try internalRevealField(field)
        if let secretSnapshot = try fetchSecret(id: field.secretId) {
            try audit?.append(NewAuditEvent(
                kind: purpose == .copy ? .uiCopy : .uiReveal,
                source: .ui,
                secretId: secretSnapshot.id,
                vaultId: secretSnapshot.vaultId,
                versionId: secretSnapshot.currentVersionId,
                success: true,
                payload: AuditEventPayload(
                    notes: "Field '\(field.fieldName)' \(purpose == .copy ? "copied" : "revealed")",
                    secretInternalNameFrozen: secretSnapshot.internalName,
                    secretKindFrozen: secretSnapshot.kind
                )
            ))
        }
        return revealed
    }

    private func internalRevealField(_ field: SecretFieldRecord) throws -> RevealedField {
        if !field.isSecret {
            return RevealedField(
                name: field.fieldName,
                fieldKind: field.fieldKind,
                placement: field.placement,
                value: field.publicValue,
                otpPeriod: field.otpPeriod,
                otpDigits: field.otpDigits,
                otpAlgorithm: field.otpAlgorithm
            )
        }
        guard let secret = try fetchSecret(id: field.secretId) else {
            throw SecretsStoreError.secretNotFound
        }
        guard let cipher = field.valueCiphertext else {
            return RevealedField(
                name: field.fieldName,
                fieldKind: field.fieldKind,
                placement: field.placement,
                value: nil,
                otpPeriod: field.otpPeriod,
                otpDigits: field.otpDigits,
                otpAlgorithm: field.otpAlgorithm
            )
        }
        let itemKey = try unwrapItemKey(for: secret)
        let plain: Data
        do {
            plain = try AEAD.open(
                blob: cipher,
                key: itemKey,
                aad: aadForField(secretId: secret.id, fieldName: field.fieldName)
            )
        } catch {
            throw SecretsStoreError.lockedItemKey
        }
        return RevealedField(
            name: field.fieldName,
            fieldKind: field.fieldKind,
            placement: field.placement,
            value: String(data: plain, encoding: .utf8),
            otpPeriod: field.otpPeriod,
            otpDigits: field.otpDigits,
            otpAlgorithm: field.otpAlgorithm
        )
    }

    public func revealNotes(secret: SecretRecord, emitAudit: Bool = false) throws -> String? {
        let notes = try database.read { db -> SecretNotesRecord? in
            try SecretNotesRecord
                .filter(Column("secretId") == secret.id.uuidString.uppercased())
                .filter(Column("versionId") == secret.currentVersionId.uuidString.uppercased())
                .fetchOne(db)
        }
        guard let cipher = notes?.ciphertext else { return nil }
        let itemKey = try unwrapItemKey(for: secret)
        let plain = try AEAD.open(
            blob: cipher,
            key: itemKey,
            aad: aadForNotes(secretId: secret.id, versionId: secret.currentVersionId)
        )
        if emitAudit {
            try audit?.append(NewAuditEvent(
                kind: .uiView,
                source: .ui,
                secretId: secret.id,
                vaultId: secret.vaultId,
                versionId: secret.currentVersionId,
                success: true,
                payload: AuditEventPayload(
                    notes: "Notes viewed",
                    secretInternalNameFrozen: secret.internalName,
                    secretKindFrozen: secret.kind
                )
            ))
        }
        return String(data: plain, encoding: .utf8)
    }

    @discardableResult
    public func trashSecret(id: EntityID) throws -> SecretRecord {
        let updated = try database.write { db -> SecretRecord in
            guard var secret = try SecretRecord.fetchOne(db, key: id.uuidString.uppercased()) else {
                throw SecretsStoreError.secretNotFound
            }
            secret.trashedAt = Clock.now()
            secret.updatedAt = Clock.now()
            try secret.update(db)
            return secret
        }
        try audit?.append(NewAuditEvent(
            kind: .adminTrash,
            source: .admin,
            secretId: updated.id,
            vaultId: updated.vaultId,
            success: true,
            payload: AuditEventPayload(
                notes: "Moved to trash",
                secretInternalNameFrozen: updated.internalName,
                secretKindFrozen: updated.kind
            )
        ))
        return updated
    }

    @discardableResult
    public func restoreSecret(id: EntityID) throws -> SecretRecord {
        let updated = try database.write { db -> SecretRecord in
            guard var secret = try SecretRecord.fetchOne(db, key: id.uuidString.uppercased()) else {
                throw SecretsStoreError.secretNotFound
            }
            secret.trashedAt = nil
            secret.updatedAt = Clock.now()
            try secret.update(db)
            return secret
        }
        try audit?.append(NewAuditEvent(
            kind: .adminRestoreVersion,
            source: .admin,
            secretId: updated.id,
            vaultId: updated.vaultId,
            success: true,
            payload: AuditEventPayload(
                notes: "Restored from trash",
                secretInternalNameFrozen: updated.internalName,
                secretKindFrozen: updated.kind
            )
        ))
        return updated
    }

    @discardableResult
    public func updateGovernance(
        secretId: EntityID,
        to newGovernance: Governance
    ) throws -> SecretRecord {
        let updated = try database.write { db -> SecretRecord in
            guard var secret = try SecretRecord.fetchOne(db, key: secretId.uuidString.uppercased()) else {
                throw SecretsStoreError.secretNotFound
            }
            secret.governance = newGovernance
            secret.updatedAt = Clock.now()
            try secret.update(db)
            return secret
        }
        try audit?.append(NewAuditEvent(
            kind: .adminToggle,
            source: .ui,
            secretId: updated.id,
            vaultId: updated.vaultId,
            success: true,
            payload: AuditEventPayload(
                notes: "Governance updated",
                secretInternalNameFrozen: updated.internalName,
                secretKindFrozen: updated.kind
            )
        ))
        return updated
    }

    @discardableResult
    public func updateTitle(
        secretId: EntityID,
        title: String,
        readOnly: Bool? = nil,
        archived: Bool? = nil
    ) throws -> SecretRecord {
        let updated = try database.write { db -> SecretRecord in
            guard var secret = try SecretRecord.fetchOne(db, key: secretId.uuidString.uppercased()) else {
                throw SecretsStoreError.secretNotFound
            }
            secret.title = title
            if let readOnly { secret.readOnly = readOnly }
            if let archived { secret.isArchived = archived }
            secret.updatedAt = Clock.now()
            try secret.update(db)
            return secret
        }
        try audit?.append(NewAuditEvent(
            kind: .adminEdit,
            source: .ui,
            secretId: updated.id,
            vaultId: updated.vaultId,
            success: true,
            payload: AuditEventPayload(
                notes: "Title / flags updated",
                secretInternalNameFrozen: updated.internalName,
                secretKindFrozen: updated.kind
            )
        ))
        return updated
    }

    public func bumpUseCount(id: EntityID) throws {
        try database.write { db in
            guard var secret = try SecretRecord.fetchOne(db, key: id.uuidString.uppercased()) else {
                throw SecretsStoreError.secretNotFound
            }
            secret.useCount += 1
            secret.lastUsedAt = Clock.now()
            try secret.update(db)
        }
    }

    @discardableResult
    public func setCompromised(id: EntityID, flag: Bool, reason: String? = nil) throws -> SecretRecord {
        let updated = try database.write { db -> SecretRecord in
            guard var secret = try SecretRecord.fetchOne(db, key: id.uuidString.uppercased()) else {
                throw SecretsStoreError.secretNotFound
            }
            secret.isCompromised = flag
            secret.isLocked = flag
            secret.updatedAt = Clock.now()
            try secret.update(db)
            return secret
        }
        try audit?.append(NewAuditEvent(
            kind: .adminCompromise,
            source: .admin,
            secretId: updated.id,
            vaultId: updated.vaultId,
            success: true,
            payload: AuditEventPayload(
                notes: flag ? "Marked as compromised\(reason.map { ": \($0)" } ?? "")" : "Compromise flag cleared",
                secretInternalNameFrozen: updated.internalName,
                secretKindFrozen: updated.kind
            )
        ))
        return updated
    }

    @discardableResult
    public func purgeTrashed(olderThan threshold: Timestamp) throws -> Int {
        let toPurge = try database.read { db in
            try SecretRecord
                .filter(Column("trashedAt") != nil)
                .filter(Column("trashedAt") < threshold)
                .fetchAll(db)
        }
        guard !toPurge.isEmpty else { return 0 }
        try database.write { db in
            for secret in toPurge {
                try SecretRecord.deleteOne(db, key: secret.id.uuidString.uppercased())
            }
        }
        for secret in toPurge {
            try audit?.append(NewAuditEvent(
                kind: .adminPurge,
                source: .system,
                secretId: nil,
                vaultId: secret.vaultId,
                success: true,
                payload: AuditEventPayload(
                    notes: "Auto-purged from trash",
                    secretInternalNameFrozen: secret.internalName,
                    secretKindFrozen: secret.kind
                )
            ))
        }
        return toPurge.count
    }

    // MARK: Fixture seeding (DEV ONLY)
    //
    // The methods below let dummy-mode fixtures backdate timestamps and
    // counters that the regular API derives from `Clock.now()`. They are
    // gated by the `CLAWIX_FIXTURE_SEEDING=1` environment variable, set
    // exclusively by `dummy.sh` when seeding from `CLAWIX_SECRETS_FIXTURE`.
    // In production builds (where the env var is never set) every call
    // is a no-op, so the production write path is unchanged.

    public func _fixtureTouch(
        secretId: EntityID,
        createdAt: Timestamp? = nil,
        updatedAt: Timestamp? = nil,
        lastUsedAt: Timestamp? = nil,
        lastRotatedAt: Timestamp? = nil,
        useCount: Int? = nil,
        trashedAt: Timestamp? = nil,
        readOnly: Bool? = nil,
        isLocked: Bool? = nil
    ) throws {
        guard ProcessInfo.processInfo.environment["CLAWIX_FIXTURE_SEEDING"] == "1" else { return }
        try database.write { db in
            guard var secret = try SecretRecord.fetchOne(db, key: secretId.uuidString.uppercased()) else {
                throw SecretsStoreError.secretNotFound
            }
            if let createdAt { secret.createdAt = createdAt }
            if let updatedAt { secret.updatedAt = updatedAt }
            if let lastUsedAt { secret.lastUsedAt = lastUsedAt }
            if let lastRotatedAt { secret.lastRotatedAt = lastRotatedAt }
            if let useCount { secret.useCount = useCount }
            if let trashedAt { secret.trashedAt = trashedAt }
            if let readOnly { secret.readOnly = readOnly }
            if let isLocked { secret.isLocked = isLocked }
            try secret.update(db)
        }
    }

    // MARK: Helpers

    private func buildFieldRecord(
        draftField: DraftField,
        secretId: EntityID,
        versionId: EntityID,
        itemKey: LockableSecret,
        sortOrder: Int
    ) throws -> SecretFieldRecord {
        var cipher: Data?
        if draftField.isSecret, let value = draftField.secretValue {
            cipher = try AEAD.seal(
                plaintext: Data(value.utf8),
                key: itemKey,
                aad: aadForField(secretId: secretId, fieldName: draftField.name)
            )
        }
        return SecretFieldRecord(
            secretId: secretId,
            versionId: versionId,
            fieldName: draftField.name,
            fieldKind: draftField.fieldKind,
            placement: draftField.placement,
            isSecret: draftField.isSecret,
            isConcealed: draftField.isConcealed,
            publicValue: draftField.isSecret ? nil : draftField.publicValue,
            valueCiphertext: cipher,
            otpPeriod: draftField.otpPeriod,
            otpDigits: draftField.otpDigits,
            otpAlgorithm: draftField.otpAlgorithm,
            sortOrder: sortOrder
        )
    }

    private func unwrapItemKey(for secret: SecretRecord) throws -> LockableSecret {
        let bytes: Data
        do {
            bytes = try AEAD.open(
                blob: secret.wrappedItemKey,
                key: masterKey,
                aad: aadForItemKey(secretId: secret.id)
            )
        } catch {
            throw SecretsStoreError.lockedItemKey
        }
        return LockableSecret(bytes: bytes)
    }

    private func aadForItemKey(secretId: EntityID) -> Data {
        Data((secretId.uuidString.uppercased() + "|item-key").utf8)
    }

    private func aadForField(secretId: EntityID, fieldName: String) -> Data {
        Data((secretId.uuidString.uppercased() + "|field|" + fieldName).utf8)
    }

    private func aadForNotes(secretId: EntityID, versionId: EntityID) -> Data {
        Data((secretId.uuidString.uppercased() + "|notes|" + versionId.uuidString.uppercased()).utf8)
    }
}
