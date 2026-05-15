import Foundation
import SwiftUI
import AppKit
import Combine

/// Tracks the local runtime auth state and drives the login / logout
/// flows. The single source of truth is the runtime auth file: presence
/// (with a parseable id_token) means logged in; absence means logged out.
///
/// The coordinator watches that file with a DispatchSource on the parent
/// directory so external login / logout invocations (CLI
/// in another terminal, OAuth callback that just landed) flip the UI in
/// near real time without polling.
final class BackendAuthCoordinator: ObservableObject {
    @Published private(set) var accountProfile: BackendAccountProfile? = nil
    @Published private(set) var loginInProgress: Bool = false
    @Published private(set) var loginError: String? = nil

    private var loginProcess: Process?
    private var watchSource: DispatchSourceFileSystemObject?
    private var dirHandle: Int32 = -1

    var isLoggedIn: Bool { accountProfile != nil }

    func bootstrap() {
        ensureBackendDirectoryExists()
        // Synchronous initial read on main so the very first frame already
        // reflects the real auth state. Any async dispatch here lets the UI
        // paint LoginGateView for one frame even when credentials exist.
        let initial = BackendAuthReader.read()
        self.accountProfile = initial.email != nil ? initial : nil
        startWatchingAuthFile()
    }

    /// Re-reads `auth.json` and republishes the result on the main queue.
    func refresh() {
        let next = BackendAuthReader.read()
        let newProfile = next.email != nil ? next : nil
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.accountProfile != newProfile { self.accountProfile = newProfile }
        }
    }

    // MARK: - Login

    /// Spawns runtime login and lets the user finish OAuth in the browser.
    /// Auth state flips via the file watcher when `auth.json` lands.
    func startLogin(binary: ClawixBinaryResolution) {
        guard !loginInProgress else { return }
        DispatchQueue.main.async {
            self.loginError = nil
            self.loginInProgress = true
        }

        let proc = Process()
        proc.executableURL = binary.path
        proc.arguments = ["login"]
        let errPipe = Pipe()
        proc.standardOutput = Pipe()
        proc.standardError = errPipe

        // The runtime binary itself does the OAuth dance and shells out to
        // `open` to launch the browser. Make sure system PATH is exposed
        // even though we launch with an absolute executable URL.
        var env = ProcessInfo.processInfo.environment
        let path = env["PATH"] ?? ""
        if !path.contains("/usr/bin") {
            env["PATH"] = path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        }
        proc.environment = env

        proc.terminationHandler = { [weak self] p in
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            DispatchQueue.main.async {
                guard let self else { return }
                self.loginInProgress = false
                self.loginProcess = nil
                self.refresh()
                let exitedWithError = p.terminationStatus != 0
                    && p.terminationReason != .uncaughtSignal
                if self.accountProfile == nil, exitedWithError {
                    let stderr = String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    self.loginError = (stderr?.isEmpty == false ? stderr : nil)
                        ?? L10n.t("Could not sign in.")
                }
            }
        }

        do {
            try proc.run()
            loginProcess = proc
        } catch {
            DispatchQueue.main.async {
                self.loginInProgress = false
                self.loginError = L10n.signInFailed(error.localizedDescription)
            }
        }
    }

    /// User abandoned the OAuth flow. Killing the child process tears
    /// down the local listener so a future login attempt isn't blocked
    /// on the loopback port.
    func cancelLogin() {
        loginProcess?.terminate()
        loginProcess = nil
        DispatchQueue.main.async {
            self.loginInProgress = false
        }
    }

    // MARK: - Logout

    /// Runs runtime logout, which deletes `auth.json`. We optimistically
    /// clear the UI state so the login screen appears instantly even if
    /// the runtime CLI is slow to spin up; the file watcher will reconfirm.
    func logout(binary: ClawixBinaryResolution) {
        DispatchQueue.main.async {
            self.accountProfile = nil
            self.loginError = nil
        }

        let proc = Process()
        proc.executableURL = binary.path
        proc.arguments = ["logout"]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        do {
            try proc.run()
        } catch {
            // Runtime CLI unreachable. Delete auth.json directly so the UI
            // is still in a consistent logged-out state.
            try? FileManager.default.removeItem(at: BackendAuthReader.authURL)
            refresh()
        }
    }

    // MARK: - File watching

    private func ensureBackendDirectoryExists() {
        let dir = BackendAuthReader.authURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
    }

    private func startWatchingAuthFile() {
        let dir = BackendAuthReader.authURL.deletingLastPathComponent()
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        dirHandle = fd

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .extend, .rename, .attrib],
            queue: DispatchQueue.global(qos: .utility)
        )
        src.setEventHandler { [weak self] in self?.refresh() }
        src.setCancelHandler { [weak self] in
            guard let self, self.dirHandle >= 0 else { return }
            close(self.dirHandle)
            self.dirHandle = -1
        }
        src.resume()
        watchSource = src
    }

    deinit {
        watchSource?.cancel()
        loginProcess?.terminate()
    }
}
