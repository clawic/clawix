import CryptoKit
import Foundation
import Security

@objc(ClawixSecretsXPCProtocol)
protocol ClawixSecretsXPCProtocol {
    @objc(bootstrapWithAssertionKey:reply:)
    func bootstrap(assertionKeyBase64: String, reply: @escaping (Bool, String?) -> Void)

    @objc(assertionForMethod:path:reply:)
    func assertion(method: String, path: String, reply: @escaping (String?, String?) -> Void)
}

final class SecretsAssertionService: NSObject, ClawixSecretsXPCProtocol {
    private let lock = NSLock()
    private var assertionKey: Data?

    func bootstrap(assertionKeyBase64: String, reply: @escaping (Bool, String?) -> Void) {
        guard let keyData = Data(base64Encoded: assertionKeyBase64), keyData.count >= 32 else {
            reply(false, "invalid assertion key")
            return
        }
        lock.lock()
        assertionKey = keyData
        lock.unlock()
        reply(true, nil)
    }

    func assertion(method: String, path: String, reply: @escaping (String?, String?) -> Void) {
        lock.lock()
        let keyData = assertionKey
        lock.unlock()
        guard let keyData else {
            reply(nil, "assertion key not bootstrapped")
            return
        }

        let timestampMs = Int64(Date().timeIntervalSince1970 * 1000)
        let nonce = Self.randomNonceHex()
        let message = "\(method.uppercased())\n\(path)\n\(timestampMs)\n\(nonce)"
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(message.utf8),
            using: SymmetricKey(data: keyData)
        )
        reply("v1:\(timestampMs):\(nonce):\(Data(mac).base64URLEncodedString())", nil)
    }

    private static func randomNonceHex() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        } else {
            return bytes.map { String(format: "%02x", $0) }.joined()
        }
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard Self.verifyCaller(connection) else {
            return false
        }
        connection.exportedInterface = NSXPCInterface(with: ClawixSecretsXPCProtocol.self)
        connection.exportedObject = SecretsAssertionService()
        connection.resume()
        return true
    }

    private static func verifyCaller(_ connection: NSXPCConnection) -> Bool {
        guard let expected = Bundle.main.object(forInfoDictionaryKey: "CLXAllowedCallerIdentifier") as? String,
              !expected.isEmpty,
              let caller = codeSignatureIdentity(pid: connection.processIdentifier),
              let ownTeamIdentifier = ownCodeSignatureIdentity()?.teamIdentifier,
              !ownTeamIdentifier.isEmpty else {
            return false
        }
        return caller.identifier == expected && caller.teamIdentifier == ownTeamIdentifier
    }

    private struct CodeSignatureIdentity {
        let identifier: String
        let teamIdentifier: String?
    }

    private static func codeSignatureIdentity(pid: pid_t) -> CodeSignatureIdentity? {
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &code) == errSecSuccess,
              let code else {
            return nil
        }
        return codeSignatureIdentity(code: code)
    }

    private static func ownCodeSignatureIdentity() -> CodeSignatureIdentity? {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess,
              let code else {
            return nil
        }
        return codeSignatureIdentity(code: code)
    }

    private static func codeSignatureIdentity(code: SecCode) -> CodeSignatureIdentity? {
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else {
            return nil
        }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(), &information) == errSecSuccess,
              let info = information as? [String: Any],
              let identifier = info[kSecCodeInfoIdentifier as String] as? String else {
            return nil
        }
        return CodeSignatureIdentity(
            identifier: identifier,
            teamIdentifier: info[kSecCodeInfoTeamIdentifier as String] as? String
        )
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

let listener = NSXPCListener.service()
let delegate = ListenerDelegate()
listener.delegate = delegate
listener.resume()
