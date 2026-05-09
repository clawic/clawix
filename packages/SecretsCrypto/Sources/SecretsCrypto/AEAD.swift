import Foundation
import CryptoKit

public enum AEAD {

    public static let nonceSize = 12
    public static let tagSize = 16
    public static let versionSize = 1
    public static let overhead = versionSize + nonceSize + tagSize

    public enum Error: Swift.Error, CustomStringConvertible, Equatable {
        case unsupportedVersion(UInt8)
        case malformedBlob
        case decryptionFailed
        case invalidKey

        public var description: String {
            switch self {
            case .unsupportedVersion(let v):
                return "AEAD: unsupported crypto version 0x\(String(v, radix: 16))"
            case .malformedBlob:
                return "AEAD: malformed sealed blob"
            case .decryptionFailed:
                return "AEAD: decryption failed (wrong key, tampered ciphertext, or wrong AAD)"
            case .invalidKey:
                return "AEAD: invalid key (must be 32 bytes)"
            }
        }
    }

    public static func seal(plaintext: Data, key: LockableSecret, aad: Data = Data()) throws -> Data {
        guard key.count == 32 else { throw Error.invalidKey }
        let nonceData = SecureRandom.nonce12()
        let nonce = try ChaChaPoly.Nonce(data: nonceData)

        let sealed: ChaChaPoly.SealedBox = try key.withBytes { kb in
            let sym = SymmetricKey(data: Data(kb))
            return try ChaChaPoly.seal(plaintext, using: sym, nonce: nonce, authenticating: aad)
        }

        var blob = Data(capacity: overhead + plaintext.count)
        blob.append(CryptoVersion.current)
        blob.append(nonceData)
        blob.append(sealed.ciphertext)
        blob.append(sealed.tag)
        return blob
    }

    public static func open(blob: Data, key: LockableSecret, aad: Data = Data()) throws -> Data {
        guard key.count == 32 else { throw Error.invalidKey }
        guard blob.count >= overhead else { throw Error.malformedBlob }

        let version = blob[blob.startIndex]
        guard CryptoVersion.isSupported(version) else { throw Error.unsupportedVersion(version) }

        let nonceStart = blob.startIndex + versionSize
        let nonceEnd = nonceStart + nonceSize
        let cipherEnd = blob.endIndex - tagSize
        guard nonceEnd <= cipherEnd else { throw Error.malformedBlob }

        let nonce = try ChaChaPoly.Nonce(data: blob[nonceStart..<nonceEnd])
        let cipher = blob[nonceEnd..<cipherEnd]
        let tag = blob[cipherEnd..<blob.endIndex]
        let sealedBox: ChaChaPoly.SealedBox
        do {
            sealedBox = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: cipher, tag: tag)
        } catch {
            throw Error.malformedBlob
        }

        return try key.withBytes { kb in
            let sym = SymmetricKey(data: Data(kb))
            do {
                return try ChaChaPoly.open(sealedBox, using: sym, authenticating: aad)
            } catch {
                throw Error.decryptionFailed
            }
        }
    }

    public static func versionByte(of blob: Data) -> UInt8? {
        guard !blob.isEmpty else { return nil }
        return blob[blob.startIndex]
    }
}
