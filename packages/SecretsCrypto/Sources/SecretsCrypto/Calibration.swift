import Foundation
import ClawixArgon2

public enum Calibration {

    public static let defaultTargetMs: UInt64 = 250
    public static let toleranceMs: UInt64 = 60
    public static let minMemoryKB: UInt32 = 16 * 1024
    public static let maxMemoryKB: UInt32 = 256 * 1024
    public static let defaultParallelism: UInt32 = 1
    public static let defaultIterations: UInt32 = 2

    public static let safeFallback = Argon2.Params(
        memoryKB: 64 * 1024,
        iterations: 3,
        parallelism: defaultParallelism
    )

    public static func calibrate(targetMs: UInt64 = defaultTargetMs) -> Argon2.Params {
        let pwd = Data("calibration-probe".utf8)
        let salt = Data(repeating: 0xCA, count: 16)
        var memoryKB: UInt32 = 64 * 1024
        var params = Argon2.Params(memoryKB: memoryKB, iterations: defaultIterations, parallelism: defaultParallelism)

        for _ in 0..<6 {
            let elapsedMs = measureMs {
                _ = try? Argon2.deriveKey(password: pwd, salt: salt, params: params, outputLength: 32)
            }
            if elapsedMs == 0 { break }
            let diff = Int64(elapsedMs) - Int64(targetMs)
            if abs(diff) <= Int64(toleranceMs) { break }

            let ratio = Double(targetMs) / Double(elapsedMs)
            let scaled = max(1.0, Double(memoryKB) * ratio)
            memoryKB = UInt32(min(Double(maxMemoryKB), max(Double(minMemoryKB), scaled)))
            params = Argon2.Params(memoryKB: memoryKB, iterations: defaultIterations, parallelism: defaultParallelism)
        }
        return params
    }

    public static func deriveMasterKey(
        password: String,
        salt: Data,
        params: Argon2.Params,
        outputLength: Int = 32
    ) throws -> LockableSecret {
        let pwd = Data(password.utf8)
        let bytes = try Argon2.deriveKey(
            password: pwd,
            salt: salt,
            params: params,
            outputLength: outputLength,
            variant: .id
        )
        return LockableSecret(bytes: bytes)
    }

    private static func measureMs(_ body: () -> Void) -> UInt64 {
        let start = DispatchTime.now()
        body()
        let end = DispatchTime.now()
        return (end.uptimeNanoseconds &- start.uptimeNanoseconds) / 1_000_000
    }
}
