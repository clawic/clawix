import Foundation

/// Curated list of models the user can download from inside Clawix. Kept
/// short on purpose: the goal is "the canonical 12, in one place" rather
/// than a 4500-row mirror of upstream. Adding a model is one PR; the
/// metadata here drives display name, capability badges, and the size
/// hint shown next to the variant before the user commits to download.
///
/// Branding: never reference the upstream runtime by name. The
/// `provider` field is the model author (Meta, Mistral, Google,
/// Alibaba, …), not the runtime.
enum LocalModelsCatalog {

    static let entries: [Entry] = [
        Entry(
            id: "llama3.2",
            displayName: "Llama 3.2",
            provider: "Meta",
            description: "Compact general-purpose chat. Fast, runs comfortably on 8 GB devices.",
            variants: [
                Variant(tag: "1b", sizeGB: 1.3, recommendedRAMGB: 8),
                Variant(tag: "3b", sizeGB: 2.0, recommendedRAMGB: 8)
            ],
            capabilities: [.chat, .tools],
            license: "Llama 3.2 Community License"
        ),
        Entry(
            id: "llama3.1",
            displayName: "Llama 3.1",
            provider: "Meta",
            description: "Workhorse general-purpose chat with strong reasoning at 8B and beyond.",
            variants: [
                Variant(tag: "8b", sizeGB: 4.7, recommendedRAMGB: 16),
                Variant(tag: "70b", sizeGB: 40.0, recommendedRAMGB: 64)
            ],
            capabilities: [.chat, .tools],
            license: "Llama 3.1 Community License"
        ),
        Entry(
            id: "llama3.2-vision",
            displayName: "Llama 3.2 Vision",
            provider: "Meta",
            description: "Multimodal: accepts images alongside text prompts.",
            variants: [
                Variant(tag: "11b", sizeGB: 7.9, recommendedRAMGB: 16)
            ],
            capabilities: [.chat, .vision],
            license: "Llama 3.2 Community License"
        ),
        Entry(
            id: "qwen2.5",
            displayName: "Qwen 2.5",
            provider: "Alibaba",
            description: "Strong all-rounder, excellent for code and reasoning across languages.",
            variants: [
                Variant(tag: "7b", sizeGB: 4.7, recommendedRAMGB: 16),
                Variant(tag: "14b", sizeGB: 9.0, recommendedRAMGB: 24)
            ],
            capabilities: [.chat, .code, .tools],
            license: "Qwen License"
        ),
        Entry(
            id: "qwen2.5-coder",
            displayName: "Qwen 2.5 Coder",
            provider: "Alibaba",
            description: "Code-specialised variant of Qwen 2.5. Excellent for autocomplete and review.",
            variants: [
                Variant(tag: "7b", sizeGB: 4.7, recommendedRAMGB: 16),
                Variant(tag: "32b", sizeGB: 19.0, recommendedRAMGB: 48)
            ],
            capabilities: [.code, .tools],
            license: "Qwen License"
        ),
        Entry(
            id: "deepseek-r1",
            displayName: "DeepSeek R1",
            provider: "DeepSeek",
            description: "Reasoning-tuned model. Visibly slower per token because it thinks aloud first.",
            variants: [
                Variant(tag: "7b", sizeGB: 4.7, recommendedRAMGB: 16),
                Variant(tag: "14b", sizeGB: 9.0, recommendedRAMGB: 24),
                Variant(tag: "32b", sizeGB: 19.0, recommendedRAMGB: 48)
            ],
            capabilities: [.chat, .reasoning],
            license: "MIT"
        ),
        Entry(
            id: "mistral",
            displayName: "Mistral",
            provider: "Mistral AI",
            description: "Fast, capable 7B chat. A reliable default if you don't know what to pick.",
            variants: [
                Variant(tag: "7b", sizeGB: 4.1, recommendedRAMGB: 16)
            ],
            capabilities: [.chat, .tools],
            license: "Apache 2.0"
        ),
        Entry(
            id: "gemma2",
            displayName: "Gemma 2",
            provider: "Google",
            description: "Small, efficient chat model from Google. Strong at instruction following.",
            variants: [
                Variant(tag: "2b", sizeGB: 1.6, recommendedRAMGB: 8),
                Variant(tag: "9b", sizeGB: 5.4, recommendedRAMGB: 16)
            ],
            capabilities: [.chat],
            license: "Gemma Terms of Use"
        ),
        Entry(
            id: "phi3",
            displayName: "Phi-3",
            provider: "Microsoft",
            description: "Tiny but punchy. Excellent latency at 3.8B for short tasks on low-RAM machines.",
            variants: [
                Variant(tag: "3.8b", sizeGB: 2.3, recommendedRAMGB: 8),
                Variant(tag: "14b", sizeGB: 7.9, recommendedRAMGB: 16)
            ],
            capabilities: [.chat],
            license: "MIT"
        ),
        Entry(
            id: "llava",
            displayName: "LLaVA",
            provider: "LLaVA team",
            description: "Vision-language model. Describe images, answer questions about screenshots.",
            variants: [
                Variant(tag: "7b", sizeGB: 4.7, recommendedRAMGB: 16),
                Variant(tag: "13b", sizeGB: 8.0, recommendedRAMGB: 24)
            ],
            capabilities: [.chat, .vision],
            license: "Apache 2.0"
        ),
        Entry(
            id: "nomic-embed-text",
            displayName: "Nomic Embed Text",
            provider: "Nomic AI",
            description: "Text embeddings for search and RAG. Tiny, fast, and L2-normalised out of the box.",
            variants: [
                Variant(tag: "latest", sizeGB: 0.27, recommendedRAMGB: 4)
            ],
            capabilities: [.embedding],
            license: "Apache 2.0"
        )
    ]

    struct Entry: Identifiable, Hashable {
        let id: String
        let displayName: String
        let provider: String
        let description: String
        let variants: [Variant]
        let capabilities: Set<Capability>
        let license: String

        /// Default variant the UI surfaces first. Uses the smallest size,
        /// which is the safest bet for "user has no idea what to pick".
        var defaultVariant: Variant { variants.min(by: { $0.sizeGB < $1.sizeGB }) ?? variants[0] }
    }

    struct Variant: Hashable {
        /// Upstream tag (e.g. "8b", "latest"). Combined with `Entry.id`
        /// to form the pull name `<id>:<tag>`.
        let tag: String
        let sizeGB: Double
        let recommendedRAMGB: Int

        var sizeLabel: String {
            sizeGB < 1
                ? String(format: "%.0f MB", sizeGB * 1024)
                : String(format: "%.1f GB", sizeGB)
        }
    }

    enum Capability: String, CaseIterable, Hashable {
        case chat
        case code
        case vision
        case tools
        case embedding
        case reasoning

        var label: String {
            switch self {
            case .chat: return "Chat"
            case .code: return "Code"
            case .vision: return "Vision"
            case .tools: return "Tools"
            case .embedding: return "Embeddings"
            case .reasoning: return "Reasoning"
            }
        }
    }

    /// Combine an entry id with a variant tag to form the model name the
    /// daemon expects in `/api/pull` and friends.
    static func pullName(_ entry: Entry, variant: Variant) -> String {
        "\(entry.id):\(variant.tag)"
    }
}
