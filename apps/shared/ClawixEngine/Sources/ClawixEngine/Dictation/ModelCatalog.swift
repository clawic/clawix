import Foundation

/// Static catalog of Whisper variants Clawix exposes through the
/// dictation flow at launch. Adding a new entry here is enough for it
/// to show up in Settings; no plumbing changes required as long as the
/// variant name resolves against `argmaxinc/whisperkit-coreml` on the
/// Hugging Face Hub.
public enum DictationModel: String, CaseIterable, Codable, Sendable {
    /// Distilled, multilingual, ~1.5 GB on disk. Turbo is 6-8x faster
    /// than `largeV3` on Apple Silicon while keeping enough quality
    /// for general dictation. Default for new installs.
    case largeV3Turbo = "large-v3-turbo"
    /// Full Whisper Large V3, ~3 GB. Slower; use when transcription
    /// quality matters more than latency or storage.
    case largeV3 = "large-v3"

    public static let `default`: DictationModel = .largeV3Turbo

    /// Display name used in the Settings model picker.
    public var displayName: String {
        switch self {
        case .largeV3Turbo: return "Whisper Large V3 Turbo"
        case .largeV3:      return "Whisper Large V3"
        }
    }

    /// Approximate disk footprint of the variant in bytes. Read off
    /// the WhisperKit model card; used only to render a "1.5 GB" hint
    /// next to each row, not as a hard quota.
    public var approximateBytes: Int64 {
        switch self {
        case .largeV3Turbo: return 1_500_000_000
        case .largeV3:      return 3_000_000_000
        }
    }

    /// Variant slug WhisperKit passes to `Hub` when downloading. The
    /// download API does the prefixing to `openai_whisper-...` itself.
    public var whisperKitVariant: String { rawValue }
}
