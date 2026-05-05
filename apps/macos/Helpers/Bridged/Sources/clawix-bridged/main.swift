import Foundation
import Combine
import ClawixCore
import ClawixEngine

/// Placeholder `EngineHost` until the AgentBackend layer (codex
/// subprocess wrapper, RolloutReader, SessionsIndex, persistence
/// repos) is migrated into `ClawixEngine`. Returns an empty chats
/// list and turns every inbound mutation into a no-op so the daemon
/// can run end-to-end against an iPhone today: pair, auth, get an
/// empty `chatsSnapshot`, and stay connected without crashing.
@MainActor
final class EmptyEngineHost: EngineHost {
    private let chatsSubject = CurrentValueSubject<[BridgeChatSnapshot], Never>([])

    var bridgeChatsCurrent: [BridgeChatSnapshot] { chatsSubject.value }
    var bridgeChatsPublisher: AnyPublisher<[BridgeChatSnapshot], Never> {
        chatsSubject.eraseToAnyPublisher()
    }

    func handleHydrateHistory(chatId: UUID) {
        // No backing rollout reader yet.
    }

    func handleSendPrompt(chatId: UUID, text: String) {
        // Redacted log: chatId is a UUID (no PII), text length only.
        // Never log the prompt body — rollouts already capture user
        // content where it belongs, no reason to duplicate it on
        // /tmp/clawix-bridged.err where any local user can read it.
        let shortId = chatId.uuidString.prefix(8)
        FileHandle.standardError.write(Data(
            "[clawix-bridged] sendPrompt chat=\(shortId) len=\(text.count) dropped (stub host)\n"
                .utf8
        ))
    }
}

/// Bearer-tolerant log line. Truncates anything that looks like a 32+
/// char base64url token (the shape `PairingService` produces) so a
/// dev `tail -f /tmp/clawix-bridged.err` can't accidentally surface
/// the iPhone's shared secret.
func bridgedLog(_ message: String) {
    let redacted = redactBearer(in: message)
    FileHandle.standardError.write(Data((redacted + "\n").utf8))
}

private func redactBearer(in s: String) -> String {
    // 32+ chars of [A-Za-z0-9_-] with no surrounding alphanum:
    // good-enough match for the base64url-encoded 32-byte tokens.
    guard let regex = try? NSRegularExpression(
        pattern: "(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{32,}(?![A-Za-z0-9_-])"
    ) else { return s }
    let range = NSRange(s.startIndex..., in: s)
    return regex.stringByReplacingMatches(
        in: s, range: range, withTemplate: "<redacted>"
    )
}

// MARK: - Entrypoint

FileHandle.standardError.write(Data(
    "[clawix-bridged] starting (schemaVersion=\(bridgeSchemaVersion))\n".utf8
))

let port: UInt16 = ProcessInfo.processInfo.environment["CLAWIX_BRIDGED_PORT"]
    .flatMap { UInt16($0) } ?? 7778

// `BridgeServer` is `@MainActor`; run startup on the main actor
// synchronously by hopping into a Task and parking the main thread on
// the runloop afterwards.
let dispatchedHostBox = HostBox()

Task { @MainActor in
    let host = EmptyEngineHost()
    // The stub host has no chats, so we deliberately do NOT publish
    // Bonjour: a fresh iPhone scanning the LAN would otherwise race
    // between the GUI's real BridgeServer and this empty daemon and
    // half the time land here. Once the daemon owns real chat state
    // (Phase 3), it becomes the single source of truth and
    // re-enables Bonjour.
    let server = BridgeServer(host: host, port: port, publishBonjour: false)
    server.start()
    dispatchedHostBox.host = host
    dispatchedHostBox.server = server
    FileHandle.standardError.write(Data(
        "[clawix-bridged] bridge listening on tcp/\(port). SIGTERM to stop.\n".utf8
    ))
}

// Pin the process. launchd will SIGTERM us when the user toggles the
// LaunchAgent off; SIGINT works in dev (`bash` in foreground).
RunLoop.current.run()

/// Tiny holder so the host + server outlive the bootstrap Task.
/// `RunLoop.current.run()` blocks the main thread while the network
/// events keep flowing on the main run loop, so the references just
/// need to exist somewhere; this box is that somewhere.
final class HostBox: @unchecked Sendable {
    var host: AnyObject?
    var server: AnyObject?
}
