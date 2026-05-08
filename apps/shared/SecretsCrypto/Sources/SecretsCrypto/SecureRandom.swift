import Foundation
import Security

public enum SecureRandom {
    public static func bytes(_ count: Int) -> Data {
        precondition(count >= 0, "byte count must be non-negative")
        guard count > 0 else { return Data() }
        var data = Data(count: count)
        let result = data.withUnsafeMutableBytes { buf -> Int32 in
            guard let base = buf.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, count, base)
        }
        precondition(result == errSecSuccess, "SecRandomCopyBytes failed with status \(result)")
        return data
    }

    public static func nonce12() -> Data { bytes(12) }
    public static func saltKDF() -> Data { bytes(32) }
    public static func keyBytes32() -> Data { bytes(32) }
}
