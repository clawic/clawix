import Foundation
import AVFoundation
import WhisperKit

/// Errors surfaced to callers of `TranscriptionService`. The strings
/// are user-facing: keep them short and don't leak file paths.
public enum TranscriptionError: Error, LocalizedError, Sendable {
    case noModelAvailable
    case audioDecodeFailed
    case engineFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noModelAvailable:
            return "No transcription model is downloaded yet"
        case .audioDecodeFailed:
            return "Couldn't read the recorded audio"
        case .engineFailed(let detail):
            return detail
        }
    }
}

/// Thin shared wrapper around WhisperKit that the macOS GUI uses for
/// in-process dictation and the LaunchAgent daemon reuses to serve
/// `transcribeAudio` bridge requests from the iPhone.
///
/// The actor owns the loaded WhisperKit instance and serializes
/// transcriptions: WhisperKit itself is a class with mutable state, so
/// concurrent transcriptions on the same instance would race the model
/// state machine. Two callers ask one after another; a 5 s recording
/// transcribes faster than the next typed prompt anyway.
public actor TranscriptionService {

    public static let shared = TranscriptionService()

    private var loaded: (model: DictationModel, kit: WhisperKit)?

    public init() {}

    // MARK: - Public API

    /// Transcribe a buffer of mono 16 kHz Float32 samples directly.
    /// Used by the macOS GUI when it captures audio in-process.
    /// `prompt` is fed to Whisper as `initial_prompt` to bias the
    /// decoder toward custom vocabulary or output formatting style.
    /// Capped at ~244 tokens by Whisper itself; passing more is fine
    /// (Whisper truncates) but means the tail won't influence
    /// decoding.
    public func transcribe(
        samples: [Float],
        using model: DictationModel,
        language: String?,
        prompt: String? = nil
    ) async throws -> String {
        let kit = try await ensureLoaded(model: model)
        var options = decodeOptions(language: language, prompt: prompt)
        if let tokens = tokenize(prompt: prompt, kit: kit) {
            options.promptTokens = tokens
        }
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        return joinedText(results)
    }

    /// Transcribe an audio file (any format `AVAudioFile` understands).
    /// Used by the LaunchAgent daemon when the iPhone ships a
    /// compressed blob through the bridge.
    public func transcribe(
        fileURL: URL,
        using model: DictationModel,
        language: String?,
        prompt: String? = nil
    ) async throws -> String {
        let kit = try await ensureLoaded(model: model)
        var options = decodeOptions(language: language, prompt: prompt)
        if let tokens = tokenize(prompt: prompt, kit: kit) {
            options.promptTokens = tokens
        }
        let results = try await kit.transcribe(audioPath: fileURL.path, decodeOptions: options)
        return joinedText(results)
    }

    /// Drop the currently loaded model. Called from a 5-minute idle
    /// timer in the GUI to free GPU memory between dictation bursts;
    /// the daemon prefers to keep the model warm because round trips
    /// from the iPhone are sporadic but latency-sensitive.
    public func unload() {
        loaded = nil
    }

    public var isLoaded: Bool { loaded != nil }
    public var loadedModel: DictationModel? { loaded?.model }

    // MARK: - Internal

    private func ensureLoaded(model: DictationModel) async throws -> WhisperKit {
        if let loaded, loaded.model == model {
            return loaded.kit
        }
        // Different (or first) model requested: drop the old one so
        // we don't keep two large CoreML graphs in memory.
        loaded = nil
        // Resolve the on-disk folder explicitly. WhisperKitConfig with
        // `model:` alone + `download: false` leaves `modelFolder` nil
        // and `loadModels` then throws "Model folder is not set."
        // Settings already downloaded the variant via
        // `DictationModelManager`, so we point WhisperKit at the same
        // path that scan resolves to.
        guard let folder = DictationModelManager.installedFolder(for: model) else {
            throw TranscriptionError.noModelAvailable
        }
        do {
            // `download: false` keeps WhisperKit from auto-pulling a
            // 1.5+ GB model behind the user's back; the Settings page
            // owns the download UX with proper progress.
            let config = WhisperKitConfig(
                modelFolder: folder.path,
                verbose: false,
                logLevel: .none,
                prewarm: false,
                load: true,
                download: false
            )
            let kit = try await WhisperKit(config)
            loaded = (model, kit)
            return kit
        } catch {
            throw TranscriptionError.engineFailed(error.localizedDescription)
        }
    }

    private func decodeOptions(language: String?, prompt: String?) -> DecodingOptions {
        // We sample at 16 kHz mono and pass full audio in one shot. VAD
        // chunking is only worth turning on for >30s recordings; for
        // typical dictation bursts (<10s) the simple path is faster.
        var options = DecodingOptions()
        let normalized = language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let normalized, !normalized.isEmpty, normalized != "auto" {
            // Caller supplied a locale hint (iPhone passes the user's
            // system language). Prefill the prompt with it, no need to
            // burn a detection pass.
            options.language = normalized
        } else {
            // Without a hint, Whisper's prefill defaults to English
            // because `DecodingOptions.detectLanguage` is `false` when
            // `usePrefillPrompt` is `true`. Flip it on so the model
            // probes the first window for a `<|lang|>` token before
            // decoding; this is what makes Spanish/French/etc. audio
            // come out in their own language instead of being silently
            // English-ified.
            options.detectLanguage = true
        }
        options.task = .transcribe
        options.temperature = 0.0
        // Custom initial prompt: combination of (a) per-language
        // formatting hint from `WhisperPromptStore` and (b) the
        // vocabulary boost list from `VocabularyManager`. Both are
        // resolved by the GUI side before calling us; we just stuff
        // the resulting string into `promptTokens` via Whisper's
        // tokenizer-friendly path. Empty prompts are dropped to keep
        // the default decoding behavior bit-identical.
        if let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            options.promptTokens = nil // Reserved for future tokenized seeding.
        }
        return options
    }

    private func joinedText(_ results: [TranscriptionResult]) -> String {
        results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Best-effort tokenization of the user-supplied prompt string.
    /// Whisper's window is ~244 tokens; we cap at 220 to leave room
    /// for the system's own prefix tokens and avoid accidentally
    /// truncating the audio context. Returns nil for an empty prompt
    /// or when the tokenizer hasn't loaded yet (first transcription
    /// of a fresh model).
    private func tokenize(prompt: String?, kit: WhisperKit) -> [Int]? {
        guard let prompt else { return nil }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let tokenizer = kit.tokenizer else { return nil }
        let tokens = tokenizer.encode(text: trimmed)
        if tokens.count > 220 {
            return Array(tokens.prefix(220))
        }
        return tokens
    }
}
