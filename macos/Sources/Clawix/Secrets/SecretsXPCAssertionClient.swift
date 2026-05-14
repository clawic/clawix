import Foundation

@objc(ClawixSecretsXPCProtocol)
private protocol ClawixSecretsXPCProtocol {
    @objc(bootstrapWithAssertionKey:reply:)
    func bootstrap(assertionKeyBase64: String, reply: @escaping (Bool, String?) -> Void)

    @objc(assertionForMethod:path:reply:)
    func assertion(method: String, path: String, reply: @escaping (String?, String?) -> Void)
}

final class SecretsXPCAssertionClient {
    static let shared = SecretsXPCAssertionClient()

    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private var bootstrappedKeyBase64: String?

    func assertionHeader(keyBase64: String, method: String, path: String) async throws -> String {
        try await ensureBootstrapped(keyBase64: keyBase64)
        return try await withCheckedThrowingContinuation { continuation in
            proxy().assertion(method: method, path: path) { assertion, error in
                if let assertion {
                    continuation.resume(returning: assertion)
                } else {
                    continuation.resume(throwing: Self.error(error ?? "Secrets XPC assertion failed"))
                }
            }
        }
    }

    private func ensureBootstrapped(keyBase64: String) async throws {
        if isBootstrapped(keyBase64: keyBase64) { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            proxy().bootstrap(assertionKeyBase64: keyBase64) { ok, error in
                if ok {
                    self.lock.lock()
                    self.bootstrappedKeyBase64 = keyBase64
                    self.lock.unlock()
                    continuation.resume()
                } else {
                    continuation.resume(throwing: Self.error(error ?? "Secrets XPC bootstrap failed"))
                }
            }
        }
    }

    private func isBootstrapped(keyBase64: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return bootstrappedKeyBase64 == keyBase64 && connection != nil
    }

    private func proxy() -> ClawixSecretsXPCProtocol {
        lock.lock()
        defer { lock.unlock() }
        if connection == nil {
            let serviceName = Self.serviceName()
            let newConnection = NSXPCConnection(serviceName: serviceName)
            newConnection.remoteObjectInterface = NSXPCInterface(with: ClawixSecretsXPCProtocol.self)
            newConnection.invalidationHandler = { [weak self] in
                self?.reset()
            }
            newConnection.interruptionHandler = { [weak self] in
                self?.reset()
            }
            newConnection.resume()
            connection = newConnection
        }
        return connection!.remoteObjectProxyWithErrorHandler { [weak self] error in
            self?.reset()
            NSLog("Secrets XPC assertion proxy error: \(error.localizedDescription)")
        } as! ClawixSecretsXPCProtocol
    }

    private func reset() {
        lock.lock()
        connection = nil
        bootstrappedKeyBase64 = nil
        lock.unlock()
    }

    private static func serviceName() -> String {
        let appIdentifier = Bundle.main.bundleIdentifier ?? "com.example.clawix.desktop"
        return "\(appIdentifier).secrets-xpc"
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "SecretsXPCAssertionClient", code: 1, userInfo: [
            NSLocalizedDescriptionKey: message
        ])
    }
}
