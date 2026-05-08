import Foundation
import CArgon2

public enum Argon2 {

    public enum Variant: Int, Hashable, Sendable, Codable {
        case d = 0
        case i = 1
        case id = 2
    }

    public struct Params: Equatable, Hashable, Codable, Sendable {
        public var memoryKB: UInt32
        public var iterations: UInt32
        public var parallelism: UInt32

        public init(memoryKB: UInt32 = 65_536, iterations: UInt32 = 3, parallelism: UInt32 = 1) {
            self.memoryKB = memoryKB
            self.iterations = iterations
            self.parallelism = parallelism
        }
    }

    public enum Error: Swift.Error, CustomStringConvertible {
        case invalidParameters
        case argon2(code: Int32)

        public var description: String {
            switch self {
            case .invalidParameters:
                return "Argon2: invalid parameters"
            case .argon2(let code):
                return "Argon2 returned code \(code)"
            }
        }
    }

    public static func deriveKey(
        password: Data,
        salt: Data,
        params: Params,
        outputLength: Int = 32,
        variant: Variant = .id
    ) throws -> Data {
        guard outputLength > 0,
              params.memoryKB > 0,
              params.iterations > 0,
              params.parallelism > 0
        else {
            throw Error.invalidParameters
        }

        var output = Data(count: outputLength)
        let code = output.withUnsafeMutableBytes { (outBuf: UnsafeMutableRawBufferPointer) -> Int32 in
            password.withUnsafeBytes { (pwdBuf: UnsafeRawBufferPointer) -> Int32 in
                salt.withUnsafeBytes { (saltBuf: UnsafeRawBufferPointer) -> Int32 in
                    let outPtr = outBuf.baseAddress!
                    let pwdPtr = pwdBuf.baseAddress
                    let saltPtr = saltBuf.baseAddress
                    switch variant {
                    case .id:
                        return argon2id_hash_raw(
                            params.iterations,
                            params.memoryKB,
                            params.parallelism,
                            pwdPtr, password.count,
                            saltPtr, salt.count,
                            outPtr, outputLength
                        )
                    case .i:
                        return argon2i_hash_raw(
                            params.iterations,
                            params.memoryKB,
                            params.parallelism,
                            pwdPtr, password.count,
                            saltPtr, salt.count,
                            outPtr, outputLength
                        )
                    case .d:
                        return argon2d_hash_raw(
                            params.iterations,
                            params.memoryKB,
                            params.parallelism,
                            pwdPtr, password.count,
                            saltPtr, salt.count,
                            outPtr, outputLength
                        )
                    }
                }
            }
        }

        guard code == ARGON2_OK.rawValue else {
            throw Error.argon2(code: code)
        }
        return output
    }
}
