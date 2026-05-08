import Foundation
import AppKit
import ClawixEngine

/// Single source of truth for "the most recent dictation result" so
/// quick-action AppIntents (Paste Last, Retry Last) can replay it
/// without the user having to dictate again.
///
/// Samples are kept in memory only. They're discarded when the app
/// quits — the goal is fast retry/repaste in the same session, not a
/// crash-recovery store. Persisting raw audio across launches would
/// either bloat Application Support or require encrypted storage.
@MainActor
final class LastTranscriptionStore {

    static let shared = LastTranscriptionStore()

    /// Plain transcript text (after the user's word-replacement
    /// dictionary was applied).
    private(set) var lastText: String?
    /// Raw 16 kHz mono Float32 PCM samples — the same buffer
    /// `TranscriptionService` consumed. Kept in memory for retry.
    private(set) var lastSamples: [Float]?
    /// Model the original transcription was produced with. Retry
    /// switches to the user's currently-active model so a "wrong model"
    /// retry actually changes the outcome.
    private(set) var lastModelOriginal: DictationModel?
    /// Language hint used at the original transcription, or nil for
    /// auto-detect.
    private(set) var lastLanguage: String?
    private(set) var lastTimestamp: Date?

    private init() {}

    var hasResult: Bool { lastText?.isEmpty == false }

    /// Called by `DictationCoordinator.finish()` after the transcript
    /// has been processed (replacements applied) and just before paste.
    func record(
        text: String,
        samples: [Float],
        model: DictationModel?,
        language: String?
    ) {
        guard !text.isEmpty else { return }
        lastText = text
        lastSamples = samples
        lastModelOriginal = model
        lastLanguage = language
        lastTimestamp = Date()
    }

    // MARK: - Actions

    /// Paste the stored text into whatever app is foreground. Used by
    /// the `PasteLastTranscriptionIntent`. Honors the user's current
    /// auto-send and clipboard-restore settings — the goal is parity
    /// with a fresh dictation paste.
    func pasteLastOriginal() throws {
        guard let text = lastText, !text.isEmpty else {
            throw QuickActionError.noLastTranscription
        }
        let defaults = UserDefaults.standard
        let restore = defaults.bool(forKey: DictationCoordinator.restoreClipboardDefaultsKey)
        let restoreMs = defaults.object(forKey: DictationCoordinator.restoreClipboardDelayMsKey) as? Int ?? 2000
        let restoreAfter = TimeInterval(max(100, min(10_000, restoreMs))) / 1000.0
        let autoSendRaw = defaults.string(forKey: DictationCoordinator.autoSendKeyDefaultsKey) ?? DictationAutoSendKey.none.rawValue
        let autoSend = DictationAutoSendKey(rawValue: autoSendRaw) ?? .none
        let addSpace = defaults.object(forKey: DictationCoordinator.addSpaceBeforeKey) as? Bool ?? true
        try TextInjector.inject(
            text: text,
            restorePrevious: restore,
            autoSendKey: autoSend,
            restoreAfter: restoreAfter,
            addSpaceBefore: addSpace
        )
    }

    /// Re-run transcription on the stored audio with the user's
    /// current active model + language. Surfaces the new text and
    /// pastes it. Useful when the user changed the model in Settings
    /// and wants to compare results without redictating, or when
    /// Whisper's output was visibly garbled.
    func retryLast() async throws {
        guard let samples = lastSamples, !samples.isEmpty else {
            throw QuickActionError.noLastTranscription
        }
        let coordinator = DictationCoordinator.shared
        let activeModel = coordinator.modelManager.activeModel
        let language = coordinator.resolvedLanguageHintForExternalCallers()

        let prompt = DictationCoordinator.composeWhisperPrompt(language: language)
        let raw = try await DictationCoordinator.transcribeLocalWithFallback(
            samples: samples,
            model: activeModel,
            language: language,
            prompt: prompt,
            useVAD: UserDefaults.standard.object(forKey: DictationCoordinator.vadEnabledKey) as? Bool ?? true,
            autoFormat: UserDefaults.standard.object(forKey: DictationCoordinator.autoFormatParagraphsKey) as? Bool ?? true
        )
        let processed = DictationCoordinator.processForDelivery(raw, language: language)
        guard !processed.isEmpty else {
            throw QuickActionError.transcriptionEmpty
        }
        // Update the store so a follow-up "Paste Last" gets the new
        // text rather than the original.
        lastText = processed
        lastModelOriginal = activeModel
        lastLanguage = language
        lastTimestamp = Date()

        // Use the same paste path so settings are honored.
        try pasteLastOriginal()
    }

    enum QuickActionError: Error, LocalizedError {
        case noLastTranscription
        case transcriptionEmpty

        var errorDescription: String? {
            switch self {
            case .noLastTranscription:
                return "No previous dictation to repeat in this session"
            case .transcriptionEmpty:
                return "Whisper returned no text on retry"
            }
        }
    }
}
