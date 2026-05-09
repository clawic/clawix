import CryptoKit
import Foundation

/// PKCE (Proof Key for Code Exchange) helpers. Used by Anthropic's
/// OAuth flow. SHA-256 + base64url, no padding.
enum PKCE {

    /// Cryptographically random verifier, 32 bytes → 43 base64url chars.
    static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return Data(bytes).base64URLEncoded
    }

    /// SHA-256(verifier), base64url-encoded, no padding. The "S256"
    /// transformation; raw "plain" is not used.
    static func challenge(forVerifier verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncoded
    }

    /// Random state token. Plain base64url, 16 bytes → 22 chars.
    static func makeState() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return Data(bytes).base64URLEncoded
    }
}

extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
