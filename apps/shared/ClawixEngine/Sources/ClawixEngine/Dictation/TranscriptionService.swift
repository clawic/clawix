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
    public func transcribe(samples: [Float], using model: DictationModel, language: String?) async throws -> String {
        let kit = try await ensureLoaded(model: model)
        let options = decodeOptions(language: language)
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        return joinedText(results)
    }

    /// Transcribe an audio file (any format `AVAudioFile` understands).
    /// Used by the LaunchAgent daemon when the iPhone ships a
    /// compressed blob through the bridge.
    public func transcribe(fileURL: URL, using model: DictationModel, language: String?) async throws -> String {
        let kit = try await ensureLoaded(model: model)
        let options = decodeOptions(language: language)
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
        do {
            // `download: false` is intentional. Auto-downloading a
            // 1.5+ GB model behind the user's back blocks the
            // dictation overlay for a long time with no progress UI.
            // The Settings page has an explicit "Download" button
            // that goes through `WhisperKit.download(...)` with a
            // proper progress bar, so by the time we get here the
            // model should already be on disk. If it isn't, surface
            // `noModelAvailable` so the overlay closes immediately
            // and the caller can tell the user where to fix it.
            let config = WhisperKitConfig(
                model: model.whisperKitVariant,
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
            throw TranscriptionError.noModelAvailable
        }
    }

    private func decodeOptions(language: String?) -> DecodingOptions {
        // We sample at 16 kHz mono and pass full audio in one shot. VAD
        // chunking is only worth turning on for >30s recordings; for
        // typical dictation bursts (<10s) the simple path is faster.
        var options = DecodingOptions()
        if let language, !language.isEmpty, language != "auto" {
            options.language = language
        }
        options.task = .transcribe
        options.temperature = 0.0
        return options
    }

    private func joinedText(_ results: [TranscriptionResult]) -> String {
        results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
