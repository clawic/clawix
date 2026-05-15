import Foundation
import ClawixCore

struct BackendAccountProfile: Equatable {
    var email: String?
    var accountLabel: String?
    var planType: String?
    var name: String?

    static let empty = BackendAccountProfile(email: nil, accountLabel: nil, planType: nil, name: nil)
}

enum BackendAuthReader {

    private static let backendDirectoryName = ".codex"

    static var authURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("\(backendDirectoryName)/auth.json")
    }

    static func read() -> BackendAccountProfile {
        let environment = ProcessInfo.processInfo.environment
        if environment[ClawixEnv.disableBackend] == "1" || environment[ClawixEnv.dummyMode] == "1" {
            return BackendAccountProfile(
                email: "account@example.com",
                accountLabel: String(localized: "Demo account", bundle: AppLocale.bundle, locale: AppLocale.current),
                planType: nil,
                name: String(localized: "Demo User", bundle: AppLocale.bundle, locale: AppLocale.current)
            )
        }

        guard let data = try? Data(contentsOf: authURL),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any],
              let idToken = tokens["id_token"] as? String,
              let payload = decodeJWTPayload(idToken)
        else { return .empty }

        let email = (payload["email"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let name = (payload["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        var planType: String? = nil
        var orgTitle: String? = nil
        if let auth = payload["https://api.openai.com/auth"] as? [String: Any] {
            planType = (auth["chatgpt_plan_type"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            if let orgs = auth["organizations"] as? [[String: Any]] {
                let chosen = orgs.first(where: { ($0["is_default"] as? Bool) == true }) ?? orgs.first
                orgTitle = (chosen?["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            }
        }

        return BackendAccountProfile(
            email: email,
            accountLabel: orgTitle.map(accountLabel(forOrgTitle:)),
            planType: planType,
            name: name
        )
    }

    private static func accountLabel(forOrgTitle title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("Personal") == .orderedSame {
            return "Personal account"
        }
        return L10n.accountLabel(trimmed)
    }

    private static func decodeJWTPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2,
              let data = base64URLDecode(String(parts[1])),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    private static func base64URLDecode(_ s: String) -> Data? {
        var b64 = s.replacingOccurrences(of: "-", with: "+")
                   .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - b64.count % 4) % 4
        if pad > 0 { b64.append(String(repeating: "=", count: pad)) }
        return Data(base64Encoded: b64)
    }
}
