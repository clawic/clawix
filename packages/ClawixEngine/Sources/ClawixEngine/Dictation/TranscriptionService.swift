import Foundation
import AVFoundation
import WhisperKit

/// Joined text + the per-segment timing windows the auto-format
/// pass walks to insert paragraph breaks at silence boundaries.
public struct SegmentedTranscript: Sendable {
    public struct Segment: Sendable {
        public let text: String
        public let start: Float
        public let end: Float
    }
    public let text: String
    public let segments: [Segment]
}

/// Errors surfaced to callers of `TranscriptionService`. The strings
/// are user-facing: keep them short and don't leak file paths.
public enum TranscriptionError: Error, LocalizedError, Sendable {
    case noModelAvailable
    case audioDecodeFailed
    case engineFailed(String)
    /// On-disk WhisperKit folder is present but partial / corrupt.
    /// We've already wiped it so the next press re-downloads cleanly;
    /// the message points the user at Settings to start that fetch.
    case modelIncomplete(DictationModel)

    public var errorDescription: String? {
        switch self {
        case .noModelAvailable:
            return "No transcription model is downloaded yet"
        case .audioDecodeFailed:
            return "Couldn't read the recorded audio"
        case .engineFailed(let detail):
            return detail
        case .modelIncomplete(let model):
            return "\(model.displayName) didn't finish downloading. Open Settings → Voice to Text and tap Download to retry."
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
        prompt: String? = nil,
        useVAD: Bool = false
    ) async throws -> String {
        if let fixture = try Self.e2eFixtureText(useVAD: useVAD, permissive: false) {
            return fixture
        }
        let kit = try await ensureLoaded(model: model)
        var options = decodeOptions(language: language, prompt: prompt)
        if useVAD {
            options.chunkingStrategy = .vad
        }
        if let tokens = tokenize(prompt: prompt, kit: kit) {
            options.promptTokens = tokens
        }
        Self.trace("transcribe: samples=\(samples.count) language=\(options.language ?? "auto") detect=\(options.detectLanguage) vad=\(useVAD)")
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        Self.trace("transcribe: results.count=\(results.count) firstText=\"\(results.first?.text.prefix(80) ?? "")\" segments=\(results.first?.segments.count ?? -1) detectedLang=\(results.first?.language ?? "?")")
        if let first = results.first {
            for (idx, seg) in first.segments.prefix(3).enumerated() {
                Self.trace("  seg[\(idx)] text=\"\(seg.text)\" start=\(seg.start) end=\(seg.end) tokens=\(seg.tokens.prefix(20))")
            }
        }
        return joinedText(results)
    }

    /// Transcribe an audio file (any format `AVAudioFile` understands).
    /// Used by the LaunchAgent daemon when the iPhone ships a
    /// compressed blob through the bridge.
    public func transcribe(
        fileURL: URL,
        using model: DictationModel,
        language: String?,
        prompt: String? = nil,
        useVAD: Bool = false
    ) async throws -> String {
        if let fixture = try Self.e2eFixtureText(useVAD: useVAD, permissive: false) {
            return fixture
        }
        let kit = try await ensureLoaded(model: model)
        var options = decodeOptions(language: language, prompt: prompt)
        if useVAD {
            options.chunkingStrategy = .vad
        }
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

    /// Transcribe + return per-segment timing alongside the joined
    /// text. Used by the macOS GUI's auto-format pass (#7) to drop
    /// paragraph breaks at silence boundaries instead of inferring
    /// them from punctuation. The segments are flattened across all
    /// `TranscriptionResult` chunks so the caller doesn't need to
    /// know about WhisperKit's internal windowing.
    public func transcribeWithSegments(
        samples: [Float],
        using model: DictationModel,
        language: String?,
        prompt: String? = nil,
        useVAD: Bool = false
    ) async throws -> SegmentedTranscript {
        if let fixture = try Self.e2eFixtureText(useVAD: useVAD, permissive: false) {
            return SegmentedTranscript(
                text: fixture,
                segments: [
                    SegmentedTranscript.Segment(text: fixture, start: 0, end: 1)
                ]
            )
        }
        let kit = try await ensureLoaded(model: model)
        var options = decodeOptions(language: language, prompt: prompt)
        if useVAD {
            options.chunkingStrategy = .vad
        }
        if let tokens = tokenize(prompt: prompt, kit: kit) {
            options.promptTokens = tokens
        }
        Self.trace("transcribeWithSegments: samples=\(samples.count) language=\(options.language ?? "auto") detect=\(options.detectLanguage) vad=\(useVAD)")
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        Self.trace("transcribeWithSegments: results.count=\(results.count) firstText=\"\(results.first?.text.prefix(80) ?? "")\" segments=\(results.first?.segments.count ?? -1) detectedLang=\(results.first?.language ?? "?")")
        if let first = results.first {
            for (idx, seg) in first.segments.prefix(3).enumerated() {
                Self.trace("  seg[\(idx)] text=\"\(seg.text)\" start=\(seg.start) end=\(seg.end) tokens=\(seg.tokens.prefix(20))")
            }
        }
        let text = joinedText(results)
        // Each `TranscriptionResult` window restarts its `start` at
        // 0 within its own coordinate space, so when we flatten we
        // offset every segment by the cumulative window length so
        // gaps across chunk boundaries don't read as artificial.
        var flattened: [SegmentedTranscript.Segment] = []
        var offset: Float = 0
        for result in results {
            for segment in result.segments {
                flattened.append(
                    SegmentedTranscript.Segment(
                        text: segment.text,
                        start: segment.start + offset,
                        end: segment.end + offset
                    )
                )
            }
            // The window's effective length is the end of its last
            // segment; if a window had no segments, fall back to the
            // ratio of samples it consumed (less common path).
            if let lastEnd = result.segments.last?.end {
                offset += lastEnd
            }
        }
        return SegmentedTranscript(text: text, segments: flattened)
    }

    /// Last local fallback for audible buffers where WhisperKit returns
    /// only control tokens (`<|startoftranscript|> ... <|endoftext|>`).
    /// The normal decoder keeps no-speech / low-logprob guards enabled;
    /// this path disables those guards so real speech is not discarded
    /// before it reaches the coordinator.
    public func transcribePermissive(
        samples: [Float],
        using model: DictationModel,
        language: String? = nil,
        prompt: String? = nil
    ) async throws -> String {
        if let fixture = try Self.e2eFixtureText(useVAD: false, permissive: true) {
            return fixture
        }
        let kit = try await ensureLoaded(model: model)
        var options = decodeOptions(language: language, prompt: prompt)
        options.detectLanguage = language == nil || language == "auto"
        options.skipSpecialTokens = true
        options.noSpeechThreshold = nil
        options.logProbThreshold = nil
        options.firstTokenLogProbThreshold = nil
        options.temperatureFallbackCount = 0
        if let tokens = tokenize(prompt: prompt, kit: kit) {
            options.promptTokens = tokens
        }
        Self.trace("transcribePermissive: samples=\(samples.count) language=\(options.language ?? "auto") detect=\(options.detectLanguage)")
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        Self.trace("transcribePermissive: results.count=\(results.count) firstText=\"\(results.first?.text.prefix(80) ?? "")\" segments=\(results.first?.segments.count ?? -1) detectedLang=\(results.first?.language ?? "?")")
        return joinedText(results)
    }

    // MARK: - Internal

    private func ensureLoaded(model: DictationModel) async throws -> WhisperKit {
        if let loaded, loaded.model == model {
            return loaded.kit
        }
        loaded = nil
        guard let folder = DictationModelManager.installedFolder(for: model) else {
            Self.trace("ensureLoaded: noModelAvailable variant=\(model.whisperKitVariant)")
            throw TranscriptionError.noModelAvailable
        }
        Self.trace("ensureLoaded: loading variant=\(model.whisperKitVariant) folder=\(folder.path)")
        do {
            // `download: false` keeps WhisperKit from auto-pulling a
            // 1.5+ GB model behind the user's back; the Settings page
            // owns the download UX with proper progress. `verbose: true`
            // and `logLevel: .debug` route WhisperKit's internal stage
            // messages (model load, audio chunks, decode passes) through
            // its `Logging` system so we can read them in the host app's
            // stderr / Console; cheap and load-bearing for diagnosing
            // empty-transcript cases where the audio is captured fine
            // but the decoder produces no tokens.
            let config = WhisperKitConfig(
                modelFolder: folder.path,
                verbose: true,
                logLevel: .debug,
                prewarm: false,
                load: true,
                download: false
            )
            let kit = try await WhisperKit(config)
            Self.trace("ensureLoaded: loaded ok variant=\(model.whisperKitVariant) tokenizerLoaded=\(kit.tokenizer != nil)")
            loaded = (model, kit)
            return kit
        } catch {
            Self.trace("ensureLoaded: WhisperKit init threw: \(error)")
            // The strict `installedFolder` check should already keep
            // partial trees out of here, but a corrupted-yet-non-empty
            // file (e.g. a `coremldata.bin` truncated by a power
            // failure) can still slip through. Re-validate, and if
            // the folder fails the check now, treat it as a broken
            // install: wipe and surface the actionable
            // `modelIncomplete` error so the user gets a clean retry
            // path from Settings instead of a leaky CoreML message
            // pointing at `file:///Users/.../coremldata.bin`.
            if !DictationModelManager.isCompleteVariantFolder(at: folder) {
                DictationModelManager.wipeBrokenInstall(for: model)
                throw TranscriptionError.modelIncomplete(model)
            }
            throw TranscriptionError.engineFailed(
                "Couldn't load \(model.displayName). Try restarting the app, or re-download the model from Settings → Voice to Text."
            )
        }
    }

    /// File-backed tracer so transcription stage transitions land in a
    /// known location regardless of how the host app is launched.
    /// Mirrors the format used by `HotkeyManager` / `DictationCoordinator`
    /// (same `/tmp/clawix-hotkey.log`) so we can diff one continuous
    /// timeline when reproducing dictation bugs.
    public nonisolated static func trace(_ message: String) {
        let line = "\(Date()) ts: \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: "/tmp/clawix-hotkey.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
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

    private nonisolated static func e2eFixtureText(useVAD: Bool, permissive: Bool) throws -> String? {
        let env = ProcessInfo.processInfo.environment
        guard let text = env["CLAWIX_E2E_TRANSCRIPTION_TEXT"] else { return nil }
        if !permissive, env["CLAWIX_E2E_TRANSCRIPTION_EMPTY_UNTIL_PERMISSIVE"] == "1" {
            trace("e2e: forced empty standard transcription")
            return ""
        }
        if useVAD, env["CLAWIX_E2E_TRANSCRIPTION_VAD_FAIL"] == "1" {
            trace("e2e: forced vad failure")
            throw TranscriptionError.engineFailed("E2E forced VAD failure")
        }
        trace("e2e: fixture transcription vad=\(useVAD) permissive=\(permissive)")
        return text
    }
}
