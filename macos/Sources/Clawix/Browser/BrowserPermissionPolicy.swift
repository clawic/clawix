import Foundation
import WebKit

enum BrowserPermissionPolicy {
    static let approvalStorageKey = "clawix.browser.websiteApproval"
    static let blockedDomainsStorageKey = "clawix.browser.blockedDomains"
    static let allowedDomainsStorageKey = "clawix.browser.allowedDomains"

    enum Approval: String {
        case alwaysAsk = "Always ask"
        case alwaysAllow = "Always allow"
        case alwaysBlock = "Always block"
    }

    enum DomainList {
        case blocked
        case allowed
    }

    enum BrowsingDataKind: String {
        case all = "Clear all browsing data"
        case cache = "Clear cache"
        case cookies = "Clear cookies"
    }

    static var currentApproval: Approval {
        let raw = UserDefaults.standard.string(forKey: approvalStorageKey)
        return Approval(rawValue: raw ?? "") ?? .alwaysAsk
    }

    static func decision(for url: URL) -> BrowserNavigationDecision {
        if isLocalOrBlank(url) { return .allow }
        if hostMatches(url, domains: blockedDomains) { return .block }
        if hostMatches(url, domains: allowedDomains) { return .allow }
        switch currentApproval {
        case .alwaysAllow:
            return .allow
        case .alwaysBlock:
            return .block
        case .alwaysAsk:
            return .ask
        }
    }

    static var blockedDomains: [String] {
        get { normalizedStoredDomains(forKey: blockedDomainsStorageKey) }
        set { UserDefaults.standard.set(normalizedDomains(newValue), forKey: blockedDomainsStorageKey) }
    }

    static var allowedDomains: [String] {
        get { normalizedStoredDomains(forKey: allowedDomainsStorageKey) }
        set { UserDefaults.standard.set(normalizedDomains(newValue), forKey: allowedDomainsStorageKey) }
    }

    static func normalizedDomain(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !trimmed.isEmpty else { return nil }

        let url: URL?
        if trimmed.contains("://") {
            url = URL(string: trimmed)
        } else {
            url = URL(string: "https://\(trimmed)")
        }

        var host = url?.host ?? trimmed
        if let colonIndex = host.lastIndex(of: ":"), host.contains(".") {
            host = String(host[..<colonIndex])
        }
        host = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))

        let invalidScalars = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "/?#@"))
        guard !host.isEmpty,
              host.rangeOfCharacter(from: invalidScalars) == nil,
              host.contains(".") || host == "localhost"
        else { return nil }
        return host
    }

    static func addDomain(_ raw: String, to list: DomainList) -> String? {
        guard let domain = normalizedDomain(raw) else { return nil }
        switch list {
        case .blocked:
            var blocked = blockedDomains.filter { $0 != domain }
            blocked.append(domain)
            blockedDomains = blocked
            allowedDomains = allowedDomains.filter { $0 != domain }
        case .allowed:
            var allowed = allowedDomains.filter { $0 != domain }
            allowed.append(domain)
            allowedDomains = allowed
            blockedDomains = blockedDomains.filter { $0 != domain }
        }
        return domain
    }

    static func removeDomain(_ domain: String, from list: DomainList) {
        guard let normalized = normalizedDomain(domain) else { return }
        switch list {
        case .blocked:
            blockedDomains = blockedDomains.filter { $0 != normalized }
        case .allowed:
            allowedDomains = allowedDomains.filter { $0 != normalized }
        }
    }

    static func clearBrowsingData(_ kind: BrowsingDataKind, completion: @escaping () -> Void) {
        let types: Set<String>
        switch kind {
        case .all:
            types = WKWebsiteDataStore.allWebsiteDataTypes()
        case .cache:
            types = [
                WKWebsiteDataTypeDiskCache,
                WKWebsiteDataTypeMemoryCache,
                WKWebsiteDataTypeOfflineWebApplicationCache,
                WKWebsiteDataTypeFetchCache,
            ]
        case .cookies:
            types = [WKWebsiteDataTypeCookies]
        }
        WKWebsiteDataStore.default()
            .removeData(ofTypes: types, modifiedSince: Date(timeIntervalSince1970: 0)) {
                Task { @MainActor in completion() }
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

    private static func normalizedStoredDomains(forKey key: String) -> [String] {
        normalizedDomains(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    private static func normalizedDomains(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { raw in
            guard let domain = normalizedDomain(raw), !seen.contains(domain) else { return nil }
            seen.insert(domain)
            return domain
        }
        .sorted()
    }

    private static func hostMatches(_ url: URL, domains: [String]) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return domains.contains { domain in
            host == domain || host.hasSuffix(".\(domain)")
        }
    }
}

enum BrowserNavigationDecision {
    case allow
    case ask
    case block
}
