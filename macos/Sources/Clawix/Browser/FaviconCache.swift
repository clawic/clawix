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
///
/// On top of the two tiers, hosts that returned no usable favicon are
/// recorded with a `.miss` sentinel so the UI doesn't chase a 404 every
/// time the user reopens them. The sentinel expires after 24 hours so a
/// site that adds a favicon shows up the next day.
final class FaviconCache: @unchecked Sendable {
    static let shared = FaviconCache()

    private let memory = NSCache<NSString, NSImage>()
    private let directory: URL
    private let inFlight = OSAllocatedUnfairLock<[URL: Task<NSImage?, Never>]>(
        initialState: [:]
    )
    private let primed = OSAllocatedUnfairLock<Bool>(initialState: false)

    private let negativeTTL: TimeInterval = 60 * 60 * 24
    private let diskMaxAge: TimeInterval = 60 * 24 * 60 * 60

    private init() {
        memory.countLimit = 2048
        let caches = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        directory = caches
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.clawix, isDirectory: true)
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.favicons, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
    }

    /// Synchronous in-memory lookup. Safe to call from the main thread on
    /// every SwiftUI body; returns immediately.
    func cachedImage(for url: URL) -> NSImage? {
        memory.object(forKey: key(for: url))
    }

    /// Synchronous lookup that falls through to the on-disk blob via
    /// memory-mapped I/O. Safe on the main thread because favicons are
    /// 1-4 KB and `mappedIfSafe` skips a real read; decode is
    /// sub-millisecond on SSD. Returns nil when the host has never been
    /// fetched (the negative-cache check happens only in the async
    /// path so a stale `.miss` never hides a valid blob next to it).
    func cachedImageOrLoadFromDisk(for url: URL) -> NSImage? {
        if let hit = memory.object(forKey: key(for: url)) { return hit }
        let fileURL = diskURL(for: url)
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
              let img = NSImage(data: data) else { return nil }
        memory.setObject(img, forKey: key(for: url))
        return img
    }

    /// Returns the favicon for `url`, hitting memory first, then disk,
    /// then the network. Concurrent calls for the same URL share one
    /// underlying fetch. Honors the negative cache: a fresh `.miss`
    /// short-circuits to nil without touching the network.
    func image(for url: URL) async -> NSImage? {
        if let hit = cachedImageOrLoadFromDisk(for: url) { return hit }
        if isFreshNegative(for: url) { return nil }

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
    /// asks for it. Used when a navigation starts. Pass
    /// `priority: .userInitiated` for foreground navigation; the
    /// default `.utility` is for background sweeps.
    func prefetch(_ url: URL, priority: TaskPriority = .utility) {
        if cachedImage(for: url) != nil { return }
        Task.detached(priority: priority) { [weak self] in
            _ = await self?.image(for: url)
        }
    }

    /// One-shot, idempotent. Called early from AppState.init so the
    /// kernel page cache holds every favicon blob by the time SwiftUI
    /// asks for them. Also unlinks blobs not accessed in the past 60
    /// days so the directory does not grow unbounded.
    func primeDiskCache() {
        let alreadyPrimed = primed.withLock { state -> Bool in
            if state { return true }
            state = true
            return false
        }
        if alreadyPrimed { return }
        Task.detached(priority: .userInitiated) { [directory, diskMaxAge] in
            let fm = FileManager.default
            guard let entries = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentAccessDateKey],
                options: [.skipsHiddenFiles]
            ) else { return }
            let now = Date()
            for entry in entries {
                if let values = try? entry.resourceValues(forKeys: [
                    .contentAccessDateKey
                ]),
                   let accessed = values.contentAccessDate,
                   now.timeIntervalSince(accessed) > diskMaxAge {
                    try? fm.removeItem(at: entry)
                    continue
                }
                if entry.pathExtension == "miss" { continue }
                _ = try? Data(contentsOf: entry, options: .mappedIfSafe)
            }
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
                writeNegative(for: url)
                return nil
            }
            guard let img = NSImage(data: data) else {
                writeNegative(for: url)
                return nil
            }
            // Clear any stale negative entry BEFORE writing the blob so
            // a crash mid-write can never leave both files coexisting.
            try? FileManager.default.removeItem(at: missURL(for: url))
            try? data.write(to: fileURL, options: .atomic)
            return img
        } catch {
            writeNegative(for: url)
            return nil
        }
    }

    private func isFreshNegative(for url: URL) -> Bool {
        let path = missURL(for: url)
        guard let attrs = try? FileManager.default.attributesOfItem(
            atPath: path.path
        ),
              let modified = attrs[.modificationDate] as? Date else {
            return false
        }
        if Date().timeIntervalSince(modified) > negativeTTL {
            try? FileManager.default.removeItem(at: path)
            return false
        }
        return true
    }

    private func writeNegative(for url: URL) {
        try? Data().write(to: missURL(for: url), options: .atomic)
    }

    private func key(for url: URL) -> NSString {
        url.absoluteString as NSString
    }

    private func diskURL(for url: URL) -> URL {
        directory.appendingPathComponent(digestName(for: url))
    }

    private func missURL(for url: URL) -> URL {
        directory.appendingPathComponent("\(digestName(for: url)).miss")
    }

    private func digestName(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
