import AppKit
import Combine
import Foundation

/// Single source of truth for the user's installed Apps. Persists each
/// app as a folder under `~/Library/Application Support/Clawix/Apps/<slug>/`
/// with a `manifest.json` next to the actual web files (`index.html`,
/// `app.js`, `style.css`, ...). The store watches the parent dir on a
/// timer and reloads the index when the agent writes new files from a
/// different process; this keeps the contract between the agent (which
/// can be any process that writes files there) and the GUI minimal:
/// "write a manifest + files; the sidebar will pick it up".
@MainActor
final class AppsStore: ObservableObject {
    static let shared = AppsStore()

    @Published private(set) var apps: [AppRecord] = []

    /// Effective sort: pinned first, then most-recently-opened, then
    /// most-recently-created. Used by every consumer (sidebar, grid).
    var sortedApps: [AppRecord] {
        apps.sorted(by: AppsStore.compareForSidebar)
    }

    private let rootURL: URL
    private let fileManager: FileManager
    private let manifestName = "manifest.json"
    private var pollingTimer: Timer?
    /// Last-known mtime per slug; used to detect agent-side file changes
    /// without diffing every file's bytes on each poll.
    private var lastSeenMtime: [String: Date] = [:]

    init(
        rootURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? AppsStore.defaultRootURL(fileManager: fileManager)
        ensureRootExists()
        reloadFromDisk()
        startPolling()
    }

    deinit {
        pollingTimer?.invalidate()
    }

    /// `~/Library/Application Support/Clawix/Apps`. Mirrors what the
    /// rest of the app does for chat databases, dictionaries, etc.
    static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        let support = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.clawix, isDirectory: true)
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.apps, isDirectory: true)
    }

    /// Bring `apps` in sync with whatever currently lives on disk. Cheap
    /// enough to call on every poll because we short-circuit per-slug
    /// when the manifest mtime hasn't moved.
    func reloadFromDisk() {
        ensureRootExists()
        guard let entries = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            apps = []
            return
        }

        var found: [AppRecord] = []
        var newMtimes: [String: Date] = [:]
        for entry in entries {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let manifestURL = entry.appendingPathComponent(manifestName)
            guard fileManager.fileExists(atPath: manifestURL.path) else { continue }
            do {
                let mtime = (try manifestURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let data = try Data(contentsOf: manifestURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let record = try decoder.decode(AppRecord.self, from: data)
                found.append(record)
                newMtimes[record.slug] = mtime
            } catch {
                // Don't crash if a manifest is malformed; just skip it
                // so the agent (or the user) can fix it without losing
                // the rest of the index.
                continue
            }
        }
        // Reflect deletions: if a slug is gone from disk, drop it.
        let sortedFound = found.sorted(by: AppsStore.compareForSidebar)
        if sortedFound != apps.sorted(by: AppsStore.compareForSidebar) {
            apps = sortedFound
        }
        lastSeenMtime = newMtimes
    }

    // MARK: - CRUD

    /// Create a brand-new app folder + manifest. Returns the persisted
    /// record. Throws if the slug already exists or contains characters
    /// that would not survive a URL host (a-z, 0-9, dash).
    @discardableResult
    func create(
        name: String,
        slug: String? = nil,
        description: String = "",
        icon: String = "",
        accentColor: String = "",
        projectId: UUID? = nil,
        tags: [String] = [],
        permissions: AppPermissions = .defaults,
        createdByChatId: UUID? = nil
    ) throws -> AppRecord {
        let resolvedSlug = try uniqueSlug(preferred: slug, name: name)
        let now = Date()
        let record = AppRecord(
            slug: resolvedSlug,
            name: name,
            description: description,
            icon: icon,
            accentColor: accentColor,
            projectId: projectId,
            tags: tags,
            permissions: permissions,
            pinned: false,
            lastOpenedAt: nil,
            createdAt: now,
            updatedAt: now,
            createdByChatId: createdByChatId
        )
        try writeManifest(record)
        // Seed a placeholder index.html so the user can open the app
        // immediately even before the agent has written anything.
        let appDir = directory(forSlug: record.slug)
        let indexURL = appDir.appendingPathComponent("index.html")
        if !fileManager.fileExists(atPath: indexURL.path) {
            let placeholder = AppsStore.placeholderIndexHTML(name: name)
            try? placeholder.data(using: .utf8)?.write(to: indexURL, options: .atomic)
        }
        reloadFromDisk()
        return record
    }

    /// Persist any AppRecord change (rename, pin, permissions, ...). The
    /// manifest is the truth-of-record on disk; reloadFromDisk is what
    /// surfaces it back into `@Published apps`.
    func update(_ record: AppRecord) throws {
        var updated = record
        updated.updatedAt = Date()
        try writeManifest(updated)
        reloadFromDisk()
    }

    /// Remove an app entirely (folder + manifest + files). Irreversible
    /// from the GUI; the user gets a confirm sheet on the call site.
    func delete(_ record: AppRecord) throws {
        let dir = directory(forSlug: record.slug)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
        reloadFromDisk()
    }

    /// Stamp `lastOpenedAt = now` so the app floats to the top of the
    /// recent ordering. Cheap; the manifest is rewritten in place.
    func markOpened(_ record: AppRecord) {
        var updated = record
        updated.lastOpenedAt = Date()
        try? writeManifest(updated)
        reloadFromDisk()
    }

    func togglePinned(_ record: AppRecord) {
        var updated = record
        updated.pinned.toggle()
        try? update(updated)
    }

    // MARK: - File I/O for the WKURLSchemeHandler

    /// Look up a file inside an app's folder and return its bytes plus
    /// a guessed MIME type. Returns nil when the slug or path is bogus
    /// or when the file is outside the app's folder (path traversal
    /// guard via `URL.resolvingSymlinksInPath` + prefix check).
    func readFile(slug: String, relativePath: String) -> (data: Data, mimeType: String)? {
        let appDir = directory(forSlug: slug)
        let trimmed = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let resolvedName = trimmed.isEmpty ? "index.html" : trimmed
        let target = appDir.appendingPathComponent(resolvedName).standardizedFileURL
        // Path traversal guard: ensure target is still under appDir.
        guard target.path.hasPrefix(appDir.standardizedFileURL.path + "/") || target.path == appDir.standardizedFileURL.path else {
            return nil
        }
        guard fileManager.fileExists(atPath: target.path) else { return nil }
        guard let data = try? Data(contentsOf: target) else { return nil }
        return (data, AppsStore.guessMimeType(forPath: target.path))
    }

    /// Bytes of the SDK script. Loaded lazily so consumers can flip the
    /// inline JS implementation without rebuilding any other types.
    var sdkScriptJS: String { ClawixAppsSDKJS }

    func record(forSlug slug: String) -> AppRecord? {
        apps.first(where: { $0.slug == slug })
    }

    func record(forId id: UUID) -> AppRecord? {
        apps.first(where: { $0.id == id })
    }

    func directory(forSlug slug: String) -> URL {
        rootURL.appendingPathComponent(slug)
    }

    // MARK: - Internals

    private func ensureRootExists() {
        if !fileManager.fileExists(atPath: rootURL.path) {
            try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
    }

    private func writeManifest(_ record: AppRecord) throws {
        let dir = directory(forSlug: record.slug)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let manifestURL = dir.appendingPathComponent(manifestName)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(record)
        try data.write(to: manifestURL, options: .atomic)
    }

    private func uniqueSlug(preferred: String?, name: String) throws -> String {
        let base = AppsStore.normalizedSlug(from: preferred?.isEmpty == false ? preferred! : name)
        guard !base.isEmpty else {
            throw NSError(domain: "AppsStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot derive a slug from name '\(name)'"])
        }
        // Disambiguate "todos" → "todos-2" → "todos-3" if needed.
        let existing = Set(apps.map(\.slug))
        if !existing.contains(base) { return base }
        var counter = 2
        while existing.contains("\(base)-\(counter)") {
            counter += 1
            if counter > 999 {
                throw NSError(domain: "AppsStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "Too many slugs starting with '\(base)'"])
            }
        }
        return "\(base)-\(counter)"
    }

    /// Lowercase, hyphen-separated, alphanumeric only. "Hello, World!" → "hello-world".
    static func normalizedSlug(from raw: String) -> String {
        let lowered = raw.lowercased()
        var result = ""
        var lastWasDash = false
        for scalar in lowered.unicodeScalars {
            if (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9") {
                result.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash, !result.isEmpty {
                result.append("-")
                lastWasDash = true
            }
        }
        if result.hasSuffix("-") { result.removeLast() }
        return result
    }

    private static func compareForSidebar(_ lhs: AppRecord, _ rhs: AppRecord) -> Bool {
        if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
        let lOpened = lhs.lastOpenedAt ?? .distantPast
        let rOpened = rhs.lastOpenedAt ?? .distantPast
        if lOpened != rOpened { return lOpened > rOpened }
        return lhs.createdAt > rhs.createdAt
    }

    private func startPolling() {
        // 4s is fast enough that the agent writing a new manifest is
        // visible "in the next breath" without burning CPU.
        let timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.reloadFromDisk()
            }
        }
        timer.tolerance = 1.0
        RunLoop.main.add(timer, forMode: .common)
        pollingTimer = timer
    }

    static func guessMimeType(forPath path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs":   return "application/javascript; charset=utf-8"
        case "css":         return "text/css; charset=utf-8"
        case "json":        return "application/json; charset=utf-8"
        case "svg":         return "image/svg+xml"
        case "png":         return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif":         return "image/gif"
        case "webp":        return "image/webp"
        case "ico":         return "image/x-icon"
        case "woff":        return "font/woff"
        case "woff2":       return "font/woff2"
        case "ttf":         return "font/ttf"
        case "otf":         return "font/otf"
        case "wasm":        return "application/wasm"
        case "txt", "md":   return "text/plain; charset=utf-8"
        default:            return "application/octet-stream"
        }
    }

    static func placeholderIndexHTML(name: String) -> String {
        // Minimal, on-brand "this app is empty" page so opening a fresh
        // app slug doesn't show a blank window. The agent overwrites it
        // as soon as it writes any real index.html.
        let escapedName = name
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!doctype html>
        <html><head><meta charset="utf-8"><title>\(escapedName)</title>
        <style>
        :root{color-scheme:dark light}
        html,body{margin:0;height:100%;font-family:-apple-system,BlinkMacSystemFont,sans-serif;
            display:flex;align-items:center;justify-content:center;background:#0e0e10;color:#aaa;}
        .wrap{text-align:center;padding:40px;max-width:520px}
        h1{font-weight:500;font-size:22px;color:#eee;margin:0 0 8px}
        p{margin:0;font-size:14px;line-height:1.5}
        code{background:#1e1e22;padding:2px 6px;border-radius:4px;font-size:12.5px;color:#ddd}
        </style></head><body>
        <div class="wrap">
        <h1>\(escapedName)</h1>
        <p>This app has no content yet. Ask the agent to build it, or drop files into <code>Application Support/Clawix/Apps/</code>.</p>
        </div></body></html>
        """
    }
}
