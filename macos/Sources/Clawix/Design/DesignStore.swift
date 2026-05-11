import AppKit
import Combine
import Foundation

/// Single source of truth for the design system surfaced by Clawix:
/// Styles, Templates and References. Each resource lives as its own
/// directory under `~/Library/Application Support/Clawix/Design/` so
/// the agent (which can be any process writing files there) and the
/// GUI share a contract: write a `STYLE.md` / `TEMPLATE.md` /
/// `REFERENCE.md` and the sidebar picks it up.
///
/// File layout:
/// ```
/// Design/
///   styles/<id>/STYLE.md
///   templates/<id>/TEMPLATE.md
///   references/<id>/REFERENCE.md
/// ```
@MainActor
final class DesignStore: ObservableObject {
    static let shared = DesignStore()

    @Published private(set) var styles: [StyleManifest] = []
    @Published private(set) var templates: [TemplateManifest] = []
    @Published private(set) var references: [ReferenceManifest] = []

    private let rootURL: URL
    private let fileManager: FileManager
    private var pollingTimer: Timer?

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? DesignStore.defaultRootURL(fileManager: fileManager)
        ensureLayoutExists()
        seedBuiltinsIfNeeded()
        reloadFromDisk()
        startPolling()
    }

    deinit {
        pollingTimer?.invalidate()
    }

    static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        let support = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("Clawix")
            .appendingPathComponent("Design")
    }

    var stylesRootURL: URL { rootURL.appendingPathComponent("styles") }
    var templatesRootURL: URL { rootURL.appendingPathComponent("templates") }
    var referencesRootURL: URL { rootURL.appendingPathComponent("references") }

    // MARK: - Public lookups

    func style(id: String) -> StyleManifest? {
        styles.first(where: { $0.id == id })
    }

    func template(id: String) -> TemplateManifest? {
        templates.first(where: { $0.id == id })
    }

    func reference(id: String) -> ReferenceManifest? {
        references.first(where: { $0.id == id })
    }

    func templatesByCategory() -> [(TemplateCategory, [TemplateManifest])] {
        var bucket: [TemplateCategory: [TemplateManifest]] = [:]
        for template in templates {
            bucket[template.category, default: []].append(template)
        }
        return TemplateCategory.allCases
            .compactMap { category -> (TemplateCategory, [TemplateManifest])? in
                guard let list = bucket[category], !list.isEmpty else { return nil }
                return (category, list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
            }
    }

    // MARK: - Refresh

    func reloadFromDisk() {
        styles = readAllStyles()
        templates = readAllTemplates()
        references = readAllReferences()
    }

    // MARK: - Internals

    private func ensureLayoutExists() {
        for dir in [stylesRootURL, templatesRootURL, referencesRootURL] {
            if !fileManager.fileExists(atPath: dir.path) {
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    private func seedBuiltinsIfNeeded() {
        if (try? fileManager.contentsOfDirectory(atPath: stylesRootURL.path))?.isEmpty == true {
            for manifest in DesignBuiltins.styles() {
                try? writeStyle(manifest)
            }
        }
        if (try? fileManager.contentsOfDirectory(atPath: templatesRootURL.path))?.isEmpty == true {
            for manifest in DesignBuiltins.templates() {
                try? writeTemplate(manifest)
            }
        }
    }

    private func readAllStyles() -> [StyleManifest] {
        guard let entries = try? fileManager.contentsOfDirectory(at: stylesRootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        var out: [StyleManifest] = []
        for entry in entries {
            let manifestPath = entry.appendingPathComponent("STYLE.md")
            guard let content = try? String(contentsOf: manifestPath, encoding: .utf8) else { continue }
            if let manifest = try? DesignSerializer.parseStyle(content) {
                out.append(manifest)
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func readAllTemplates() -> [TemplateManifest] {
        guard let entries = try? fileManager.contentsOfDirectory(at: templatesRootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        var out: [TemplateManifest] = []
        for entry in entries {
            let manifestPath = entry.appendingPathComponent("TEMPLATE.md")
            guard let content = try? String(contentsOf: manifestPath, encoding: .utf8) else { continue }
            if let manifest = try? DesignSerializer.parseTemplate(content) {
                out.append(manifest)
            }
        }
        return out
    }

    private func readAllReferences() -> [ReferenceManifest] {
        guard let entries = try? fileManager.contentsOfDirectory(at: referencesRootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        var out: [ReferenceManifest] = []
        for entry in entries {
            let manifestPath = entry.appendingPathComponent("REFERENCE.md")
            guard let content = try? String(contentsOf: manifestPath, encoding: .utf8) else { continue }
            if let manifest = try? DesignSerializer.parseReference(content) {
                out.append(manifest)
            }
        }
        return out.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func writeStyle(_ manifest: StyleManifest) throws {
        let dir = stylesRootURL.appendingPathComponent(manifest.id)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload = try DesignSerializer.writeStyle(manifest)
        try payload.data(using: .utf8)?.write(to: dir.appendingPathComponent("STYLE.md"), options: .atomic)
    }

    private func writeTemplate(_ manifest: TemplateManifest) throws {
        let dir = templatesRootURL.appendingPathComponent(manifest.id)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload = try DesignSerializer.writeTemplate(manifest)
        try payload.data(using: .utf8)?.write(to: dir.appendingPathComponent("TEMPLATE.md"), options: .atomic)
    }

    private func startPolling() {
        let timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.reloadFromDisk()
            }
        }
        timer.tolerance = 1.0
        RunLoop.main.add(timer, forMode: .common)
        pollingTimer = timer
    }
}
