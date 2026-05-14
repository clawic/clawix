import SwiftUI
import Combine
import AppKit
import ClawixCore
import ClawixEngine

final class LinkMetadataStore: ObservableObject {
    @Published private(set) var titles: [URL: String] = [:]
    private var inFlight: Set<URL> = []

    func title(for url: URL) -> String? {
        titles[url]
    }

    func ensureTitle(for url: URL) {
        if titles[url] != nil || inFlight.contains(url) { return }
        inFlight.insert(url)
        Task { [weak self] in
            let resolved = await Self.fetchTitle(url)
            await MainActor.run {
                guard let self else { return }
                self.titles[url] = resolved ?? Self.fallback(for: url)
                self.inFlight.remove(url)
            }
        }
    }

    static func fallback(for url: URL) -> String {
        if let host = url.host, !host.isEmpty {
            if let port = url.port { return "\(host):\(port)" }
            return host
        }
        return url.absoluteString
    }

    private static func fetchTitle(_ url: URL) async -> String? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        req.setValue("Mozilla/5.0 (Macintosh) Clawix", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { return nil }
        return parseTitle(from: html)
    }

    /// Tiny regex-free `<title>` extractor: tolerant of attributes on the
    /// open tag and of mixed casing. Returns nil when the document has no
    /// usable title.
    static func parseTitle(from html: String) -> String? {
        guard let openRange = html.range(of: "<title", options: .caseInsensitive),
              let openEnd = html[openRange.upperBound...].range(of: ">"),
              let closeRange = html[openEnd.upperBound...].range(of: "</title>", options: .caseInsensitive)
        else { return nil }
        let raw = html[openEnd.upperBound..<closeRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }
}
