import Foundation
import ClawixCore

/// Ollama provider. No API key — just a local base URL. Default
/// `http://localhost:11434` which is what `ollama serve` listens on
/// out of the box. The `/api/chat` endpoint is the closest match to
/// the OpenAI chat-completions shape.
struct OllamaEnhancementProvider: EnhancementProvider {
    let id: EnhancementProviderID = .ollama

    func isConfigured() async -> Bool {
        // We don't ping the host here — that would block the settings
        // UI on the network. Treat configuration as "user has set a
        // base URL" and let the actual call surface a descriptive
        // error if the daemon isn't up.
        baseURL() != nil
    }

    private func baseURL() -> URL? {
        let raw = UserDefaults.standard.string(
            forKey: EnhancementSettings.baseURLKey(for: id.rawValue)
        ) ?? "http://localhost:11434"
        return URL(string: raw)
    }

    func enhance(
        text: String,
        systemPrompt: String,
        userPrompt: String,
        model: String,
        context: EnhancementContext?,
        timeoutSeconds: Int
    ) async throws -> String {
        guard let base = baseURL() else {
            throw EnhancementError.notConfigured
        }
        let url = base.appendingPathComponent(OllamaAPIRoute.chat)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = TimeInterval(max(3, min(120, timeoutSeconds)))

        let userMessage = composeUserMessage(text: text, prompt: userPrompt, context: context)
        // Ollama supports streaming by default — set `stream: false`
        // so we get a single JSON object back instead of NDJSON.
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "options": ["temperature": 0.2],
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw EnhancementError.http(http.statusCode, bodyText)
        }

        struct ChatResponse: Decodable {
            struct Msg: Decodable { let content: String? }
            let message: Msg?
        }
        do {
            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            return decoded.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            throw EnhancementError.decoding(error.localizedDescription)
        }
    }
}
