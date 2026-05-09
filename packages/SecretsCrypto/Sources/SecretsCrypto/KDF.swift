import Foundation
import CryptoKit

public enum KDF {

    public static func deriveSubkey(
        from master: LockableSecret,
        info: Data,
        length: Int = 32,
        salt: Data = Data()
    ) -> LockableSecret {
        precondition(master.count > 0, "master key must not be empty")
        precondition(length > 0, "subkey length must be positive")

        let derivedBytes = master.withBytes { mb -> Data in
            let sym = SymmetricKey(data: Data(mb))
            let outKey = HKDF<SHA256>.deriveKey(
                inputKeyMaterial: sym,
                salt: salt,
                info: info,
                outputByteCount: length
            )
            return outKey.withUnsafeBytes { Data($0) }
        }
        return LockableSecret(bytes: derivedBytes)
    }
}
