import Foundation

extension LocalModelsRuntimeInstaller: URLSessionDownloadDelegate {

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0
            ? totalBytesExpectedToWrite
            : Self.pinnedSizeBytes
        let progress = max(0, min(1, Double(totalBytesWritten) / Double(total)))
        Task { @MainActor in
            self.updateDownloadProgress(progress: progress, downloadedBytes: totalBytesWritten)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let fm = FileManager.default
        let cacheDir = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clawix/local-models", isDirectory: true)
        try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let dest = cacheDir.appendingPathComponent("ollama-\(Self.pinnedVersion).tgz")
        try? fm.removeItem(at: dest)

        let result: Result<URL, Error>
        do {
            try fm.moveItem(at: location, to: dest)
            result = .success(dest)
        } catch {
            result = .failure(error)
        }
        Task { @MainActor in
            self.resumeContinuation(with: result)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        Task { @MainActor in
            self.resumeContinuation(with: .failure(error))
        }
    }
}
