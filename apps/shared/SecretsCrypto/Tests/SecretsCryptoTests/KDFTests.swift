import XCTest
@testable import SecretsCrypto

final class KDFTests: XCTestCase {

    private func bytes(_ s: LockableSecret) -> Data {
        s.withBytes { Data($0) }
    }

    func testDeterministic() {
        let master = LockableSecret(bytes: Data(repeating: 0x42, count: 32))
        let info = Data("audit-mac-key".utf8)
        let a = KDF.deriveSubkey(from: master, info: info, length: 32)
        let b = KDF.deriveSubkey(from: master, info: info, length: 32)
        XCTAssertEqual(bytes(a), bytes(b))
        XCTAssertEqual(a.count, 32)
    }

    func testDifferentInfosProduceDifferentKeys() {
        let master = LockableSecret(bytes: Data(repeating: 0x42, count: 32))
        let a = KDF.deriveSubkey(from: master, info: Data("a".utf8))
        let b = KDF.deriveSubkey(from: master, info: Data("b".utf8))
        XCTAssertNotEqual(bytes(a), bytes(b))
    }

    func testDifferentMastersProduceDifferentKeys() {
        let m1 = LockableSecret(bytes: Data(repeating: 0x01, count: 32))
        let m2 = LockableSecret(bytes: Data(repeating: 0x02, count: 32))
        let info = Data("subkey".utf8)
        XCTAssertNotEqual(bytes(KDF.deriveSubkey(from: m1, info: info)),
                          bytes(KDF.deriveSubkey(from: m2, info: info)))
    }

    func testLengthHonored() {
        let master = LockableSecret(bytes: Data(repeating: 0x42, count: 32))
        for length in [16, 32, 48, 64] {
            let k = KDF.deriveSubkey(from: master, info: Data("x".utf8), length: length)
            XCTAssertEqual(k.count, length)
        }
    }
}
