import Combine
import Foundation
import UIKit

/// iOS port of the editor document store. Same on-disk shape as the
/// desktop store (`~/.claw/design/documents/<id>/document.json`),
/// only difference is image dimension probing uses `UIImage` instead of
/// `NSImage`.
@MainActor
final class EditorStore: ObservableObject {
    static let shared = EditorStore()
    private static let frameworkRootName = ".claw"
    private static let designRootName = "design"
    private static let documentsRootName = "documents"

    @Published private(set) var documents: [EditorDocument] = []

    private let rootURL: URL
    private let fileManager: FileManager

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? EditorStore.defaultRootURL(fileManager: fileManager)
        ensureRootExists()
        reloadFromDisk()
    }

    static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(frameworkRootName, isDirectory: true)
            .appendingPathComponent(designRootName, isDirectory: true)
            .appendingPathComponent(documentsRootName, isDirectory: true)
    }

    func documentDir(for id: String) -> URL { rootURL.appendingPathComponent(id) }
    func documentManifestURL(for id: String) -> URL { documentDir(for: id).appendingPathComponent("document.json") }
    func document(id: String) -> EditorDocument? { documents.first(where: { $0.id == id }) }

    func reloadFromDisk() {
        ensureRootExists()
        guard let entries = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            documents = []
            return
        }
        var found: [EditorDocument] = []
        for entry in entries {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let manifestURL = entry.appendingPathComponent("document.json")
            guard fileManager.fileExists(atPath: manifestURL.path) else { continue }
            do {
                let data = try Data(contentsOf: manifestURL)
                let document = try JSONDecoder().decode(EditorDocument.self, from: data)
                found.append(document)
            } catch { continue }
        }
        documents = found.sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func create(name: String, template: TemplateManifest, styleId: String, variantId: String?) throws -> EditorDocument {
        let id = generateId(from: name)
        let now = isoNow()
        let document = EditorDocument(
            id: id,
            name: name,
            templateId: template.id,
            styleId: styleId,
            variantId: variantId ?? template.variants.first?.id,
            data: seedData(for: template),
            createdAt: now,
            updatedAt: now
        )
        try persist(document)
        reloadFromDisk()
        return document
    }

    func update(_ document: EditorDocument) throws {
        var updated = document
        updated.updatedAt = isoNow()
        try persist(updated)
        if let index = documents.firstIndex(where: { $0.id == document.id }) {
            documents[index] = updated
        } else {
            documents.append(updated)
        }
        documents.sort { $0.updatedAt > $1.updatedAt }
    }

    func delete(_ document: EditorDocument) throws {
        let dir = documentDir(for: document.id)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
        reloadFromDisk()
    }

    func storeAsset(sourceURL: URL, into document: EditorDocument, slotId: String) throws -> SlotAssetValue {
        let dir = documentDir(for: document.id)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = sourceURL.pathExtension.lowercased()
        let filename = "\(slotId).\(ext.isEmpty ? "asset" : ext)"
        let dest = dir.appendingPathComponent(filename)
        if fileManager.fileExists(atPath: dest.path) {
            try? fileManager.removeItem(at: dest)
        }
        try fileManager.copyItem(at: sourceURL, to: dest)
        var width: Double?
        var height: Double?
        if let data = try? Data(contentsOf: dest), let image = UIImage(data: data) {
            width = Double(image.size.width)
            height = Double(image.size.height)
        }
        return SlotAssetValue(filename: filename, width: width, height: height)
    }

    func storeAssetData(_ data: Data, ext: String, into document: EditorDocument, slotId: String) throws -> SlotAssetValue {
        let dir = documentDir(for: document.id)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let normalisedExt = ext.isEmpty ? "png" : ext.lowercased()
        let filename = "\(slotId).\(normalisedExt)"
        let dest = dir.appendingPathComponent(filename)
        try data.write(to: dest, options: .atomic)
        var width: Double?
        var height: Double?
        if let image = UIImage(data: data) {
            width = Double(image.size.width)
            height = Double(image.size.height)
        }
        return SlotAssetValue(filename: filename, width: width, height: height)
    }

    func assetURL(for document: EditorDocument, value: SlotAssetValue) -> URL {
        documentDir(for: document.id).appendingPathComponent(value.filename)
    }

    private func persist(_ document: EditorDocument) throws {
        let dir = documentDir(for: document.id)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        try data.write(to: documentManifestURL(for: document.id), options: .atomic)
    }

    private func seedData(for template: TemplateManifest) -> [String: SlotValue] {
        var out: [String: SlotValue] = [:]
        for slot in template.slots {
            switch slot.kind {
            case .list:
                let n = max(2, min(slot.maxItems ?? 3, 3))
                out[slot.id] = .items((1...n).map { "Item \($0)" })
            case .image, .logo:
                out[slot.id] = .empty
            case .divider, .shape:
                out[slot.id] = .empty
            case .heading, .subheading, .body, .quote, .metric, .button, .table:
                out[slot.id] = .text(seedText(for: slot))
            }
        }
        return out
    }

    private func seedText(for slot: TemplateSlot) -> String {
        switch slot.kind {
        case .heading:    return slot.placeholder ?? slot.label
        case .subheading: return slot.placeholder ?? slot.label
        case .body:       return slot.placeholder ?? "Body copy. Edit to match the story you want this piece to tell."
        case .quote:      return slot.placeholder ?? "Pick a line that earns the whole canvas."
        case .metric:     return slot.placeholder ?? "0"
        case .button:     return slot.placeholder ?? slot.label
        case .table:      return slot.placeholder ?? "Column A | Column B"
        default:          return slot.placeholder ?? slot.label
        }
    }

    private func ensureRootExists() {
        if !fileManager.fileExists(atPath: rootURL.path) {
            try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
    }

    private func generateId(from name: String) -> String {
        let slug = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .prefix(40)
        let suffix = String(UUID().uuidString.split(separator: "-").first ?? "0000").lowercased().prefix(4)
        return "\(slug.isEmpty ? "doc" : String(slug))-\(suffix)"
    }

    private func isoNow() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
