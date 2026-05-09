import XCTest
@testable import SecretsCrypto

final class AEADTests: XCTestCase {

    private func makeKey() -> LockableSecret {
        LockableSecret.random(byteCount: 32)
    }

    func testRoundTrip() throws {
        let key = makeKey()
        let plaintext = Data("hello, vault".utf8)
        let blob = try AEAD.seal(plaintext: plaintext, key: key)
        let opened = try AEAD.open(blob: blob, key: key)
        XCTAssertEqual(opened, plaintext)
    }

    func testRoundTripWithAAD() throws {
        let key = makeKey()
        let plaintext = Data("payload".utf8)
        let aad = Data("secret_id=abc;field=token".utf8)
        let blob = try AEAD.seal(plaintext: plaintext, key: key, aad: aad)
        let opened = try AEAD.open(blob: blob, key: key, aad: aad)
        XCTAssertEqual(opened, plaintext)
    }

    func testWrongKeyFails() throws {
        let key1 = makeKey()
        let key2 = makeKey()
        let blob = try AEAD.seal(plaintext: Data("payload".utf8), key: key1)
        XCTAssertThrowsError(try AEAD.open(blob: blob, key: key2)) { error in
            XCTAssertEqual(error as? AEAD.Error, .decryptionFailed)
        }
    }

    func testWrongAADFails() throws {
        let key = makeKey()
        let blob = try AEAD.seal(plaintext: Data("payload".utf8), key: key, aad: Data("A".utf8))
        XCTAssertThrowsError(try AEAD.open(blob: blob, key: key, aad: Data("B".utf8))) { error in
            XCTAssertEqual(error as? AEAD.Error, .decryptionFailed)
        }
    }

    func testTamperedBlobFails() throws {
        let key = makeKey()
        var blob = try AEAD.seal(plaintext: Data("payload".utf8), key: key)
        let flipIndex = blob.startIndex + AEAD.versionSize + AEAD.nonceSize + 1
        blob[flipIndex] ^= 0x80
        XCTAssertThrowsError(try AEAD.open(blob: blob, key: key)) { error in
            XCTAssertEqual(error as? AEAD.Error, .decryptionFailed)
        }
    }

    func testUnsupportedVersionFails() throws {
        let key = makeKey()
        var blob = try AEAD.seal(plaintext: Data("payload".utf8), key: key)
        blob[blob.startIndex] = 0xFF
        XCTAssertThrowsError(try AEAD.open(blob: blob, key: key)) { error in
            XCTAssertEqual(error as? AEAD.Error, .unsupportedVersion(0xFF))
        }
    }

    func testMalformedShortBlobFails() {
        let key = makeKey()
        let blob = Data([CryptoVersion.v1, 0x00, 0x01])
        XCTAssertThrowsError(try AEAD.open(blob: blob, key: key)) { error in
            XCTAssertEqual(error as? AEAD.Error, .malformedBlob)
        }
    }

    func testNonceVariesPerSeal() throws {
        let key = makeKey()
        let plaintext = Data("static payload".utf8)
        let a = try AEAD.seal(plaintext: plaintext, key: key)
        let b = try AEAD.seal(plaintext: plaintext, key: key)
        XCTAssertNotEqual(a, b, "nonce must be random per seal")
        XCTAssertEqual(a.count, b.count)
    }

    func testInvalidKeyLength() {
        let badKey = LockableSecret(bytes: Data(repeating: 0x01, count: 16))
        XCTAssertThrowsError(try AEAD.seal(plaintext: Data(), key: badKey)) { error in
            XCTAssertEqual(error as? AEAD.Error, .invalidKey)
        }
    }

    func testVersionByteHelper() throws {
        let key = makeKey()
        let blob = try AEAD.seal(plaintext: Data("p".utf8), key: key)
        XCTAssertEqual(AEAD.versionByte(of: blob), CryptoVersion.v1)
        XCTAssertNil(AEAD.versionByte(of: Data()))
    }
}
