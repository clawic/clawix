import AppKit
import Foundation
import SwiftTerm

/// One live shell. Owns a `LocalProcessTerminalView` (an NSView) which
/// internally manages the PTY (forkpty), the read loop, the parser, the
/// renderer, and SIGWINCH on resize. We don't reimplement any of that;
/// we just hold the view, drive its delegate via a small Coordinator
/// (to avoid retain cycles), and translate between SwiftTerm's
/// callbacks and our `@Published` status.
@MainActor
final class TerminalSession: ObservableObject, Identifiable {
    let id: UUID
    let chatId: UUID
    let initialCwd: String

    @Published var label: String
    @Published var status: Status = .starting

    let terminalView: LocalProcessTerminalView
    private let coordinator: Coordinator
    private var hasStarted = false

    enum Status: Equatable {
        case starting
        case running
        case exited(Int32?)
        case missingCwd
    }

    init(
        id: UUID,
        chatId: UUID,
        initialCwd: String,
        label: String,
        font: NSFont? = nil
    ) {
        self.id = id
        self.chatId = chatId
        self.initialCwd = initialCwd
        self.label = label

        let view = LocalProcessTerminalView(frame: .zero)
        view.font = font ?? TerminalSession.defaultFont
        view.translatesAutoresizingMaskIntoConstraints = false
        self.terminalView = view

        let coordinator = Coordinator()
        self.coordinator = coordinator
        coordinator.session = self
        view.processDelegate = coordinator
    }

    /// Default monospaced font for new sessions. macOS' system mono
    /// (SF Mono) keeps consistent letter-spacing across weight changes
    /// which keeps the cursor aligned in vim/htop.
    static var defaultFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    }

    /// Send `signal` to the child shell (and, by virtue of the controlling
    /// terminal, to its process group). SwiftTerm exposes the underlying
    /// `LocalProcess`, but for cross-version safety we resolve the PID
    /// reflectively. Returns true on success.
    @discardableResult
    func sendSignal(_ signal: Int32) -> Bool {
        guard let pid = currentShellPid(), pid > 0 else { return false }
        return kill(pid, signal) == 0
    }

    func sendText(_ text: String) {
        let bytes = Array(text.utf8)
        terminalView.process.send(data: ArraySlice(bytes))
    }

    func runCommand(_ command: String) {
        startIfNeeded()
        let resolvedCwd = TerminalSession.resolveCwd(initialCwd)
        terminalView.feed(text: "\r\n$ \(command)\r\n")
        terminalView.needsDisplay = true
        Task.detached { [weak self] in
            let output = Self.runShellCommand(command, cwd: resolvedCwd)
            await self?.appendCommandOutput(output)
        }
    }

    /// Try to read the child PID from SwiftTerm's `LocalProcess` via
    /// `Mirror`. SwiftTerm exposes the property as `shellPid` on most
    /// recent versions; the reflective lookup keeps us forward-compatible
    /// across renames.
    private func currentShellPid() -> pid_t? {
        let mirror = Mirror(reflecting: terminalView)
        for child in mirror.children {
            guard child.label == "process" else { continue }
            let processMirror = Mirror(reflecting: child.value)
            for processChild in processMirror.children {
                if processChild.label == "shellPid",
                   let pid = processChild.value as? pid_t {
                    return pid
                }
            }
        }
        return nil
    }

    /// Spawn (or respawn) the shell in `initialCwd`. Falls back to
    /// `$HOME` if the cwd no longer exists.
    func restart() {
        hasStarted = false
        spawnShell()
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        spawnShell()
    }

    private func spawnShell() {
        guard !hasStarted else { return }
        hasStarted = true
        let resolvedCwd = TerminalSession.resolveCwd(initialCwd)
        if resolvedCwd != initialCwd {
            status = .missingCwd
        } else {
            status = .starting
        }

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let env = TerminalSession.composeEnvironment()

        let loginName = "-" + URL(fileURLWithPath: shell).lastPathComponent

        // Prefix argv[0] with `-` to request a login shell. SwiftTerm
        // already injects argv[0], so `args` must not repeat `shell`.
        terminalView.startProcess(
            executable: shell,
            args: [],
            environment: env,
            execName: loginName,
            currentDirectory: resolvedCwd
        )
        if status != .missingCwd {
            status = .running
        }
    }

    private static func resolveCwd(_ cwd: String) -> String {
        let expanded = (cwd as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expanded) {
            return expanded
        }
        return NSHomeDirectory()
    }

    private static func composeEnvironment() -> [String] {
        // Hand-roll the env so we don't depend on the exact name of
        // SwiftTerm's helper across versions. Inherit the bare minimum
        // the user's shell needs and override TERM / COLORTERM so
        // `vim`, `htop`, `bat` and friends pick up 256-color truecolor
        // rendering.
        let processEnv = ProcessInfo.processInfo.environment
        var env: [String] = []
        let inherit = ["HOME", "USER", "LOGNAME", "PATH", "SHELL", "TMPDIR", "DISPLAY", "SSH_AUTH_SOCK"]
        for key in inherit {
            if let value = processEnv[key] {
                env.append("\(key)=\(value)")
            }
        }
        env.append("TERM=xterm-256color")
        env.append("COLORTERM=truecolor")
        env.append("TERM_PROGRAM=Clawix")
        env.append("LC_TERMINAL=Clawix")
        let lang = processEnv["LANG"].flatMap(TerminalSession.validLocale) ?? "en_US.UTF-8"
        env.append("LANG=\(lang)")
        if let lcAll = processEnv["LC_ALL"].flatMap(TerminalSession.validLocale) {
            env.append("LC_ALL=\(lcAll)")
        }
        return env
    }

    private static func validLocale(_ locale: String) -> String? {
        locale.contains(".") ? locale : nil
    }

    nonisolated private static func runShellCommand(_ command: String, cwd: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return "Failed to run command: \(error.localizedDescription)\n"
        }
    }

    private func appendCommandOutput(_ output: String) {
        guard !output.isEmpty else { return }
        terminalView.feed(text: output)
        if !output.hasSuffix("\n") {
            terminalView.feed(text: "\r\n")
        }
        terminalView.needsDisplay = true
    }

    fileprivate func handleProcessTerminated(exitCode: Int32?) {
        status = .exited(exitCode)
    }

    fileprivate func handleHostNameUpdate(_ host: String) {
        // The user can rename a tab manually; only auto-update the
        // label if the user hasn't customized it (we keep it
        // conservative and ignore host updates entirely for now).
        _ = host
    }

    fileprivate func handleTitleUpdate(_ title: String) {
        // Same reasoning as above — we don't override the label from
        // the shell's title escape sequences. The user controls the
        // label via double-click rename.
        _ = title
    }

    /// Bridge between SwiftTerm's class-bound delegate protocol and
    /// our struct-friendly session. Keeps a `weak` reference to the
    /// session so the session's deinit isn't blocked by the view's
    /// strong retention of its delegate.
    @MainActor
    private final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        weak var session: TerminalSession?

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
            _ = (newCols, newRows)
        }

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            session?.handleTitleUpdate(title)
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            if let directory { session?.handleHostNameUpdate(directory) }
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            session?.handleProcessTerminated(exitCode: exitCode)
        }
    }
}
