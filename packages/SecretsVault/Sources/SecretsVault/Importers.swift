import Foundation
import SecretsModels

public struct ImportPreview: Sendable, Hashable {
    public let drafts: [DraftSecret]
    public let warnings: [String]
    public let format: String

    public init(drafts: [DraftSecret], warnings: [String], format: String) {
        self.drafts = drafts
        self.warnings = warnings
        self.format = format
    }
}

public enum ImportError: Swift.Error, CustomStringConvertible {
    case empty
    case unrecognizedFormat(String)
    case malformed(String)

    public var description: String {
        switch self {
        case .empty: return "The input file is empty."
        case .unrecognizedFormat(let s): return "Unrecognized format: \(s)"
        case .malformed(let s): return "Malformed input: \(s)"
        }
    }
}

// MARK: - 1Password CSV

public enum OnePasswordCSVImporter {

    public static func parse(_ text: String) throws -> ImportPreview {
        let rows = CSVParser.parse(text)
        guard rows.count >= 2 else { throw ImportError.empty }
        let header = rows[0].map { $0.lowercased() }
        let titleIdx = header.firstIndex { $0 == "title" || $0 == "name" }
        let userIdx = header.firstIndex { $0 == "username" || $0 == "user" || $0 == "login_username" }
        let passIdx = header.firstIndex { $0 == "password" || $0 == "login_password" }
        let urlIdx = header.firstIndex { $0 == "url" || $0 == "website" || $0 == "login_uri" }
        let notesIdx = header.firstIndex { $0 == "notes" || $0 == "notesplain" }
        let otpIdx = header.firstIndex { $0 == "one-time password" || $0 == "otp" || $0 == "login_totp" }

        guard titleIdx != nil else {
            throw ImportError.unrecognizedFormat("expected a 'Title' or 'Name' column")
        }

        var drafts: [DraftSecret] = []
        var warnings: [String] = []
        for (lineNumber, row) in rows.dropFirst().enumerated() where !row.allSatisfy({ $0.isEmpty }) {
            let title = (titleIdx.flatMap { row[safe: $0] }) ?? "Imported"
            let internalName = OnePasswordCSVImporter.slug(title)
            var fields: [DraftField] = []
            if let i = userIdx, let v = row[safe: i], !v.isEmpty {
                fields.append(DraftField(name: "username", fieldKind: .text, placement: .none, isSecret: false, isConcealed: false, publicValue: v, sortOrder: 0))
            }
            if let i = passIdx, let v = row[safe: i], !v.isEmpty {
                fields.append(DraftField(name: "password", fieldKind: .password, placement: .none, isSecret: true, secretValue: v, sortOrder: 1))
            }
            if let i = urlIdx, let v = row[safe: i], !v.isEmpty {
                fields.append(DraftField(name: "url", fieldKind: .url, placement: .none, isSecret: false, isConcealed: false, publicValue: v, sortOrder: 2))
            }
            if let i = otpIdx, let v = row[safe: i], !v.isEmpty {
                fields.append(DraftField(name: "otp", fieldKind: .otp, placement: .none, isSecret: true, secretValue: v, otpPeriod: 30, otpDigits: 6, otpAlgorithm: .sha1, sortOrder: 3))
            }
            let notesValue = notesIdx.flatMap { row[safe: $0] }.flatMap { $0.isEmpty ? nil : $0 }
            if fields.isEmpty {
                warnings.append("row \(lineNumber + 2) has no recognized fields, skipped")
                continue
            }
            let kind: SecretKind = (passIdx != nil ? .passwordLogin : .secureNote)
            let draft = DraftSecret(
                kind: kind,
                internalName: internalName,
                title: title.isEmpty ? "Imported" : title,
                fields: fields,
                notes: notesValue
            )
            drafts.append(draft)
        }
        return ImportPreview(drafts: drafts, warnings: warnings, format: "1Password CSV")
    }

    static func slug(_ title: String) -> String {
        let lower = title.lowercased()
        var output = ""
        var lastWasSep = false
        for ch in lower {
            if ch.isLetter || ch.isNumber {
                output.append(ch)
                lastWasSep = false
            } else if !lastWasSep {
                output.append("_")
                lastWasSep = true
            }
        }
        if output.first == "_" { output.removeFirst() }
        if output.last == "_" { output.removeLast() }
        if output.isEmpty { return "imported_\(Int(Date().timeIntervalSince1970))" }
        return output
    }
}

// MARK: - Bitwarden CSV

public enum BitwardenCSVImporter {

    public static func parse(_ text: String) throws -> ImportPreview {
        let rows = CSVParser.parse(text)
        guard rows.count >= 2 else { throw ImportError.empty }
        let header = rows[0].map { $0.lowercased() }
        // Bitwarden header is stable; require the canonical columns we use.
        guard let nameIdx = header.firstIndex(of: "name") else {
            throw ImportError.unrecognizedFormat("Bitwarden CSV must have a 'name' column")
        }
        let typeIdx = header.firstIndex(of: "type")
        let folderIdx = header.firstIndex(of: "folder")
        let notesIdx = header.firstIndex(of: "notes")
        let userIdx = header.firstIndex(of: "login_username")
        let passIdx = header.firstIndex(of: "login_password")
        let uriIdx = header.firstIndex(of: "login_uri")
        let totpIdx = header.firstIndex(of: "login_totp")
        let fieldsIdx = header.firstIndex(of: "fields")

        var drafts: [DraftSecret] = []
        var warnings: [String] = []
        for (lineNumber, row) in rows.dropFirst().enumerated() where !row.allSatisfy({ $0.isEmpty }) {
            let name = (row[safe: nameIdx]) ?? ""
            let type = typeIdx.flatMap { row[safe: $0] } ?? "login"
            let folder = folderIdx.flatMap { row[safe: $0] }
            let notes = notesIdx.flatMap { row[safe: $0] }.flatMap { $0.isEmpty ? nil : $0 }
            let internalName = OnePasswordCSVImporter.slug(name.isEmpty ? "imported" : name)
            var fields: [DraftField] = []
            var sort = 0
            if type.lowercased() == "login" {
                if let i = userIdx, let v = row[safe: i], !v.isEmpty {
                    fields.append(DraftField(name: "username", fieldKind: .text, placement: .none, isSecret: false, isConcealed: false, publicValue: v, sortOrder: sort)); sort += 1
                }
                if let i = passIdx, let v = row[safe: i], !v.isEmpty {
                    fields.append(DraftField(name: "password", fieldKind: .password, placement: .none, isSecret: true, secretValue: v, sortOrder: sort)); sort += 1
                }
                if let i = uriIdx, let v = row[safe: i], !v.isEmpty {
                    fields.append(DraftField(name: "url", fieldKind: .url, placement: .none, isSecret: false, isConcealed: false, publicValue: v, sortOrder: sort)); sort += 1
                }
                if let i = totpIdx, let v = row[safe: i], !v.isEmpty {
                    fields.append(DraftField(name: "otp", fieldKind: .otp, placement: .none, isSecret: true, secretValue: v, otpPeriod: 30, otpDigits: 6, otpAlgorithm: .sha1, sortOrder: sort)); sort += 1
                }
            }
            // Bitwarden's `fields` column packs additional custom fields as
            // `name: value\nname: value`. Best-effort split; values get
            // imported as concealed secret fields by default.
            if let i = fieldsIdx, let v = row[safe: i], !v.isEmpty {
                for line in v.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
                    let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                    guard parts.count == 2 else { continue }
                    let fname = parts[0].trimmingCharacters(in: .whitespaces)
                    let fvalue = parts[1].trimmingCharacters(in: .whitespaces)
                    guard !fname.isEmpty, !fvalue.isEmpty else { continue }
                    fields.append(DraftField(
                        name: fname,
                        fieldKind: .password,
                        placement: .none,
                        isSecret: true,
                        secretValue: fvalue,
                        sortOrder: sort
                    ))
                    sort += 1
                }
            }
            if fields.isEmpty && (notes?.isEmpty ?? true) {
                warnings.append("row \(lineNumber + 2) has no recognized data, skipped")
                continue
            }
            let kind: SecretKind = (type.lowercased() == "note") ? .secureNote : .passwordLogin
            var draft = DraftSecret(
                kind: kind,
                internalName: internalName,
                title: name.isEmpty ? "Imported" : name,
                fields: fields,
                notes: notes
            )
            if let folder, !folder.isEmpty {
                draft.tags = [folder]
            }
            drafts.append(draft)
        }
        return ImportPreview(drafts: drafts, warnings: warnings, format: "Bitwarden CSV")
    }
}

// MARK: - .env file

public enum EnvFileImporter {

    public static func parse(_ text: String) throws -> ImportPreview {
        var drafts: [DraftSecret] = []
        var warnings: [String] = []
        for (lineNumber, raw) in text.split(whereSeparator: { $0.isNewline }).enumerated() {
            var line = String(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") {
                line.removeFirst("export ".count)
            }
            guard let eq = line.firstIndex(of: "=") else {
                warnings.append("line \(lineNumber + 1): no '=' separator, skipped")
                continue
            }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if (value.hasPrefix("\"") && value.hasSuffix("\""))
                || (value.hasPrefix("'") && value.hasSuffix("'"))
            {
                value = String(value.dropFirst().dropLast())
            }
            if key.isEmpty { continue }
            let upperKey = key.uppercased()
            let isApiLikely = upperKey.contains("KEY") || upperKey.contains("TOKEN") || upperKey.contains("SECRET") || upperKey.contains("PASS") || upperKey.contains("API")
            let kind: SecretKind = isApiLikely ? .apiKey : .secureNote
            let fieldName = isApiLikely ? "token" : "value"
            let draft = DraftSecret(
                kind: kind,
                internalName: OnePasswordCSVImporter.slug(key),
                title: key,
                fields: [
                    DraftField(name: fieldName, fieldKind: .password, placement: .env, isSecret: true, secretValue: value, sortOrder: 0)
                ]
            )
            drafts.append(draft)
        }
        if drafts.isEmpty { throw ImportError.empty }
        return ImportPreview(drafts: drafts, warnings: warnings, format: ".env file")
    }
}

// MARK: - helpers

extension Array {
    fileprivate subscript(safe index: Int?) -> Element? {
        guard let index, indices.contains(index) else { return nil }
        return self[index]
    }
}
