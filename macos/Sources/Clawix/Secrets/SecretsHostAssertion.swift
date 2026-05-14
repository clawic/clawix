import CryptoKit
import Foundation
import SecretsCrypto

enum SecretsHostAssertion {
    static func makeHeader(keyBase64: String, method: String, path: String) throws -> String {
        guard let keyData = Data(base64Encoded: keyBase64) else {
            throw NSError(domain: "SecretsHostAssertion", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid Secrets host assertion key."
            ])
        }
        let timestampMs = Int64(Date().timeIntervalSince1970 * 1000)
        let nonce = SecureRandom.bytes(16).map { String(format: "%02x", $0) }.joined()
        let message = "\(method.uppercased())\n\(path)\n\(timestampMs)\n\(nonce)"
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(message.utf8),
            using: SymmetricKey(data: keyData)
        )
        return "v1:\(timestampMs):\(nonce):\(Data(mac).base64URLEncodedString())"
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
