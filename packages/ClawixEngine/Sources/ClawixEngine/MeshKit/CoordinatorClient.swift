import Foundation

/// Lightweight HTTP client for the clawix-relay coordinator. Used by
/// devices that need to register, heartbeat, and exchange signaling
/// envelopes to set up Iroh streams.
public struct CoordinatorClient {
    public struct DeviceSession: Codable, Sendable {
        public let deviceId: String
        public let tenantId: String
        public let accessToken: String
        public let refreshToken: String
        public let expiresInSec: Int
        public let coordinator: Coordinator

        public struct Coordinator: Codable, Sendable {
            public let publicBaseUrl: String
            public let irohRelay: IrohRelay?

            public struct IrohRelay: Codable, Sendable {
                public let enabled: Bool
                public let publicUrl: String?
                public let listenAddr: String?
                public let binaryPath: String?
            }
        }
    }

    public struct Peer: Codable, Sendable {
        public let deviceId: String
        public let irohNodeId: String
        public let relayUrl: String?
        public let publicAddrs: [String]
        public let label: String
        public let platform: String?
        public let lastSeenAt: Int
    }

    public let baseURL: URL
    public let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func requestMagicLink(
        email: String,
        deviceLabel: String?,
        platform: String?
    ) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/auth/magic-link/start"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "email": email,
            "purpose": "device-register",
            "deviceLabel": deviceLabel as Any,
            "platform": platform as Any,
        ].compactMapValues { $0 is NSNull ? nil : $0 }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await performExpectingJSON(request)
    }

    public func consumeMagicLink(
        token: String,
        deviceLabel: String?,
        platform: String?,
        platformVersion: String?,
        irohNodeID: String?
    ) async throws -> DeviceSession {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/auth/magic-link/consume"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let payload: [String: Any] = [
            "token": token,
            "deviceLabel": deviceLabel as Any,
            "platform": platform as Any,
            "platformVersion": platformVersion as Any,
            "irohNodeId": irohNodeID as Any,
        ].compactMapValues { $0 is NSNull ? nil : $0 }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performExpectingJSON(request)
        return try JSONDecoder().decode(DeviceSession.self, from: data)
    }

    public func registerWithPreauthKey(
        token: String,
        label: String?,
        platform: String?,
        platformVersion: String?,
        irohNodeID: String?
    ) async throws -> DeviceSession {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/devices/register-preauth"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let payload: [String: Any] = [
            "token": token,
            "label": label as Any,
            "platform": platform as Any,
            "platformVersion": platformVersion as Any,
            "irohNodeId": irohNodeID as Any,
        ].compactMapValues { $0 is NSNull ? nil : $0 }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performExpectingJSON(request)
        return try JSONDecoder().decode(DeviceSession.self, from: data)
    }

    public func heartbeat(
        accessToken: String,
        irohNodeID: String?,
        relayURL: URL?,
        publicAddresses: [String]
    ) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/devices/heartbeat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "authorization")
        let body: [String: Any] = [
            "irohNodeId": irohNodeID as Any,
            "relayUrl": relayURL?.absoluteString as Any,
            "publicAddrs": publicAddresses,
        ].compactMapValues { $0 is NSNull ? nil : $0 }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await performExpectingJSON(request)
    }

    public func listPeers(accessToken: String) async throws -> [Peer] {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/peers"))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "authorization")
        let (data, _) = try await performExpectingJSON(request)
        struct Envelope: Codable { let items: [Peer] }
        return try JSONDecoder().decode(Envelope.self, from: data).items
    }

    private func performExpectingJSON(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "<binary>"
            throw NSError(domain: "CoordinatorClient", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(message)",
            ])
        }
        return (data, http)
    }
}
