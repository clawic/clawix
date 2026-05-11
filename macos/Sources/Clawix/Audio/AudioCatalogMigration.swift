#if canImport(AVFoundation)
import Foundation
import AVFoundation
import ClawixEngine

/// One-shot migration from the legacy on-disk `AudioMessageStore`
/// (`~/Library/Application Support/Clawix/audio-meta.json` + per-chat
/// blobs) into the framework's audio catalog service. Idempotent: a
/// marker file in the workspace short-circuits subsequent runs. The
/// legacy JSON is renamed to `audio-meta.json.migrated` instead of
/// deleted so the user can recover data manually if something goes
/// wrong mid-migration (Constitution red line 4: no data loss).
enum AudioCatalogMigration {

    enum Outcome: Equatable {
        /// First successful migration: how many entries were imported.
        case migrated(count: Int)
        /// Marker already present; nothing to do this boot.
        case alreadyMigrated
        /// No legacy JSON found; marker written so we don't keep checking.
        case noLegacyData
    }

    /// Runs the migration once for the `clawix` app namespace. Safe to
    /// call after the audio service is healthy; aborts cleanly when it
    /// is not yet reachable so the caller can retry on the next boot.
    @discardableResult
    static func migrateIfNeeded(
        client: ClawJSAudioClient,
        legacyRoot: URL = defaultLegacyRoot(),
        markerURL: URL = defaultMarkerURL()
    ) async throws -> Outcome {
        if FileManager.default.fileExists(atPath: markerURL.path) {
            return .alreadyMigrated
        }
        try FileManager.default.createDirectory(
            at: markerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let metaURL = legacyRoot.appendingPathComponent("audio-meta.json")
        guard let metaData = try? Data(contentsOf: metaURL) else {
            try writeMarker(markerURL, count: 0)
            return .noLegacyData
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try decoder.decode([LegacyEntry].self, from: metaData)

        let blobsRoot = legacyRoot.appendingPathComponent("audio", isDirectory: true)
        var imported = 0
        for entry in entries {
            let fileURL = blobsRoot.appendingPathComponent(entry.fileRelPath)
            guard let bytes = try? Data(contentsOf: fileURL) else { continue }
            let durationMs = entry.durationMs > 0
                ? entry.durationMs
                : Self.durationMs(of: fileURL)
            let input = ClawJSAudioClient.RegisterInput(
                id: entry.id,
                kind: "user_message",
                appId: "clawix",
                originActor: "user",
                mimeType: entry.mimeType,
                bytesBase64: bytes.base64EncodedString(),
                durationMs: durationMs,
                deviceId: nil,
                sessionId: nil,
                threadId: entry.threadId,
                linkedMessageId: entry.messageId,
                metadataJson: nil,
                transcript: entry.transcript.isEmpty ? nil : .init(
                    text: entry.transcript,
                    role: "transcription",
                    provider: "unknown_legacy",
                    language: nil
                )
            )
            _ = try await client.register(input)
            imported += 1
        }

        try writeMarker(markerURL, count: imported)
        try? FileManager.default.moveItem(
            at: metaURL,
            to: metaURL.appendingPathExtension("migrated")
        )
        return .migrated(count: imported)
    }

    // MARK: - Defaults

    static func defaultLegacyRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Clawix", isDirectory: true)
    }

    /// Mirrors `ClawJSServiceManager.applicationSupportRoot` but is
    /// nonisolated so the migration can resolve the path from any
    /// concurrency context (the manager is `@MainActor`-bound).
    static func defaultMarkerURL() -> URL {
        let env = ProcessInfo.processInfo.environment
        let root: URL
        if env["CLAWIX_DUMMY_MODE"] == "1", let custom = env["CLAWIX_CLAWJS_ROOT"], !custom.isEmpty {
            root = URL(fileURLWithPath: custom, isDirectory: true)
        } else {
            root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Clawix/clawjs", isDirectory: true)
        }
        return root
            .appendingPathComponent("workspace", isDirectory: true)
            .appendingPathComponent(".clawjs", isDirectory: true)
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent(".migrated_clawix_v1", isDirectory: false)
    }

    // MARK: - Internals

    private struct LegacyEntry: Decodable {
        let id: String
        let threadId: String
        let chatId: String
        let messageId: String
        let transcript: String
        let mimeType: String
        let durationMs: Int
        let fileRelPath: String
        let createdAt: Date
    }

    private static func writeMarker(_ url: URL, count: Int) throws {
        let payload: [String: Any] = [
            "migratedAt": ISO8601DateFormatter().string(from: Date()),
            "count": count,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: .atomic)
    }

    private static func durationMs(of url: URL) -> Int {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let frames = Double(file.length)
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { return 0 }
        let seconds = frames / sampleRate
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int((seconds * 1000).rounded())
    }
}
#endif
