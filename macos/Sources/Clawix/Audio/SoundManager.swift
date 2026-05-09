import Foundation
import AVFoundation
import SwiftUI

/// Plays the four dictation feedback cues and supports custom start/stop sounds.
@MainActor
final class SoundManager {
    static let shared = SoundManager()

    static let defaultsKey = "dictation.soundFeedback"
    static let playStartKey = "dictation.playStartSound"
    static let playStopKey = "dictation.playStopSound"
    static let customStartURLKey = "dictation.customStartSoundURL"
    static let customStopURLKey = "dictation.customStopSoundURL"

    private var startPlayer: AVAudioPlayer?
    private var stopPlayer: AVAudioPlayer?
    private var donePlayer: AVAudioPlayer?
    private var cancelPlayer: AVAudioPlayer?

    private var startPlayerURL: URL?
    private var stopPlayerURL: URL?

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Self.defaultsKey) == nil {
            defaults.set(true, forKey: Self.defaultsKey)
        }
        if defaults.object(forKey: Self.playStartKey) == nil {
            defaults.set(true, forKey: Self.playStartKey)
        }
        if defaults.object(forKey: Self.playStopKey) == nil {
            defaults.set(true, forKey: Self.playStopKey)
        }
        loadStartPlayer()
        loadStopPlayer()
        loadPlayer(name: "clawix-done", into: &donePlayer, volume: 1.0)
        loadPlayer(name: "clawix-cancel", into: &cancelPlayer, volume: 0.85)
    }

    // MARK: - Loading

    private func resolvedStartURL() -> URL? {
        if let custom = customURL(forKey: Self.customStartURLKey) { return custom }
        return Bundle.module.url(forResource: "clawix-start", withExtension: "wav", subdirectory: "Sounds")
            ?? Bundle.module.url(forResource: "clawix-start", withExtension: "wav")
    }

    private func resolvedStopURL() -> URL? {
        if let custom = customURL(forKey: Self.customStopURLKey) { return custom }
        return Bundle.module.url(forResource: "clawix-stop", withExtension: "wav", subdirectory: "Sounds")
            ?? Bundle.module.url(forResource: "clawix-stop", withExtension: "wav")
    }

    private func customURL(forKey key: String) -> URL? {
        guard let path = defaults.string(forKey: key), !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func loadStartPlayer() {
        guard let url = resolvedStartURL() else {
            startPlayer = nil
            startPlayerURL = nil
            return
        }
        startPlayer = makePlayer(url: url, volume: 1.0)
        startPlayerURL = url
    }

    private func loadStopPlayer() {
        guard let url = resolvedStopURL() else {
            stopPlayer = nil
            stopPlayerURL = nil
            return
        }
        stopPlayer = makePlayer(url: url, volume: 1.0)
        stopPlayerURL = url
    }

    private func makePlayer(url: URL, volume: Float) -> AVAudioPlayer? {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = volume
            player.prepareToPlay()
            return player
        } catch {
            NSLog("[Clawix.Sound] failed to load %@: %@", url.lastPathComponent, error.localizedDescription)
            return nil
        }
    }

    private func loadPlayer(name: String, into target: inout AVAudioPlayer?, volume: Float) {
        guard let url = Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Sounds")
                ?? Bundle.module.url(forResource: name, withExtension: "wav") else {
            NSLog("[Clawix.Sound] missing resource %@.wav", name)
            return
        }
        target = makePlayer(url: url, volume: volume)
    }

    private func reloadIfNeeded() {
        let currentStart = resolvedStartURL()
        if currentStart != startPlayerURL {
            loadStartPlayer()
        }
        let currentStop = resolvedStopURL()
        if currentStop != stopPlayerURL {
            loadStopPlayer()
        }
    }

    // MARK: - Public

    func playStart() {
        reloadIfNeeded()
        guard isStartEnabled else { return }
        play(startPlayer)
    }

    func playStop() {
        reloadIfNeeded()
        guard isStopEnabled else { return }
        play(stopPlayer)
    }

    func playDone() { play(donePlayer) }
    func playCancel() { play(cancelPlayer) }

    func preview(url: URL) {
        guard isMasterEnabled else { return }
        if let player = try? AVAudioPlayer(contentsOf: url) {
            player.volume = 1.0
            player.prepareToPlay()
            Self.previewPlayer = player
            player.play()
        }
    }

    private static var previewPlayer: AVAudioPlayer?

    static func validate(url: URL) -> Result<Void, ValidationError> {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            if player.duration > 5.0 {
                return .failure(.tooLong(seconds: player.duration))
            }
            return .success(())
        } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
    }

    enum ValidationError: Error, LocalizedError {
        case tooLong(seconds: TimeInterval)
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .tooLong(let s):
                return String(format: "Audio is %.1fs; please pick a clip ≤ 5s.", s)
            case .unreadable(let detail):
                return "Couldn't read this file: \(detail)"
            }
        }
    }

    private func play(_ player: AVAudioPlayer?) {
        guard isMasterEnabled, let player else { return }
        // Always rewind: AVAudioPlayer leaves currentTime at duration after a
        // clip finishes, and the next play() can no-op silently otherwise.
        player.stop()
        player.currentTime = 0
        player.play()
    }

    var isMasterEnabled: Bool {
        if defaults.object(forKey: Self.defaultsKey) == nil { return true }
        return defaults.bool(forKey: Self.defaultsKey)
    }

    var isStartEnabled: Bool {
        guard isMasterEnabled else { return false }
        if defaults.object(forKey: Self.playStartKey) == nil { return true }
        return defaults.bool(forKey: Self.playStartKey)
    }

    var isStopEnabled: Bool {
        guard isMasterEnabled else { return false }
        if defaults.object(forKey: Self.playStopKey) == nil { return true }
        return defaults.bool(forKey: Self.playStopKey)
    }
}

enum CustomSoundLibrary {

    static func storageDirectory() throws -> URL {
        let fm = FileManager.default
        let support = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = support.appendingPathComponent("Clawix/dictation-sounds", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func install(_ source: URL) throws -> URL {
        let dir = try storageDirectory()
        let fileName = "\(UUID().uuidString)-\(source.lastPathComponent)"
        let dest = dir.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: source, to: dest)
        return dest
    }

    static func remove(at path: String) {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: url)
    }
}
