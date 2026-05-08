import XCTest
@testable import SecretsCrypto

final class LockableSecretTests: XCTestCase {

    func testCountAndAccess() {
        let payload = Data([0x01, 0x02, 0x03, 0x04])
        let s = LockableSecret(bytes: payload)
        XCTAssertEqual(s.count, 4)
        s.withBytes { buf in
            XCTAssertEqual(buf.count, 4)
            XCTAssertEqual(Array(buf), [0x01, 0x02, 0x03, 0x04])
        }
    }

    func testZeroOverwritesBuffer() {
        let s = LockableSecret(bytes: Data(repeating: 0xAB, count: 32))
        s.zero()
        s.withBytes { buf in
            XCTAssertEqual(buf.count, 32)
            for byte in buf {
                XCTAssertEqual(byte, 0)
            }
        }
    }

    func testEmptySecretIsAllowed() {
        let s = LockableSecret(bytes: Data())
        XCTAssertEqual(s.count, 0)
        s.withBytes { buf in
            XCTAssertEqual(buf.count, 0)
        }
        s.zero()
    }

    func testRandomFactoryProducesRequestedLength() {
        let s = LockableSecret.random(byteCount: 64)
        XCTAssertEqual(s.count, 64)
        s.withBytes { buf in
            XCTAssertEqual(buf.count, 64)
        }
    }
}
