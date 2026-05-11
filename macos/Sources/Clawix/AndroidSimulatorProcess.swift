import Foundation
import Darwin

extension AndroidSimulatorFramebufferController {
    nonisolated static func runTool(
        _ executable: String,
        _ arguments: [String],
        captureBinary: Bool = false,
        timeout: TimeInterval = 20
    ) async throws -> AndroidToolResult {
        try await Task.detached(priority: .userInitiated) {
            try Self.runToolSync(executable, arguments, captureBinary: captureBinary, timeout: timeout)
        }.value
    }

    nonisolated static func runToolSync(
        _ executable: String,
        _ arguments: [String],
        captureBinary: Bool = false,
        timeout: TimeInterval = 20
    ) throws -> AndroidToolResult {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let token = UUID().uuidString
        let stdoutURL = tempDir.appendingPathComponent("clawix-android-\(token).stdout")
        let stderrURL = tempDir.appendingPathComponent("clawix-android-\(token).stderr")
        defer {
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
        }

        let stdoutFD = open(stdoutURL.path, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR)
        guard stdoutFD >= 0 else {
            throw AndroidSimulatorError.commandFailed("Could not create Android stdout capture file.")
        }
        let stderrFD = open(stderrURL.path, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR)
        guard stderrFD >= 0 else {
            close(stdoutFD)
            throw AndroidSimulatorError.commandFailed("Could not create Android stderr capture file.")
        }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, stdoutFD, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, stderrFD, STDERR_FILENO)

        var pid: pid_t = 0
        var cArguments = ([executable] + arguments).map { strdup($0) }
        cArguments.append(nil)
        defer {
            for pointer in cArguments where pointer != nil {
                free(pointer)
            }
        }
        let environmentStrings: [String] = ProcessInfo.processInfo.environment.map { key, value in
            "\(key)=\(value)"
        }
        var cEnvironment: [UnsafeMutablePointer<CChar>?] = environmentStrings.map { strdup($0) }
        cEnvironment.append(nil)
        defer {
            for pointer in cEnvironment where pointer != nil {
                free(pointer)
            }
        }

        let spawnStatus = cArguments.withUnsafeMutableBufferPointer { buffer -> Int32 in
            cEnvironment.withUnsafeMutableBufferPointer { envBuffer -> Int32 in
                posix_spawn(&pid, executable, &actions, nil, buffer.baseAddress, envBuffer.baseAddress)
            }
        }
        close(stdoutFD)
        close(stderrFD)

        guard spawnStatus == 0 else {
            throw AndroidSimulatorError.commandFailed(String(cString: strerror(spawnStatus)))
        }

        var waitStatus: Int32 = 0
        func pollUntil(_ deadline: Date) throws -> Bool {
            while Date() < deadline {
                let result = waitpid(pid, &waitStatus, WNOHANG)
                if result == pid { return true }
                if result == -1 {
                    if errno == EINTR { continue }
                    throw AndroidSimulatorError.commandFailed(String(cString: strerror(errno)))
                }
                usleep(20_000)
            }
            return false
        }

        if try !pollUntil(Date().addingTimeInterval(timeout)) {
            kill(pid, SIGTERM)
            if try !pollUntil(Date().addingTimeInterval(1)) {
                kill(pid, SIGKILL)
                _ = try? pollUntil(Date().addingTimeInterval(1))
            }
            throw AndroidSimulatorError.commandFailed("Android command timed out: \(URL(fileURLWithPath: executable).lastPathComponent) \(arguments.joined(separator: " "))")
        }

        let outData = (try? Data(contentsOf: stdoutURL)) ?? Data()
        let errData = (try? Data(contentsOf: stderrURL)) ?? Data()
        let out = captureBinary ? "" : (String(data: outData, encoding: .utf8) ?? "")
        let err = String(data: errData, encoding: .utf8) ?? ""
        let terminationStatus: Int32
        if waitStatus & 0x7f == 0 {
            terminationStatus = (waitStatus >> 8) & 0xff
        } else {
            terminationStatus = 128 + (waitStatus & 0x7f)
        }
        return AndroidToolResult(
            status: terminationStatus,
            stdout: out,
            stdoutData: outData,
            stderr: err
        )
    }
}
