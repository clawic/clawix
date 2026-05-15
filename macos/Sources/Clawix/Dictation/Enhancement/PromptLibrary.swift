import Foundation

/// Prompt gallery for AI Enhancement. Each entry has a stable id
/// (hardcoded UUID for built-ins so import/export can identify them),
/// a visible title, and a system/user prompt pair.
///
/// Built-in entries cannot be deleted; the user can create additional
/// custom prompts that persist as framework-owned snippets. The active
/// prompt is stored as a UUID in `EnhancementSettings.activePromptKey`.
struct EnhancementPrompt: Identifiable, Codable, Equatable {
    let id: UUID
    /// `true` for built-in entries, which cannot be deleted or edited
    /// unless cloned. The user can still clone and modify them.
    var isBuiltIn: Bool
    var title: String
    var systemPrompt: String
    var userPrompt: String
}

@MainActor
final class PromptLibrary: ObservableObject {

    static let shared = PromptLibrary()

    nonisolated static let snippetKind = "dictation_enhancement_prompt"
    nonisolated static let slugPrefix = "dictation-enhancement-"

    @Published private(set) var prompts: [EnhancementPrompt]

    init() {
        var seed = Self.builtIns
        if let records = try? ClawJSFrameworkRecordsClient.shared.listSnippets(kind: Self.snippetKind) {
            seed.append(contentsOf: records.compactMap(Self.prompt(from:)))
        }
        self.prompts = seed
    }

    func prompt(byId id: UUID) -> EnhancementPrompt? {
        prompts.first(where: { $0.id == id })
    }

    /// Resolve the active prompt or fall back to the first built-in
    /// when the user hasn't picked one yet (or picked one that since
    /// got deleted).
    func activePrompt() -> EnhancementPrompt {
        let raw = UserDefaults.standard.string(forKey: EnhancementSettings.activePromptKey)
        if let raw, let id = UUID(uuidString: raw), let p = prompt(byId: id) {
            return p
        }
        return prompts.first ?? Self.fallback
    }

    func setActive(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: EnhancementSettings.activePromptKey)
    }

    @discardableResult
    func addCustom(title: String, systemPrompt: String, userPrompt: String) -> EnhancementPrompt {
        let entry = EnhancementPrompt(
            id: UUID(),
            isBuiltIn: false,
            title: title,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )
        prompts.append(entry)
        persistCustom()
        return entry
    }

    func update(_ entry: EnhancementPrompt) {
        guard let idx = prompts.firstIndex(where: { $0.id == entry.id }) else { return }
        // Built-in entries are immutable from the UI; ignore.
        guard !prompts[idx].isBuiltIn else { return }
        prompts[idx] = entry
        persistCustom()
    }

    func deleteCustom(_ id: UUID) {
        guard let entry = prompts.first(where: { $0.id == id }), !entry.isBuiltIn else { return }
        prompts.removeAll { $0.id == id }
        try? ClawJSFrameworkRecordsClient.shared.deleteSnippet(slug: "\(Self.slugPrefix)\(id.uuidString.lowercased())")
        persistCustom()
    }

    private func persistCustom() {
        let custom = prompts.filter { !$0.isBuiltIn }
        for prompt in custom {
            try? ClawJSFrameworkRecordsClient.shared.upsertSnippet(
                id: prompt.id.uuidString.lowercased(),
                slug: "\(Self.slugPrefix)\(prompt.id.uuidString.lowercased())",
                kind: Self.snippetKind,
                title: prompt.title,
                body: prompt.userPrompt,
                metadata: [
                    "systemPrompt": prompt.systemPrompt,
                    "isBuiltIn": "false",
                ]
            )
        }
    }

    private static func prompt(from record: ClawJSFrameworkRecordsClient.SnippetRecord) -> EnhancementPrompt? {
        let rawId = record.id.replacingOccurrences(of: "snippet-", with: "")
        guard let id = UUID(uuidString: rawId) else { return nil }
        return EnhancementPrompt(
            id: id,
            isBuiltIn: false,
            title: record.title,
            systemPrompt: record.metadata?["systemPrompt"] ?? "",
            userPrompt: record.body
        )
    }

    // MARK: - Built-ins

    /// Stable UUIDs so import/export can match across machines.
    static let builtIns: [EnhancementPrompt] = [
        EnhancementPrompt(
            id: UUID(uuidString: "11111111-0000-0000-0000-000000000001")!,
            isBuiltIn: true,
            title: "Clean up",
            systemPrompt: "You are a transcription cleanup assistant. Fix grammar, punctuation, and capitalization without changing meaning, voice, or word choice. Preserve the user's tone (casual, formal, technical) exactly.",
            userPrompt: "Clean up the transcript. Return only the cleaned text. Do not summarize. Do not add commentary."
        ),
        EnhancementPrompt(
            id: UUID(uuidString: "22222222-0000-0000-0000-000000000002")!,
            isBuiltIn: true,
            title: "Email",
            systemPrompt: "You turn dictated drafts into clean, professional emails. Keep the user's voice. No fake greetings or signatures unless dictated.",
            userPrompt: "Rewrite this transcript as a polished email body. Return only the email text."
        ),
        EnhancementPrompt(
            id: UUID(uuidString: "33333333-0000-0000-0000-000000000003")!,
            isBuiltIn: true,
            title: "Summary",
            systemPrompt: "You write tight bullet-point summaries that preserve every concrete fact in the source.",
            userPrompt: "Summarize the transcript as 3-6 short bullets. Return only the bullets."
        ),
        EnhancementPrompt(
            id: UUID(uuidString: "44444444-0000-0000-0000-000000000004")!,
            isBuiltIn: true,
            title: "Casual",
            systemPrompt: "You strip formality without losing accuracy. Keep contractions, drop hedges, keep first person.",
            userPrompt: "Rewrite the transcript in a relaxed, conversational tone. Return only the rewritten text."
        ),
        EnhancementPrompt(
            id: UUID(uuidString: "55555555-0000-0000-0000-000000000005")!,
            isBuiltIn: true,
            title: "Formal",
            systemPrompt: "You convert dictated speech into clear, formal prose. Avoid filler. Avoid hedges. Strict grammar.",
            userPrompt: "Rewrite the transcript in a formal register. Return only the rewritten text."
        ),
        EnhancementPrompt(
            id: UUID(uuidString: "66666666-0000-0000-0000-000000000006")!,
            isBuiltIn: true,
            title: "Code-friendly",
            systemPrompt: "You produce code-style text from spoken descriptions. Identifiers in camelCase or snake_case as appropriate. Code keywords (`func`, `let`, `if`, `return`, `nil`, `true`, `false`) verbatim.",
            userPrompt: "Rewrite the transcript so it reads as code-comment-grade text. Preserve any code symbols dictated. Return only the rewritten text."
        )
    ]

    static let fallback = builtIns[0]
}
