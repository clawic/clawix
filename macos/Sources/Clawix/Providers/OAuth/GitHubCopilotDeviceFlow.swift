import AIProviders
import Foundation

/// GitHub OAuth device-code flow used for Copilot. The client id is
/// the public Copilot app id (same value the official VS Code
/// extension ships). This file owns the flow only; the actual API
/// calls live in `GitHubCopilotClient.swift`.
@MainActor
final class GitHubCopilotDeviceFlow {

    /// Public client id of GitHub Copilot's Editor extension.
    static let clientId = "Iv1.b507a08c87ecfe98"

    private static let deviceCodeURL = URL(string: "https://github.com/login/device/code")!
    private static let tokenURL = URL(string: "https://github.com/login/oauth/access_token")!

    struct DeviceCode: Sendable {
        let deviceCode: String
        let userCode: String
        let verificationUri: URL
        let interval: TimeInterval
        let expiresAt: Date
    }

    /// Step 1: ask GitHub for a device + user code pair.
    func requestDeviceCode() async throws -> DeviceCode {
        var req = URLRequest(url: Self.deviceCodeURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Clawix/1.0", forHTTPHeaderField: "User-Agent")
        let body = try JSONSerialization.data(withJSONObject: [
            "client_id": Self.clientId,
            "scope": "read:user"
        ])
        req.httpBody = body
        let (data, _) = try await AIHTTP.send(req, timeoutSeconds: 15)
        struct Response: Codable {
            let device_code: String
            let user_code: String
            let verification_uri: String
            let expires_in: Int
            let interval: Int
        }
        let response = try AIHTTP.decode(Response.self, from: data)
        return DeviceCode(
            deviceCode: response.device_code,
            userCode: response.user_code,
            verificationUri: URL(string: response.verification_uri) ?? URL(string: "https://github.com/login/device")!,
            interval: TimeInterval(response.interval),
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expires_in))
        )
    }

    /// Step 2: poll until the user authorizes or the code expires.
    func pollAccessToken(deviceCode: String, interval: TimeInterval, expiresAt: Date) async throws -> String {
        while Date() < expiresAt {
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            var req = URLRequest(url: Self.tokenURL)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Clawix/1.0", forHTTPHeaderField: "User-Agent")
            let body = try JSONSerialization.data(withJSONObject: [
                "client_id": Self.clientId,
                "device_code": deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
            ])
            req.httpBody = body
            do {
                let (data, _) = try await AIHTTP.send(req, timeoutSeconds: 15)
                struct OK: Codable { let access_token: String }
                struct Pending: Codable { let error: String }
                if let ok = try? AIHTTP.decode(OK.self, from: data) {
                    return ok.access_token
                }
                if let pending = try? AIHTTP.decode(Pending.self, from: data) {
                    if pending.error == "authorization_pending" { continue }
                    if pending.error == "slow_down" {
                        try? await Task.sleep(nanoseconds: UInt64((interval + 5) * 1_000_000_000))
                        continue
                    }
                    throw AIClientError.provider("GitHub: \(pending.error)")
                }
            } catch let error as AIClientError {
                if case .http = error { throw error }
                continue
            }
        }
        throw AIClientError.timedOut
    }

    /// Persists the new account in the vault. Saves the GitHub OAuth
    /// access token; the per-request Copilot token is fetched on demand
    /// by `GitHubCopilotClient`.
    func persistAccount(githubAccessToken: String, accountEmail: String?) throws -> ProviderAccount {
        let store = AIAccountVaultStore.shared
        let count = (try? store.listAccounts(for: .githubCopilot).count) ?? 0
        let label = (accountEmail ?? (count == 0 ? "Personal" : "Account \(count + 1)"))
        let draft = ProviderAccountDraft(
            providerId: .githubCopilot,
            label: label,
            authMethod: .deviceCode(.githubCopilot),
            accessToken: githubAccessToken,
            accountEmail: accountEmail
        )
        return try store.createAccount(draft)
    }
}
