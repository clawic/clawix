import Foundation

/// Periodic privacy-cleanup runner for transcript history (#25).
/// Two policies, mutually exclusive (transcripts wins when both are
/// on so the user doesn't end up with audio outliving the rows that
/// described them):
///
///   * `dictation.cleanup.transcriptsEnabled` → drop the whole row +
///     audio file after `transcriptsTTL` elapses.
///   * `dictation.cleanup.audioFilesEnabled` → drop just the audio
///     file (text + metadata stay) after `audioFilesTTL`.
///
/// Schedule: a one-shot pass on app boot + an hourly re-run via a
/// repeating Timer. Cheap (a single SQLite scan with an index) so
/// the hourly cadence is fine.
@MainActor
final class CleanupScheduler {

    static let shared = CleanupScheduler()

    static let transcriptsEnabledKey = "dictation.cleanup.transcriptsEnabled"
    static let transcriptsTTLKey = "dictation.cleanup.transcriptsTTL"
    static let audioFilesEnabledKey = "dictation.cleanup.audioFilesEnabled"
    static let audioFilesTTLKey = "dictation.cleanup.audioFilesTTL"

    enum TranscriptsTTL: String, CaseIterable {
        case immediate, h1, d1, d3, d7

        var displayName: String {
            switch self {
            case .immediate: return "Immediately"
            case .h1: return "1 hour"
            case .d1: return "1 day"
            case .d3: return "3 days"
            case .d7: return "7 days"
            }
        }
        var seconds: TimeInterval {
            switch self {
            case .immediate: return 0
            case .h1: return 3600
            case .d1: return 86_400
            case .d3: return 86_400 * 3
            case .d7: return 86_400 * 7
            }
        }
    }

    enum AudioTTL: String, CaseIterable {
        case d1, d3, d7, d14, d30

        var displayName: String {
            switch self {
            case .d1: return "1 day"
            case .d3: return "3 days"
            case .d7: return "7 days"
            case .d14: return "14 days"
            case .d30: return "30 days"
            }
        }
        var seconds: TimeInterval {
            switch self {
            case .d1: return 86_400
            case .d3: return 86_400 * 3
            case .d7: return 86_400 * 7
            case .d14: return 86_400 * 14
            case .d30: return 86_400 * 30
            }
        }
    }

    private let defaults: UserDefaults
    private var timer: Timer?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bootstrapIfNeeded()
    }

    func start() {
        Task { await runOnce() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.runOnce() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Public so the Settings sheet's "Run Cleanup Now" button can
    /// trigger it on demand.
    func runOnce() async {
        let now = Date()
        if defaults.bool(forKey: Self.transcriptsEnabledKey) {
            let ttl = transcriptsTTL().seconds
            let cutoff = now.addingTimeInterval(-ttl)
            await TranscriptionsRepository.shared.purgeRecords(olderThan: cutoff)
            return
        }
        if defaults.bool(forKey: Self.audioFilesEnabledKey) {
            let ttl = audioTTL().seconds
            let cutoff = now.addingTimeInterval(-ttl)
            await TranscriptionsRepository.shared.purgeAudioFiles(olderThan: cutoff)
        }
    }

    func transcriptsTTL() -> TranscriptsTTL {
        let raw = defaults.string(forKey: Self.transcriptsTTLKey) ?? TranscriptsTTL.d1.rawValue
        return TranscriptsTTL(rawValue: raw) ?? .d1
    }

    func audioTTL() -> AudioTTL {
        let raw = defaults.string(forKey: Self.audioFilesTTLKey) ?? AudioTTL.d7.rawValue
        return AudioTTL(rawValue: raw) ?? .d7
    }

    private func bootstrapIfNeeded() {
        if defaults.object(forKey: Self.transcriptsEnabledKey) == nil {
            defaults.set(false, forKey: Self.transcriptsEnabledKey)
        }
        if defaults.object(forKey: Self.audioFilesEnabledKey) == nil {
            defaults.set(false, forKey: Self.audioFilesEnabledKey)
        }
        if defaults.object(forKey: Self.transcriptsTTLKey) == nil {
            defaults.set(TranscriptsTTL.d1.rawValue, forKey: Self.transcriptsTTLKey)
        }
        if defaults.object(forKey: Self.audioFilesTTLKey) == nil {
            defaults.set(AudioTTL.d7.rawValue, forKey: Self.audioFilesTTLKey)
        }
    }
}
