import Foundation

/// Streams a single user prompt against the local Ollama daemon and
/// pipes the assistant reply back into `AppState` through the same
/// `appendAssistantPlaceholder` / `appendAssistantDelta` /
/// `streamingFinished` pipeline the Codex backend uses. This is the
/// non-Codex path: when the user picks an Ollama model in the composer,
/// `AppState.sendMessage()` routes here instead of the Clawix service.
@MainActor
final class LocalModelChat {

    static let shared = LocalModelChat()

    /// Per-chat in-flight task so a second submit on the same chat
    /// can cancel the first cleanly (matches the Codex path's behavior
    /// on `sendUserMessage`).
    private var inFlight: [UUID: Task<Void, Never>] = [:]

    private init() {}

    func send(
        chatId: UUID,
        model: String,
        history: [ChatMessage],
        appState: AppState
    ) {
        cancel(chatId: chatId)
        guard let assistantId = appState.appendAssistantPlaceholder(chatId: chatId) else { return }

        let task = Task { @MainActor [weak self] in
            do {
                let stream = LocalModelsClient.shared.chat(
                    model: model,
                    messages: history.map { msg in
                        LocalModelsClient.ChatMessage(
                            role: msg.role == .user ? "user" : "assistant",
                            content: msg.content
                        )
                    }
                )
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    if !chunk.isEmpty {
                        appState.appendAssistantDelta(chatId: chatId, delta: chunk)
                    }
                }
                appState.flushPendingAssistantTextDeltas()
                appState.markAssistantFinished(chatId: chatId, messageId: assistantId)
            } catch {
                appState.flushPendingAssistantTextDeltas()
                appState.markAssistantFailed(
                    chatId: chatId,
                    messageId: assistantId,
                    error: error.localizedDescription
                )
            }
            self?.inFlight[chatId] = nil
        }
        inFlight[chatId] = task
    }

    func cancel(chatId: UUID) {
        inFlight[chatId]?.cancel()
        inFlight[chatId] = nil
    }
}
