import AppKit
import CryptoKit
import Foundation
import os

/// Two-tier cache for favicon bitmaps, modeled after how a real browser
/// keeps icons warm: an in-memory `NSCache` for instant hits while the
/// app is running, and a persistent on-disk store under
/// `~/Library/Caches/Clawix/Favicons/` so a freshly launched app shows
/// the icon for any host you've already visited without a network round
/// trip. Concurrent requests for the same URL are coalesced so a tab
/// strip with five tabs pointing to the same host fires a single fetch.
final class FaviconCache: @unchecked Sendable {
    static let shared = FaviconCache()

    private let memory = NSCache<NSString, NSImage>()
    private let directory: URL
    private let inFlight = OSAllocatedUnfairLock<[URL: Task<NSImage?, Never>]>(
        initialState: [:]
    )

    private init() {
        memory.countLimit = 512
        let caches = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        directory = caches
            .appendingPathComponent("Clawix", isDirectory: true)
            .appendingPathComponent("Favicons", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
    }

    /// Synchronous in-memory lookup. Safe to call from the main thread on
    /// every SwiftUI body; returns immediately.
    func cachedImage(for url: URL) -> NSImage? {
        memory.object(forKey: key(for: url))
    }

    /// Returns the favicon for `url`, hitting memory first, then disk,
    /// then the network. Concurrent calls for the same URL share one
    /// underlying fetch.
    func image(for url: URL) async -> NSImage? {
        if let hit = cachedImage(for: url) { return hit }

        let task: Task<NSImage?, Never> = inFlight.withLock { state in
            if let existing = state[url] { return existing }
            let new = Task<NSImage?, Never> { [weak self] in
                await self?.load(url: url)
            }
            state[url] = new
            return new
        }

        let result = await task.value

        inFlight.withLock { state in state[url] = nil }

        if let result {
            memory.setObject(result, forKey: key(for: url))
        }
        return result
    }

    /// Fire-and-forget warm-up so the icon is on disk by the time the UI
    /// asks for it. Used when a navigation starts.
    func prefetch(_ url: URL) {
        if cachedImage(for: url) != nil { return }
        Task.detached(priority: .utility) { [weak self] in
            _ = await self?.image(for: url)
        }
    }

    private func load(url: URL) async -> NSImage? {
        let fileURL = diskURL(for: url)
        if let data = try? Data(contentsOf: fileURL),
           let img = NSImage(data: data) {
            return img
        }
        do {
            var req = URLRequest(
                url: url,
                cachePolicy: .useProtocolCachePolicy,
                timeoutInterval: 8.0
            )
            req.setValue("image/*", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                return nil
            }
            guard let img = NSImage(data: data) else { return nil }
            try? data.write(to: fileURL, options: .atomic)
            return img
        } catch {
            return nil
        }
    }

    private func key(for url: URL) -> NSString {
        url.absoluteString as NSString
    }

    private func diskURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name)
    }
}
