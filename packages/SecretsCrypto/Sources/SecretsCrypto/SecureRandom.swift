import Foundation
#if canImport(Security)
import Security
#endif

public enum SecureRandom {
    public static func bytes(_ count: Int) -> Data {
        precondition(count >= 0, "byte count must be non-negative")
        guard count > 0 else { return Data() }
        var data = Data(count: count)
        #if canImport(Security)
        let result = data.withUnsafeMutableBytes { buf -> Int32 in
            guard let base = buf.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, count, base)
        }
        precondition(result == errSecSuccess, "SecRandomCopyBytes failed with status \(result)")
        #else
        guard let handle = FileHandle(forReadingAtPath: "/dev/urandom") else {
            preconditionFailure("SecureRandom: cannot open /dev/urandom")
        }
        defer { try? handle.close() }
        var remaining = count
        var offset = 0
        while remaining > 0 {
            guard let chunk = try? handle.read(upToCount: remaining), !chunk.isEmpty else {
                preconditionFailure("SecureRandom: /dev/urandom read failed")
            }
            data.replaceSubrange(offset..<(offset + chunk.count), with: chunk)
            offset += chunk.count
            remaining -= chunk.count
        }
        #endif
        return data
    }

    public static func nonce12() -> Data { bytes(12) }
    public static func saltKDF() -> Data { bytes(32) }
    public static func keyBytes32() -> Data { bytes(32) }
}
