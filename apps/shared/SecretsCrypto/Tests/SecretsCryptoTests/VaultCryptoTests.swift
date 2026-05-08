import XCTest
import ClawixArgon2
@testable import SecretsCrypto

final class VaultCryptoTests: XCTestCase {

    private let smallParams = Argon2.Params(memoryKB: 1024, iterations: 2, parallelism: 1)

    private func keyBytes(_ k: LockableSecret) -> Data {
        k.withBytes { Data($0) }
    }

    func testSetUpProducesUsableBootstrap() throws {
        let bootstrap = try VaultCrypto.setUp(
            masterPassword: "hunter2",
            kdfParams: smallParams,
            deviceId: "macbook-1",
            appVersion: "0.0.0"
        )
        XCTAssertEqual(bootstrap.recoveryPhrase.count, 24)
        XCTAssertEqual(bootstrap.masterKey.count, 32)
        XCTAssertEqual(bootstrap.auditMacKey.count, 32)
        XCTAssertEqual(bootstrap.meta.kdfSalt.count, 32)
        XCTAssertEqual(bootstrap.meta.recoverySalt.count, 32)
        XCTAssertEqual(bootstrap.meta.verifier.count, Verifier.length)
        XCTAssertGreaterThan(bootstrap.meta.recoveryWrap.count, AEAD.overhead)
        XCTAssertGreaterThan(bootstrap.meta.auditMacKeyWrap.count, AEAD.overhead)
        XCTAssertEqual(bootstrap.meta.auditChainGenesis.count, 32)
        XCTAssertEqual(bootstrap.meta.deviceId, "macbook-1")
        XCTAssertEqual(bootstrap.meta.appVersionAtSetup, "0.0.0")
    }

    func testUnlockWithCorrectPassword() throws {
        let bootstrap = try VaultCrypto.setUp(masterPassword: "hunter2", kdfParams: smallParams)
        let result = try VaultCrypto.unlock(masterPassword: "hunter2", meta: bootstrap.meta)
        XCTAssertEqual(keyBytes(result.masterKey), keyBytes(bootstrap.masterKey))
        XCTAssertEqual(keyBytes(result.auditMacKey), keyBytes(bootstrap.auditMacKey))
    }

    func testUnlockWithWrongPasswordThrows() throws {
        let bootstrap = try VaultCrypto.setUp(masterPassword: "hunter2", kdfParams: smallParams)
        XCTAssertThrowsError(try VaultCrypto.unlock(masterPassword: "wrong", meta: bootstrap.meta)) { err in
            XCTAssertEqual(err as? VaultCryptoError, .verifierMismatch)
        }
    }

    func testRecoverWithCorrectPhrase() throws {
        let bootstrap = try VaultCrypto.setUp(masterPassword: "hunter2", kdfParams: smallParams)
        let result = try VaultCrypto.recover(recoveryPhrase: bootstrap.recoveryPhrase, meta: bootstrap.meta)
        XCTAssertEqual(keyBytes(result.masterKey), keyBytes(bootstrap.masterKey))
        XCTAssertEqual(keyBytes(result.auditMacKey), keyBytes(bootstrap.auditMacKey))
    }

    func testRecoverWithCorruptedPhraseThrows() throws {
        let bootstrap = try VaultCrypto.setUp(masterPassword: "hunter2", kdfParams: smallParams)
        var bad = bootstrap.recoveryPhrase
        bad.swapAt(0, 1)
        XCTAssertThrowsError(try VaultCrypto.recover(recoveryPhrase: bad, meta: bootstrap.meta))
    }

    func testRecoverWithDifferentValidPhraseFailsToUnwrap() throws {
        let bootstrap = try VaultCrypto.setUp(masterPassword: "hunter2", kdfParams: smallParams)
        let otherPhrase = RecoveryPhrase.generate()
        XCTAssertNotEqual(otherPhrase, bootstrap.recoveryPhrase)
        XCTAssertThrowsError(try VaultCrypto.recover(recoveryPhrase: otherPhrase, meta: bootstrap.meta)) { err in
            XCTAssertEqual(err as? VaultCryptoError, .unwrapFailed)
        }
    }

    func testChangePasswordPreservesAuditMacKey() throws {
        let bootstrap = try VaultCrypto.setUp(masterPassword: "old-pwd", kdfParams: smallParams)
        let originalAudit = keyBytes(bootstrap.auditMacKey)
        let originalMaster = keyBytes(bootstrap.masterKey)

        let change = try VaultCrypto.changePassword(
            currentMasterKey: bootstrap.masterKey,
            newPassword: "new-pwd",
            currentMeta: bootstrap.meta
        )
        XCTAssertEqual(keyBytes(change.auditMacKey), originalAudit, "audit MAC key must survive password change")
        XCTAssertNotEqual(keyBytes(change.masterKey), originalMaster, "master key must rotate on password change")
        XCTAssertEqual(change.newRecoveryPhrase.count, 24)
        XCTAssertNotEqual(change.newRecoveryPhrase, bootstrap.recoveryPhrase)

        let unlocked = try VaultCrypto.unlock(masterPassword: "new-pwd", meta: change.meta)
        XCTAssertEqual(keyBytes(unlocked.masterKey), keyBytes(change.masterKey))
        XCTAssertEqual(keyBytes(unlocked.auditMacKey), originalAudit)

        XCTAssertThrowsError(try VaultCrypto.unlock(masterPassword: "old-pwd", meta: change.meta)) { err in
            XCTAssertEqual(err as? VaultCryptoError, .verifierMismatch)
        }

        XCTAssertThrowsError(try VaultCrypto.recover(recoveryPhrase: bootstrap.recoveryPhrase, meta: change.meta)) { err in
            XCTAssertEqual(err as? VaultCryptoError, .unwrapFailed)
        }

        let recovered = try VaultCrypto.recover(recoveryPhrase: change.newRecoveryPhrase, meta: change.meta)
        XCTAssertEqual(keyBytes(recovered.masterKey), keyBytes(change.masterKey))
        XCTAssertEqual(keyBytes(recovered.auditMacKey), originalAudit)
    }

    func testMetaSnapshotEncodesAndDecodes() throws {
        let bootstrap = try VaultCrypto.setUp(masterPassword: "abc", kdfParams: smallParams)
        let encoded = try JSONEncoder().encode(bootstrap.meta)
        let decoded = try JSONDecoder().decode(VaultMetaSnapshot.self, from: encoded)
        XCTAssertEqual(decoded, bootstrap.meta)
    }

    func testUnsupportedFormatRejected() throws {
        let bootstrap = try VaultCrypto.setUp(masterPassword: "abc", kdfParams: smallParams)
        var meta = bootstrap.meta
        meta.cryptoVersion = 0xFF
        XCTAssertThrowsError(try VaultCrypto.unlock(masterPassword: "abc", meta: meta)) { err in
            XCTAssertEqual(err as? VaultCryptoError, .unsupportedFormat(0xFF))
        }
    }
}
