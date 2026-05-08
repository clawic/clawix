import Foundation
import GRDB

/// One persisted dictation result. The repository hands these back
/// in reverse-chronological order. Audio file path is nullable so
/// the audio-cleanup policy (#25) can drop just the WAV.
struct TranscriptionRecord: Identifiable, Codable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "dictation_transcript"

    enum Columns: String, ColumnExpression {
        case id, timestamp, original_text, enhanced_text, model_used, language
        case duration_seconds, audio_file_path, power_mode_id, word_count
        case transcription_ms, enhancement_ms, enhancement_provider, cost_usd
    }

    var id: String
    var timestamp: Date
    var originalText: String
    var enhancedText: String?
    var modelUsed: String?
    var language: String?
    var durationSeconds: Double
    var audioFilePath: String?
    var powerModeId: String?
    var wordCount: Int
    var transcriptionMs: Int
    var enhancementMs: Int
    var enhancementProvider: String?
    var costUSD: Double

    init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        originalText: String,
        enhancedText: String? = nil,
        modelUsed: String? = nil,
        language: String? = nil,
        durationSeconds: Double = 0,
        audioFilePath: String? = nil,
        powerModeId: String? = nil,
        wordCount: Int = 0,
        transcriptionMs: Int = 0,
        enhancementMs: Int = 0,
        enhancementProvider: String? = nil,
        costUSD: Double = 0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.originalText = originalText
        self.enhancedText = enhancedText
        self.modelUsed = modelUsed
        self.language = language
        self.durationSeconds = durationSeconds
        self.audioFilePath = audioFilePath
        self.powerModeId = powerModeId
        self.wordCount = wordCount
        self.transcriptionMs = transcriptionMs
        self.enhancementMs = enhancementMs
        self.enhancementProvider = enhancementProvider
        self.costUSD = costUSD
    }

    enum CodingKeys: String, CodingKey {
        case id, timestamp
        case originalText = "original_text"
        case enhancedText = "enhanced_text"
        case modelUsed = "model_used"
        case language
        case durationSeconds = "duration_seconds"
        case audioFilePath = "audio_file_path"
        case powerModeId = "power_mode_id"
        case wordCount = "word_count"
        case transcriptionMs = "transcription_ms"
        case enhancementMs = "enhancement_ms"
        case enhancementProvider = "enhancement_provider"
        case costUSD = "cost_usd"
    }
}

@MainActor
final class TranscriptionsRepository: ObservableObject {

    static let shared = TranscriptionsRepository()

    private let dbQueue: DatabaseQueue

    /// Cache so the SwiftUI history view re-renders without going to
    /// disk on every keystroke.
    @Published private(set) var recent: [TranscriptionRecord] = []

    init(db: DatabaseQueue = Database.shared.dbQueue) {
        self.dbQueue = db
        Task { @MainActor in await self.refreshCache() }
    }

    // MARK: - Reads

    func refreshCache(limit: Int = 200) async {
        do {
            let rows: [TranscriptionRecord] = try await dbQueue.read { db in
                try TranscriptionRecord
                    .order(TranscriptionRecord.Columns.timestamp.desc)
                    .limit(limit)
                    .fetchAll(db)
            }
            await MainActor.run { self.recent = rows }
        } catch {
            NSLog("[Clawix.Transcripts] cache refresh failed: %@", error.localizedDescription)
        }
    }

    func fetchPage(offset: Int, limit: Int) async throws -> [TranscriptionRecord] {
        try await dbQueue.read { db in
            try TranscriptionRecord
                .order(TranscriptionRecord.Columns.timestamp.desc)
                .limit(limit, offset: offset)
                .fetchAll(db)
        }
    }

    func search(_ needle: String, limit: Int = 200) async throws -> [TranscriptionRecord] {
        let pattern = "%" + needle.replacingOccurrences(of: "%", with: "\\%") + "%"
        return try await dbQueue.read { db in
            try TranscriptionRecord
                .filter(
                    TranscriptionRecord.Columns.original_text.like(pattern)
                    || TranscriptionRecord.Columns.enhanced_text.like(pattern)
                )
                .order(TranscriptionRecord.Columns.timestamp.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Writes

    func record(_ entry: TranscriptionRecord) async {
        do {
            try await dbQueue.write { db in
                try entry.insert(db)
            }
            await refreshCache()
        } catch {
            NSLog("[Clawix.Transcripts] insert failed: %@", error.localizedDescription)
        }
    }

    func delete(id: String) async {
        do {
            try await dbQueue.write { db in
                try TranscriptionRecord
                    .filter(TranscriptionRecord.Columns.id == id)
                    .deleteAll(db)
            }
            await refreshCache()
        } catch {
            NSLog("[Clawix.Transcripts] delete failed: %@", error.localizedDescription)
        }
    }

    // MARK: - Cleanup

    /// Delete every record older than `cutoff` and best-effort remove
    /// the corresponding audio files from Application Support.
    func purgeRecords(olderThan cutoff: Date) async {
        do {
            let toDelete: [TranscriptionRecord] = try await dbQueue.read { db in
                try TranscriptionRecord
                    .filter(TranscriptionRecord.Columns.timestamp < cutoff)
                    .fetchAll(db)
            }
            for record in toDelete {
                if let path = record.audioFilePath {
                    try? FileManager.default.removeItem(atPath: path)
                }
            }
            try await dbQueue.write { db in
                try TranscriptionRecord
                    .filter(TranscriptionRecord.Columns.timestamp < cutoff)
                    .deleteAll(db)
            }
            await refreshCache()
        } catch {
            NSLog("[Clawix.Transcripts] purgeRecords failed: %@", error.localizedDescription)
        }
    }

    /// Drop just the audio files older than cutoff; keep the text rows.
    func purgeAudioFiles(olderThan cutoff: Date) async {
        do {
            let candidates: [TranscriptionRecord] = try await dbQueue.read { db in
                try TranscriptionRecord
                    .filter(TranscriptionRecord.Columns.timestamp < cutoff
                            && TranscriptionRecord.Columns.audio_file_path != nil)
                    .fetchAll(db)
            }
            for record in candidates {
                if let path = record.audioFilePath {
                    try? FileManager.default.removeItem(atPath: path)
                }
            }
            try await dbQueue.write { db in
                let ids = candidates.map(\.id)
                try TranscriptionRecord
                    .filter(ids.contains(TranscriptionRecord.Columns.id))
                    .updateAll(db, TranscriptionRecord.Columns.audio_file_path.set(to: nil))
            }
            await refreshCache()
        } catch {
            NSLog("[Clawix.Transcripts] purgeAudioFiles failed: %@", error.localizedDescription)
        }
    }

    // MARK: - Aggregates

    struct Aggregates: Equatable {
        var totalCount: Int
        var totalWords: Int
        var totalDurationSeconds: Double
        var totalCostUSD: Double
        var averageTranscriptionMs: Double
        var averageEnhancementMs: Double
    }

    func aggregates() async throws -> Aggregates {
        try await dbQueue.read { db in
            let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dictation_transcript") ?? 0
            let words = try Int.fetchOne(db, sql: "SELECT COALESCE(SUM(word_count), 0) FROM dictation_transcript") ?? 0
            let dur = try Double.fetchOne(db, sql: "SELECT COALESCE(SUM(duration_seconds), 0) FROM dictation_transcript") ?? 0
            let cost = try Double.fetchOne(db, sql: "SELECT COALESCE(SUM(cost_usd), 0) FROM dictation_transcript") ?? 0
            let avgT = try Double.fetchOne(db, sql: "SELECT COALESCE(AVG(transcription_ms), 0) FROM dictation_transcript") ?? 0
            let avgE = try Double.fetchOne(db, sql: "SELECT COALESCE(AVG(NULLIF(enhancement_ms, 0)), 0) FROM dictation_transcript") ?? 0
            return Aggregates(
                totalCount: total,
                totalWords: words,
                totalDurationSeconds: dur,
                totalCostUSD: cost,
                averageTranscriptionMs: avgT,
                averageEnhancementMs: avgE
            )
        }
    }
}

/// Storage helper for raw audio files associated with transcripts.
/// Lives in `Application Support/Clawix/dictation-audio/<UUID>.wav`
/// so cleanup can target a single directory.
enum DictationAudioStorage {
    static func storageDirectory() throws -> URL {
        let fm = FileManager.default
        let support = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = support.appendingPathComponent("Clawix/dictation-audio", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Persist a 16 kHz mono Float32 PCM buffer as a 16-bit WAV.
    /// Skipped silently on any error — the transcript row is more
    /// important than the audio companion and shouldn't fail because
    /// of an audio write hiccup.
    static func writeWAV(samples: [Float], id: String) -> URL? {
        guard !samples.isEmpty else { return nil }
        do {
            let dir = try storageDirectory()
            let url = dir.appendingPathComponent("\(id).wav")
            let sampleRate: Int = 16_000
            let bitsPerSample: Int = 16
            let channels: Int = 1
            let byteRate = sampleRate * channels * (bitsPerSample / 8)
            let blockAlign = channels * (bitsPerSample / 8)
            let dataBytes = samples.count * (bitsPerSample / 8)
            var data = Data(capacity: 44 + dataBytes)
            data.append("RIFF".data(using: .ascii)!)
            data.append(UInt32(36 + dataBytes).littleEndianData)
            data.append("WAVE".data(using: .ascii)!)
            data.append("fmt ".data(using: .ascii)!)
            data.append(UInt32(16).littleEndianData)
            data.append(UInt16(1).littleEndianData) // PCM
            data.append(UInt16(channels).littleEndianData)
            data.append(UInt32(sampleRate).littleEndianData)
            data.append(UInt32(byteRate).littleEndianData)
            data.append(UInt16(blockAlign).littleEndianData)
            data.append(UInt16(bitsPerSample).littleEndianData)
            data.append("data".data(using: .ascii)!)
            data.append(UInt32(dataBytes).littleEndianData)
            for sample in samples {
                let clamped = max(-1, min(1, sample))
                let value = Int16(clamped * Float(Int16.max))
                data.append(UInt16(bitPattern: value).littleEndianData)
            }
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

private extension UInt16 {
    var littleEndianData: Data {
        var v = self.littleEndian
        return Data(bytes: &v, count: MemoryLayout<UInt16>.size)
    }
}

private extension UInt32 {
    var littleEndianData: Data {
        var v = self.littleEndian
        return Data(bytes: &v, count: MemoryLayout<UInt32>.size)
    }
}
