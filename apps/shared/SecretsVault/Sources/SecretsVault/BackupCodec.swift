import Foundation
import ClawixArgon2
import SecretsCrypto
import SecretsModels

/// Self-contained encrypted backup of vault contents. The file format is
/// designed to be portable: the helper binary can verify it without a
/// running app, and a future iOS client can decrypt with the same
/// passphrase. The audit chain is NOT included — audit MAC keys are
/// per-install and re-encrypting events under a new key would break their
/// integrity guarantee. Backups carry vaults + secrets + decrypted field
/// values + notes; the recipient re-creates them under a fresh item key.
public struct BackupContents: Codable, Sendable, Hashable {
    public var version: Int
    public var vaults: [BackupVault]
    public var secrets: [BackupSecret]

    public init(version: Int = 1, vaults: [BackupVault], secrets: [BackupSecret]) {
        self.version = version
        self.vaults = vaults
        self.secrets = secrets
    }
}

public struct BackupVault: Codable, Sendable, Hashable {
    public var name: String
    public var icon: String?
    public var color: String?

    public init(name: String, icon: String? = nil, color: String? = nil) {
        self.name = name
        self.icon = icon
        self.color = color
    }
}

public struct BackupSecret: Codable, Sendable, Hashable {
    public var vaultName: String
    public var internalName: String
    public var title: String
    public var kind: String
    public var brandPreset: String?
    public var tags: [String]
    public var notes: String?
    public var fields: [BackupField]

    public init(vaultName: String, internalName: String, title: String, kind: String, brandPreset: String?, tags: [String], notes: String?, fields: [BackupField]) {
        self.vaultName = vaultName
        self.internalName = internalName
        self.title = title
        self.kind = kind
        self.brandPreset = brandPreset
        self.tags = tags
        self.notes = notes
        self.fields = fields
    }
}

public struct BackupField: Codable, Sendable, Hashable {
    public var name: String
    public var fieldKind: String
    public var placement: String
    public var isSecret: Bool
    public var isConcealed: Bool
    public var value: String?
    public var otpPeriod: Int?
    public var otpDigits: Int?
    public var otpAlgorithm: String?

    public init(name: String, fieldKind: String, placement: String, isSecret: Bool, isConcealed: Bool, value: String?, otpPeriod: Int? = nil, otpDigits: Int? = nil, otpAlgorithm: String? = nil) {
        self.name = name
        self.fieldKind = fieldKind
        self.placement = placement
        self.isSecret = isSecret
        self.isConcealed = isConcealed
        self.value = value
        self.otpPeriod = otpPeriod
        self.otpDigits = otpDigits
        self.otpAlgorithm = otpAlgorithm
    }
}

public enum BackupCodecError: Swift.Error, Equatable, CustomStringConvertible {
    case malformed
    case unsupportedVersion(UInt8)
    case decryptionFailed
    case decodeFailed

    public var description: String {
        switch self {
        case .malformed: return "Backup file is malformed"
        case .unsupportedVersion(let v): return "Unsupported backup format version: \(v)"
        case .decryptionFailed: return "Wrong passphrase or tampered backup"
        case .decodeFailed: return "Could not decode backup payload"
        }
    }
}

public enum BackupCodec {

    public static let magic: [UInt8] = Array("CLAWIXBK".utf8)
    public static let formatVersion: UInt8 = 1

    public static func pack(contents: BackupContents, passphrase: String, kdfParams: Argon2.Params = Argon2.Params(memoryKB: 65_536, iterations: 3, parallelism: 1)) throws -> Data {
        let salt = SecureRandom.bytes(32)
        let key = try deriveKey(passphrase: passphrase, salt: salt, params: kdfParams)
        let payload = try JSONEncoder().encode(contents)
        let header = BackupHeader(
            kdfSaltB64: salt.base64EncodedString(),
            kdfMemoryKB: kdfParams.memoryKB,
            kdfIterations: kdfParams.iterations,
            kdfParallelism: kdfParams.parallelism,
            createdAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
        let headerJSON = try JSONEncoder().encode(header)
        let aad = try makeAAD(headerJSON: headerJSON)
        let ciphertext = try AEAD.seal(plaintext: payload, key: key, aad: aad)

        var output = Data()
        output.append(contentsOf: magic)
        output.append(formatVersion)
        var hlen = UInt32(headerJSON.count).bigEndian
        Swift.withUnsafeBytes(of: &hlen) { output.append(contentsOf: $0) }
        output.append(headerJSON)
        output.append(ciphertext)
        return output
    }

    public static func unpack(data: Data, passphrase: String) throws -> BackupContents {
        guard data.count > magic.count + 1 + 4 else { throw BackupCodecError.malformed }
        // magic
        let prefix = data.prefix(magic.count)
        guard Array(prefix) == magic else { throw BackupCodecError.malformed }
        var cursor = data.startIndex.advanced(by: magic.count)
        // version
        let version = data[cursor]
        cursor = data.index(after: cursor)
        guard version == formatVersion else { throw BackupCodecError.unsupportedVersion(version) }
        // header length
        let lenStart = cursor
        let lenEnd = data.index(lenStart, offsetBy: 4)
        guard lenEnd <= data.endIndex else { throw BackupCodecError.malformed }
        let b0 = UInt32(data[lenStart])
        let b1 = UInt32(data[data.index(lenStart, offsetBy: 1)])
        let b2 = UInt32(data[data.index(lenStart, offsetBy: 2)])
        let b3 = UInt32(data[data.index(lenStart, offsetBy: 3)])
        let headerLen = Int((b0 << 24) | (b1 << 16) | (b2 << 8) | b3)
        cursor = lenEnd
        let headerEnd = data.index(cursor, offsetBy: headerLen)
        guard headerEnd <= data.endIndex else { throw BackupCodecError.malformed }
        let headerJSON = data[cursor..<headerEnd]
        cursor = headerEnd
        let ciphertext = data[cursor..<data.endIndex]

        let header: BackupHeader
        do {
            header = try JSONDecoder().decode(BackupHeader.self, from: headerJSON)
        } catch { throw BackupCodecError.malformed }
        guard let salt = Data(base64Encoded: header.kdfSaltB64) else { throw BackupCodecError.malformed }
        let params = Argon2.Params(
            memoryKB: header.kdfMemoryKB,
            iterations: header.kdfIterations,
            parallelism: header.kdfParallelism
        )
        let key = try deriveKey(passphrase: passphrase, salt: salt, params: params)
        let aad = try makeAAD(headerJSON: Data(headerJSON))

        let plain: Data
        do {
            plain = try AEAD.open(blob: Data(ciphertext), key: key, aad: aad)
        } catch {
            throw BackupCodecError.decryptionFailed
        }
        do {
            return try JSONDecoder().decode(BackupContents.self, from: plain)
        } catch {
            throw BackupCodecError.decodeFailed
        }
    }

    public static func verifyMagic(data: Data) -> Bool {
        guard data.count >= magic.count + 1 else { return false }
        return Array(data.prefix(magic.count)) == magic
    }

    private static func deriveKey(passphrase: String, salt: Data, params: Argon2.Params) throws -> LockableSecret {
        try Calibration.deriveMasterKey(password: passphrase, salt: salt, params: params)
    }

    private static func makeAAD(headerJSON: Data) throws -> Data {
        var aad = Data()
        aad.append(contentsOf: magic)
        aad.append(formatVersion)
        aad.append(headerJSON)
        return aad
    }

    private struct BackupHeader: Codable {
        var kdfSaltB64: String
        var kdfMemoryKB: UInt32
        var kdfIterations: UInt32
        var kdfParallelism: UInt32
        var createdAt: Int64
    }
}

public extension SecretsStore {

    /// Build a `BackupContents` snapshot from the live database, decrypting
    /// every field and note so recipients can re-create them under a fresh
    /// item key. Audit log is intentionally excluded.
    func snapshotForBackup() throws -> BackupContents {
        let vaults = try listVaults(includeTrashed: false)
        let secrets = try listSecrets(includeTrashed: false, includeArchived: true)
        let vaultsByID = Dictionary(uniqueKeysWithValues: vaults.map { ($0.id, $0) })
        var backupSecrets: [BackupSecret] = []
        for secret in secrets {
            let vaultName = vaultsByID[secret.vaultId]?.name ?? "Personal"
            let fields = try fetchFields(forSecret: secret.id, version: secret.currentVersionId)
            var backupFields: [BackupField] = []
            for field in fields {
                let value: String?
                if field.isSecret {
                    value = try decryptFieldSilently(field)
                } else {
                    value = field.publicValue
                }
                backupFields.append(BackupField(
                    name: field.fieldName,
                    fieldKind: field.fieldKind.rawValue,
                    placement: field.placement.rawValue,
                    isSecret: field.isSecret,
                    isConcealed: field.isConcealed,
                    value: value,
                    otpPeriod: field.otpPeriod,
                    otpDigits: field.otpDigits,
                    otpAlgorithm: field.otpAlgorithm?.rawValue
                ))
            }
            let notes = try revealNotes(secret: secret, emitAudit: false)
            backupSecrets.append(BackupSecret(
                vaultName: vaultName,
                internalName: secret.internalName,
                title: secret.title,
                kind: secret.kind.rawValue,
                brandPreset: secret.brandPreset,
                tags: secret.tags,
                notes: notes,
                fields: backupFields
            ))
        }
        let backupVaults = vaults.map { BackupVault(name: $0.name, icon: $0.icon, color: $0.color) }
        return BackupContents(vaults: backupVaults, secrets: backupSecrets)
    }

    /// Rebuild the snapshot into the live database. Existing internal names
    /// are skipped (returned as `skipped`); new vaults are created on
    /// demand. The vault keeps its existing per-item key wrapping; values
    /// are re-encrypted under the live master key transparently.
    @discardableResult
    func restoreBackup(_ contents: BackupContents) throws -> (created: Int, skipped: Int) {
        let existingVaults = try listVaults(includeTrashed: true)
        var vaultByName = Dictionary(uniqueKeysWithValues: existingVaults.map { ($0.name, $0) })
        var created = 0
        var skipped = 0
        for v in contents.vaults where vaultByName[v.name] == nil {
            let row = try createVault(name: v.name, icon: v.icon, color: v.color)
            vaultByName[v.name] = row
        }
        let existingSecrets = try listSecrets(includeTrashed: true, includeArchived: true)
        let existingNames = Set(existingSecrets.map { $0.internalName })
        for backupSecret in contents.secrets {
            if existingNames.contains(backupSecret.internalName) {
                skipped += 1
                continue
            }
            let vaultRow = vaultByName[backupSecret.vaultName] ?? vaultByName.values.first
            guard let target = vaultRow else { continue }
            let kind = SecretKind(rawValue: backupSecret.kind) ?? .secureNote
            var draftFields: [DraftField] = []
            for (idx, f) in backupSecret.fields.enumerated() {
                let fieldKind = FieldKind(rawValue: f.fieldKind) ?? .text
                let placement = FieldPlacement(rawValue: f.placement) ?? .none
                draftFields.append(DraftField(
                    name: f.name,
                    fieldKind: fieldKind,
                    placement: placement,
                    isSecret: f.isSecret,
                    isConcealed: f.isConcealed,
                    publicValue: f.isSecret ? nil : f.value,
                    secretValue: f.isSecret ? f.value : nil,
                    otpPeriod: f.otpPeriod,
                    otpDigits: f.otpDigits,
                    otpAlgorithm: f.otpAlgorithm.flatMap { OtpAlgorithm(rawValue: $0) },
                    sortOrder: idx
                ))
            }
            let draft = DraftSecret(
                kind: kind,
                brandPreset: backupSecret.brandPreset,
                internalName: backupSecret.internalName,
                title: backupSecret.title,
                fields: draftFields,
                notes: backupSecret.notes,
                tags: backupSecret.tags
            )
            _ = try createSecret(in: target, draft: draft)
            created += 1
        }
        return (created, skipped)
    }
}
