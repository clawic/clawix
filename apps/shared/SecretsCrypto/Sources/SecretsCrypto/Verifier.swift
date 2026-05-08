import Foundation
import CryptoKit

public enum Verifier {

    public static let length = 32
    private static let domain = Data("clawix-vault-verifier-v1".utf8)

    public static func compute(masterKey: LockableSecret) -> Data {
        precondition(masterKey.count == 32, "master key must be 32 bytes")
        return masterKey.withBytes { mb -> Data in
            let sym = SymmetricKey(data: Data(mb))
            var hmac = HMAC<SHA256>(key: sym)
            hmac.update(data: domain)
            return Data(hmac.finalize())
        }
    }

    public static func matches(_ candidate: Data, expected: Data) -> Bool {
        guard candidate.count == expected.count, !candidate.isEmpty else { return false }
        var diff: UInt8 = 0
        let cStart = candidate.startIndex
        let eStart = expected.startIndex
        for i in 0..<candidate.count {
            diff |= candidate[cStart + i] ^ expected[eStart + i]
        }
        return diff == 0
    }
}
