import XCTest
@testable import SecretsCrypto
import ClawixArgon2

final class CalibrationTests: XCTestCase {

    func testCalibratedParamsAreInRange() {
        let params = Calibration.calibrate(targetMs: 50)
        XCTAssertGreaterThanOrEqual(params.memoryKB, Calibration.minMemoryKB)
        XCTAssertLessThanOrEqual(params.memoryKB, Calibration.maxMemoryKB)
        XCTAssertGreaterThan(params.iterations, 0)
        XCTAssertGreaterThan(params.parallelism, 0)
    }

    func testDeriveMasterKeyReturnsExpectedLength() throws {
        let params = Argon2.Params(memoryKB: 1024, iterations: 2, parallelism: 1)
        let key = try Calibration.deriveMasterKey(
            password: "hunter2",
            salt: Data(repeating: 0x10, count: 16),
            params: params,
            outputLength: 32
        )
        XCTAssertEqual(key.count, 32)
    }

    func testDeriveMasterKeyDeterministic() throws {
        let params = Argon2.Params(memoryKB: 1024, iterations: 2, parallelism: 1)
        let salt = Data(repeating: 0x20, count: 16)
        let a = try Calibration.deriveMasterKey(password: "abc", salt: salt, params: params)
        let b = try Calibration.deriveMasterKey(password: "abc", salt: salt, params: params)
        a.withBytes { ab in
            b.withBytes { bb in
                XCTAssertEqual(Data(ab), Data(bb))
            }
        }
    }
}
