import Foundation
import CryptoKit

/// Installs and verifies the local LLM runtime outside the app bundle.
@MainActor
final class LocalModelsRuntimeInstaller: NSObject, ObservableObject {

    static let shared = LocalModelsRuntimeInstaller()

    nonisolated static let pinnedVersion = "v0.23.1"

    nonisolated static let pinnedDownloadURL = URL(
        string: "https://github.com/ollama/ollama/releases/download/v0.23.1/ollama-darwin.tgz"
    )!

    nonisolated static let pinnedSHA256Base64 = "YpWG/xp201GnufV+sZhe+QPuLm/0mXp8VXOWTIPzehY="

    nonisolated static let pinnedSizeBytes: Int64 = 133_703_316

    enum State: Equatable {
        case notInstalled
        case installing(progress: Double, downloadedBytes: Int64)
        case extracting
        case installed(version: String)
        case updateAvailable(installed: String)
        case failed(message: String)
    }

    @Published private(set) var state: State = .notInstalled

    private var session: URLSession?
    private var downloadTask: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<URL, Error>?

    private override init() {
        super.init()
        refresh()
    }

    // MARK: - Public API

    var isInstalled: Bool {
        if case .installed = state { return true }
        return false
    }

    func refresh() {
        if let v = installedVersion() {
            state = (v == Self.pinnedVersion)
                ? .installed(version: v)
                : .updateAvailable(installed: v)
        } else {
            state = .notInstalled
        }
    }

    func install() async {
        if case .installed(let v) = state, v == Self.pinnedVersion { return }
        if case .installing = state { return }
        if case .extracting = state { return }

        do {
            try Self.prepareParentDirectory()

            let tarball = try await download()
            try await Task.detached(priority: .userInitiated) {
                try Self.verify(tarball: tarball)
            }.value

            self.state = .extracting

            try await Task.detached(priority: .userInitiated) {
                try Self.extract(tarball: tarball)
                try Self.writeVersionFile()
                try? FileManager.default.removeItem(at: tarball)
            }.value

            self.state = .installed(version: Self.pinnedVersion)
        } catch is CancellationError {
            self.state = .notInstalled
        } catch {
            self.state = .failed(message: error.localizedDescription)
        }
    }

    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
    }

    func uninstall() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: Self.runtimeRoot.path) {
            try fm.removeItem(at: Self.runtimeRoot)
        }
        state = .notInstalled
    }

    func installedVersion() -> String? {
        guard let data = try? Data(contentsOf: Self.versionFile) else { return nil }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - On-disk layout

    nonisolated static var runtimeRoot: URL {
        applicationSupportRoot.appendingPathComponent("runtime", isDirectory: true)
    }

    nonisolated static var versionFile: URL {
        runtimeRoot.appendingPathComponent("version", isDirectory: false)
    }

    nonisolated static var binaryURL: URL {
        runtimeRoot.appendingPathComponent("bin/ollama", isDirectory: false)
    }

    nonisolated static var applicationSupportRoot: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return base.appendingPathComponent("Clawix/local-models", isDirectory: true)
    }

    private nonisolated static func prepareParentDirectory() throws {
        try FileManager.default.createDirectory(
            at: applicationSupportRoot,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Download

    private func download() async throws -> URL {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 30 * 60
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            self.continuation = cont
            self.state = .installing(progress: 0, downloadedBytes: 0)
            let task = session.downloadTask(with: Self.pinnedDownloadURL)
            self.downloadTask = task
            task.resume()
        }
    }

    private func resumeContinuation(with result: Result<URL, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        downloadTask = nil
        switch result {
        case .success(let url): cont.resume(returning: url)
        case .failure(let err): cont.resume(throwing: err)
        }
    }

    // MARK: - Verify / extract (off the main actor)

    private nonisolated static func verify(tarball: URL) throws {
        let handle = try FileHandle(forReadingFrom: tarball)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = autoreleasepool { (try? handle.read(upToCount: 1 << 20)) ?? Data() }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        let actual = Data(hasher.finalize()).base64EncodedString()
        guard actual == pinnedSHA256Base64 else {
            throw InstallerError.sha256Mismatch(expected: pinnedSHA256Base64, actual: actual)
        }
    }

    private nonisolated static func extract(tarball: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: runtimeRoot.path) {
            try fm.removeItem(at: runtimeRoot)
        }
        try fm.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)

        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xzf", tarball.path, "-C", runtimeRoot.path]
        let stderrPipe = Pipe()
        tar.standardError = stderrPipe
        tar.standardOutput = Pipe()
        try tar.run()
        tar.waitUntilExit()
        guard tar.terminationStatus == 0 else {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "exit \(tar.terminationStatus)"
            throw InstallerError.extractionFailed(message: message)
        }

        guard fm.isExecutableFile(atPath: binaryURL.path) else {
            throw InstallerError.binaryMissing(expected: binaryURL.path)
        }
    }

    private nonisolated static func writeVersionFile() throws {
        let data = pinnedVersion.data(using: .utf8)!
        try data.write(to: versionFile, options: .atomic)
    }

    // MARK: - Errors

    enum InstallerError: LocalizedError {
        case sha256Mismatch(expected: String, actual: String)
        case extractionFailed(message: String)
        case binaryMissing(expected: String)

        var errorDescription: String? {
            switch self {
            case .sha256Mismatch(let expected, let actual):
                return "Runtime checksum mismatch. Expected \(expected), got \(actual). Aborting for safety."
            case .extractionFailed(let message):
                return "Could not unpack runtime archive: \(message)"
            case .binaryMissing(let expected):
                return "Runtime extracted but the binary is missing at \(expected). Upstream layout may have changed."
            }
        }
    }
}
