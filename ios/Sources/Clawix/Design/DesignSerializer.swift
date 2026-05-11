import Foundation

/// Parses and writes the canonical `STYLE.md` / `TEMPLATE.md` / `REFERENCE.md`
/// file shape used by the ClawJS framework. The shape is a JSON
/// frontmatter block delimited by `---json` ... `---` fences, followed by
/// a Markdown body that holds prose sections (Voice, Do/Don't, Glossary).
enum DesignSerializer {
    static let frontmatterOpen = "---json"
    static let frontmatterClose = "---"

    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static func parseStyle(_ content: String) throws -> StyleManifest {
        let (frontmatter, body) = try splitFrontmatter(content)
        guard let data = frontmatter.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "STYLE.md frontmatter is not valid UTF-8"))
        }
        var manifest = try jsonDecoder.decode(StyleManifest.self, from: data)
        let sections = parseMarkdownSections(body)
        if manifest.brand == nil, !sections.isEmpty {
            manifest.brand = StyleBrand()
        }
        if let voice = sections["voice"] {
            var brand = manifest.brand ?? StyleBrand()
            brand.voice = voice
            manifest.brand = brand
        }
        if let doDont = sections["do / don't"] ?? sections["do/don't"] {
            var brand = manifest.brand ?? StyleBrand()
            brand.doDont = doDont
            manifest.brand = brand
        }
        if let glossary = sections["glossary"] {
            var brand = manifest.brand ?? StyleBrand()
            brand.glossary = glossary
            manifest.brand = brand
        }
        return manifest
    }

    static func parseTemplate(_ content: String) throws -> TemplateManifest {
        let (frontmatter, _) = try splitFrontmatter(content)
        guard let data = frontmatter.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "TEMPLATE.md frontmatter is not valid UTF-8"))
        }
        return try jsonDecoder.decode(TemplateManifest.self, from: data)
    }

    static func parseReference(_ content: String) throws -> ReferenceManifest {
        let (frontmatter, _) = try splitFrontmatter(content)
        guard let data = frontmatter.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "REFERENCE.md frontmatter is not valid UTF-8"))
        }
        return try jsonDecoder.decode(ReferenceManifest.self, from: data)
    }

    static func writeStyle(_ manifest: StyleManifest) throws -> String {
        try writeWithBody(encoding: manifest) { body in
            var sections: [String] = []
            sections.append("# \(manifest.name)")
            if let desc = manifest.description, !desc.isEmpty {
                sections.append(desc)
            }
            if let voice = manifest.brand?.voice, !voice.isEmpty {
                sections.append("## Voice")
                sections.append(voice)
            }
            if let dd = manifest.brand?.doDont, !dd.isEmpty {
                sections.append("## Do / Don't")
                sections.append(dd)
            }
            if let glossary = manifest.brand?.glossary, !glossary.isEmpty {
                sections.append("## Glossary")
                sections.append(glossary)
            }
            body = sections.joined(separator: "\n\n")
        }
    }

    static func writeTemplate(_ manifest: TemplateManifest) throws -> String {
        try writeWithBody(encoding: manifest) { body in
            body = "# \(manifest.name)\n\n\(manifest.description ?? "")".trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    static func writeReference(_ manifest: ReferenceManifest) throws -> String {
        try writeWithBody(encoding: manifest) { body in
            body = "# \(manifest.name)\n\n\(manifest.description ?? "")".trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // MARK: - Internal

    private static func writeWithBody<T: Encodable>(encoding manifest: T, body: (inout String) -> Void) throws -> String {
        let data = try jsonEncoder.encode(manifest)
        guard let frontmatter = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(manifest, .init(codingPath: [], debugDescription: "Failed to encode manifest as UTF-8 JSON"))
        }
        var bodyOut = ""
        body(&bodyOut)
        return "\(frontmatterOpen)\n\(frontmatter)\n\(frontmatterClose)\n\n\(bodyOut)\n"
    }

    private static func splitFrontmatter(_ content: String) throws -> (frontmatter: String, body: String) {
        let stripped = content.hasPrefix("\u{FEFF}") ? String(content.dropFirst()) : content
        guard stripped.hasPrefix(frontmatterOpen) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Manifest must begin with '\(frontmatterOpen)' fence"))
        }
        let afterOpen = String(stripped.dropFirst(frontmatterOpen.count))
        guard let newlineRange = afterOpen.range(of: "\n") else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Frontmatter fence missing newline"))
        }
        let fromBody = afterOpen[newlineRange.upperBound...]
        guard let closeRange = fromBody.range(of: "\n\(frontmatterClose)") else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Missing closing '\(frontmatterClose)' fence"))
        }
        let frontmatter = String(fromBody[..<closeRange.lowerBound])
        var body = String(fromBody[closeRange.upperBound...])
        if body.hasPrefix(frontmatterClose) {
            body = String(body.dropFirst(frontmatterClose.count))
        }
        return (frontmatter, body.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func parseMarkdownSections(_ body: String) -> [String: String] {
        var sections: [String: String] = [:]
        if body.isEmpty { return sections }
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var currentTitle: String?
        var buffer: [String] = []
        for line in lines {
            if line.hasPrefix("## ") {
                if let title = currentTitle {
                    sections[title.lowercased()] = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                currentTitle = String(line.dropFirst(3))
                buffer = []
            } else if currentTitle != nil {
                buffer.append(line)
            }
        }
        if let title = currentTitle {
            sections[title.lowercased()] = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return sections
    }
}
