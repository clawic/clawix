import XCTest
@testable import SecretsCrypto

final class VerifierTests: XCTestCase {

    func testComputeIsDeterministic() {
        let key = LockableSecret(bytes: Data(repeating: 0x42, count: 32))
        let a = Verifier.compute(masterKey: key)
        let b = Verifier.compute(masterKey: key)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, Verifier.length)
    }

    func testDifferentKeysDifferVerifier() {
        let k1 = LockableSecret(bytes: Data(repeating: 0xAA, count: 32))
        let k2 = LockableSecret(bytes: Data(repeating: 0xBB, count: 32))
        XCTAssertNotEqual(Verifier.compute(masterKey: k1), Verifier.compute(masterKey: k2))
    }

    func testMatchesPositive() {
        let key = LockableSecret.random(byteCount: 32)
        let v = Verifier.compute(masterKey: key)
        XCTAssertTrue(Verifier.matches(v, expected: v))
    }

    func testMatchesNegativeOneByteFlipped() {
        let key = LockableSecret.random(byteCount: 32)
        var v = Verifier.compute(masterKey: key)
        v[v.startIndex] ^= 0x01
        XCTAssertFalse(Verifier.matches(v, expected: Verifier.compute(masterKey: key)))
    }

    func testMatchesNegativeDifferentLength() {
        let v = Verifier.compute(masterKey: LockableSecret.random(byteCount: 32))
        XCTAssertFalse(Verifier.matches(v, expected: v.dropLast()))
        XCTAssertFalse(Verifier.matches(Data(), expected: v))
    }
}
