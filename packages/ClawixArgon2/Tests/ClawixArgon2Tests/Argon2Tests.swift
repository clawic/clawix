import XCTest
@testable import ClawixArgon2

final class Argon2Tests: XCTestCase {

    private let smallParams = Argon2.Params(memoryKB: 1024, iterations: 2, parallelism: 1)

    func testDeriveKeyIsDeterministic() throws {
        let pwd = Data("correct horse battery staple".utf8)
        let salt = Data(repeating: 0xAB, count: 16)

        let a = try Argon2.deriveKey(password: pwd, salt: salt, params: smallParams, outputLength: 32, variant: .id)
        let b = try Argon2.deriveKey(password: pwd, salt: salt, params: smallParams, outputLength: 32, variant: .id)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 32)
    }

    func testDifferentPasswordsProduceDifferentKeys() throws {
        let salt = Data(repeating: 0xAB, count: 16)
        let a = try Argon2.deriveKey(password: Data("alpha".utf8), salt: salt, params: smallParams)
        let b = try Argon2.deriveKey(password: Data("bravo".utf8), salt: salt, params: smallParams)
        XCTAssertNotEqual(a, b)
    }

    func testDifferentSaltsProduceDifferentKeys() throws {
        let pwd = Data("hunter2".utf8)
        let a = try Argon2.deriveKey(password: pwd, salt: Data(repeating: 0x01, count: 16), params: smallParams)
        let b = try Argon2.deriveKey(password: pwd, salt: Data(repeating: 0x02, count: 16), params: smallParams)
        XCTAssertNotEqual(a, b)
    }

    func testOutputLengthIsHonored() throws {
        let pwd = Data("password".utf8)
        let salt = Data(repeating: 0x55, count: 16)
        let lengths: [Int] = [16, 32, 48, 64, 128]
        for length in lengths {
            let key = try Argon2.deriveKey(password: pwd, salt: salt, params: smallParams, outputLength: length, variant: .id)
            XCTAssertEqual(key.count, length)
        }
    }

    func testVariantsProduceDifferentKeys() throws {
        let pwd = Data("password".utf8)
        let salt = Data(repeating: 0x77, count: 16)
        let id = try Argon2.deriveKey(password: pwd, salt: salt, params: smallParams, variant: .id)
        let i = try Argon2.deriveKey(password: pwd, salt: salt, params: smallParams, variant: .i)
        let d = try Argon2.deriveKey(password: pwd, salt: salt, params: smallParams, variant: .d)
        XCTAssertNotEqual(id, i)
        XCTAssertNotEqual(id, d)
        XCTAssertNotEqual(i, d)
    }

    func testInvalidParamsThrow() {
        let pwd = Data("password".utf8)
        let salt = Data(repeating: 0xFF, count: 16)
        let bad = Argon2.Params(memoryKB: 0, iterations: 0, parallelism: 0)
        XCTAssertThrowsError(try Argon2.deriveKey(password: pwd, salt: salt, params: bad)) { error in
            guard case Argon2.Error.invalidParameters = error else {
                XCTFail("expected invalidParameters, got \(error)")
                return
            }
        }
    }

    func testDefaultParamsFitInMemoryAndProduceKey() throws {
        let pwd = Data("longer password with spaces and 1234567890".utf8)
        let salt = Data(repeating: 0x9C, count: 32)
        let params = Argon2.Params(memoryKB: 8 * 1024, iterations: 2, parallelism: 1)
        let key = try Argon2.deriveKey(password: pwd, salt: salt, params: params, outputLength: 32, variant: .id)
        XCTAssertEqual(key.count, 32)
    }
}
