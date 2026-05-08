import Foundation
import ClawixArgon2

public struct VaultMetaSnapshot: Equatable, Hashable, Codable, Sendable {
    public var kdfSalt: Data
    public var kdfParams: Argon2.Params
    public var verifier: Data
    public var recoverySalt: Data
    public var recoveryParams: Argon2.Params
    public var recoveryWrap: Data
    public var auditMacKeyWrap: Data
    public var auditChainGenesis: Data
    public var formatVersion: UInt8
    public var cryptoVersion: UInt8
    public var schemaVersion: Int
    public var appVersionAtSetup: String
    public var deviceId: String
    public var createdAt: Int64

    public init(
        kdfSalt: Data,
        kdfParams: Argon2.Params,
        verifier: Data,
        recoverySalt: Data,
        recoveryParams: Argon2.Params,
        recoveryWrap: Data,
        auditMacKeyWrap: Data,
        auditChainGenesis: Data,
        formatVersion: UInt8 = CryptoVersion.current,
        cryptoVersion: UInt8 = CryptoVersion.current,
        schemaVersion: Int = 1,
        appVersionAtSetup: String = "",
        deviceId: String = "",
        createdAt: Int64
    ) {
        self.kdfSalt = kdfSalt
        self.kdfParams = kdfParams
        self.verifier = verifier
        self.recoverySalt = recoverySalt
        self.recoveryParams = recoveryParams
        self.recoveryWrap = recoveryWrap
        self.auditMacKeyWrap = auditMacKeyWrap
        self.auditChainGenesis = auditChainGenesis
        self.formatVersion = formatVersion
        self.cryptoVersion = cryptoVersion
        self.schemaVersion = schemaVersion
        self.appVersionAtSetup = appVersionAtSetup
        self.deviceId = deviceId
        self.createdAt = createdAt
    }
}

public struct VaultBootstrap {
    public let masterKey: LockableSecret
    public let auditMacKey: LockableSecret
    public let recoveryPhrase: [String]
    public let meta: VaultMetaSnapshot
}

public struct VaultUnlockResult {
    public let masterKey: LockableSecret
    public let auditMacKey: LockableSecret
}

public struct PasswordChangeResult {
    public let masterKey: LockableSecret
    public let auditMacKey: LockableSecret
    public let newRecoveryPhrase: [String]
    public let meta: VaultMetaSnapshot
}

public enum VaultCryptoError: Swift.Error, Equatable {
    case verifierMismatch
    case unwrapFailed
    case unsupportedFormat(UInt8)
}

public enum VaultCrypto {

    private static let auditMacInfo = Data("clawix-audit-mac-key-v1".utf8)

    public static func setUp(
        masterPassword: String,
        kdfParams: Argon2.Params,
        deviceId: String = "",
        appVersion: String = "",
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) throws -> VaultBootstrap {
        let kdfSalt = SecureRandom.bytes(32)
        let masterKey = try Calibration.deriveMasterKey(
            password: masterPassword,
            salt: kdfSalt,
            params: kdfParams
        )

        let verifier = Verifier.compute(masterKey: masterKey)

        let phrase = RecoveryPhrase.generate()
        let recoverySalt = SecureRandom.bytes(32)
        let recoveryParams = kdfParams
        let recoveryKey = try deriveRecoveryKey(phrase: phrase, salt: recoverySalt, params: recoveryParams)

        let recoveryWrap = try masterKey.withBytes { mb -> Data in
            try AEAD.seal(plaintext: Data(mb), key: recoveryKey)
        }

        let auditMacKeyBytes = SecureRandom.bytes(32)
        let auditMacKey = LockableSecret(bytes: auditMacKeyBytes)
        let auditMacKeyWrap = try AEAD.seal(plaintext: auditMacKeyBytes, key: masterKey)
        let auditChainGenesis = SecureRandom.bytes(32)

        let meta = VaultMetaSnapshot(
            kdfSalt: kdfSalt,
            kdfParams: kdfParams,
            verifier: verifier,
            recoverySalt: recoverySalt,
            recoveryParams: recoveryParams,
            recoveryWrap: recoveryWrap,
            auditMacKeyWrap: auditMacKeyWrap,
            auditChainGenesis: auditChainGenesis,
            appVersionAtSetup: appVersion,
            deviceId: deviceId,
            createdAt: createdAt
        )

        return VaultBootstrap(
            masterKey: masterKey,
            auditMacKey: auditMacKey,
            recoveryPhrase: phrase,
            meta: meta
        )
    }

    public static func unlock(masterPassword: String, meta: VaultMetaSnapshot) throws -> VaultUnlockResult {
        guard CryptoVersion.isSupported(meta.cryptoVersion) else {
            throw VaultCryptoError.unsupportedFormat(meta.cryptoVersion)
        }
        let masterKey = try Calibration.deriveMasterKey(
            password: masterPassword,
            salt: meta.kdfSalt,
            params: meta.kdfParams
        )
        let candidate = Verifier.compute(masterKey: masterKey)
        guard Verifier.matches(candidate, expected: meta.verifier) else {
            throw VaultCryptoError.verifierMismatch
        }
        let auditMacKey = try unwrapAuditMacKey(meta: meta, masterKey: masterKey)
        return VaultUnlockResult(masterKey: masterKey, auditMacKey: auditMacKey)
    }

    public static func recover(recoveryPhrase phrase: [String], meta: VaultMetaSnapshot) throws -> VaultUnlockResult {
        _ = try RecoveryPhrase.decode(phrase)
        let recoveryKey = try deriveRecoveryKey(phrase: phrase, salt: meta.recoverySalt, params: meta.recoveryParams)
        let masterBytes: Data
        do {
            masterBytes = try AEAD.open(blob: meta.recoveryWrap, key: recoveryKey)
        } catch {
            throw VaultCryptoError.unwrapFailed
        }
        let masterKey = LockableSecret(bytes: masterBytes)
        let auditMacKey = try unwrapAuditMacKey(meta: meta, masterKey: masterKey)
        return VaultUnlockResult(masterKey: masterKey, auditMacKey: auditMacKey)
    }

    public static func changePassword(
        currentMasterKey: LockableSecret,
        newPassword: String,
        currentMeta: VaultMetaSnapshot
    ) throws -> PasswordChangeResult {
        let auditMacKey = try unwrapAuditMacKey(meta: currentMeta, masterKey: currentMasterKey)

        let newKdfSalt = SecureRandom.bytes(32)
        let newMasterKey = try Calibration.deriveMasterKey(
            password: newPassword,
            salt: newKdfSalt,
            params: currentMeta.kdfParams
        )
        let newVerifier = Verifier.compute(masterKey: newMasterKey)

        let newPhrase = RecoveryPhrase.generate()
        let newRecoverySalt = SecureRandom.bytes(32)
        let newRecoveryKey = try deriveRecoveryKey(phrase: newPhrase, salt: newRecoverySalt, params: currentMeta.recoveryParams)

        let newRecoveryWrap = try newMasterKey.withBytes { mb -> Data in
            try AEAD.seal(plaintext: Data(mb), key: newRecoveryKey)
        }
        let newAuditMacKeyWrap = try auditMacKey.withBytes { ab -> Data in
            try AEAD.seal(plaintext: Data(ab), key: newMasterKey)
        }

        let newMeta = VaultMetaSnapshot(
            kdfSalt: newKdfSalt,
            kdfParams: currentMeta.kdfParams,
            verifier: newVerifier,
            recoverySalt: newRecoverySalt,
            recoveryParams: currentMeta.recoveryParams,
            recoveryWrap: newRecoveryWrap,
            auditMacKeyWrap: newAuditMacKeyWrap,
            auditChainGenesis: currentMeta.auditChainGenesis,
            formatVersion: currentMeta.formatVersion,
            cryptoVersion: currentMeta.cryptoVersion,
            schemaVersion: currentMeta.schemaVersion,
            appVersionAtSetup: currentMeta.appVersionAtSetup,
            deviceId: currentMeta.deviceId,
            createdAt: currentMeta.createdAt
        )

        return PasswordChangeResult(
            masterKey: newMasterKey,
            auditMacKey: auditMacKey,
            newRecoveryPhrase: newPhrase,
            meta: newMeta
        )
    }

    private static func deriveRecoveryKey(phrase: [String], salt: Data, params: Argon2.Params) throws -> LockableSecret {
        let canonical = phrase.map { $0.lowercased() }.joined(separator: " ")
        return try Calibration.deriveMasterKey(password: canonical, salt: salt, params: params)
    }

    private static func unwrapAuditMacKey(meta: VaultMetaSnapshot, masterKey: LockableSecret) throws -> LockableSecret {
        let bytes: Data
        do {
            bytes = try AEAD.open(blob: meta.auditMacKeyWrap, key: masterKey)
        } catch {
            throw VaultCryptoError.unwrapFailed
        }
        return LockableSecret(bytes: bytes)
    }
}
