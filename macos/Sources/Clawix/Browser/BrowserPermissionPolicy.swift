import Foundation

enum BrowserPermissionPolicy {
    static let approvalStorageKey = "clawix.browser.websiteApproval"

    enum Approval: String {
        case alwaysAsk = "Always ask"
        case alwaysAllow = "Always allow"
        case alwaysBlock = "Always block"
    }

    static var currentApproval: Approval {
        let raw = UserDefaults.standard.string(forKey: approvalStorageKey)
        return Approval(rawValue: raw ?? "") ?? .alwaysAsk
    }

    static func decision(for url: URL) -> BrowserNavigationDecision {
        if isLocalOrBlank(url) { return .allow }
        switch currentApproval {
        case .alwaysAllow:
            return .allow
        case .alwaysBlock:
            return .block
        case .alwaysAsk:
            return .ask
        }
    }

    private static func isLocalOrBlank(_ url: URL) -> Bool {
        if url.absoluteString == "about:blank" { return true }
        guard let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "file" { return true }
        guard scheme == "http" || scheme == "https" else { return true }
        guard let host = url.host?.lowercased() else { return false }
        return host == "localhost"
            || host == "127.0.0.1"
            || host == "::1"
    }
}

enum BrowserNavigationDecision {
    case allow
    case ask
    case block
}
