import Foundation

/// Anthropic Messages API implementation. Distinct shape from OpenAI:
/// system prompt is its own top-level field (not a chat role) and
/// every model id starts with `claude-`. Defaults to `claude-haiku-4-5`
/// because it's the cheapest of the 4.x family while still producing
/// good text-cleanup output.
struct AnthropicEnhancementProvider: EnhancementProvider {
    let id: EnhancementProviderID = .anthropic

    func isConfigured() -> Bool {
        EnhancementKeychain.hasAPIKey(for: id)
    }

    func enhance(
        text: String,
        systemPrompt: String,
        userPrompt: String,
        model: String,
        context: EnhancementContext?,
        timeoutSeconds: Int
    ) async throws -> String {
        guard let key = EnhancementKeychain.apiKey(for: id) else {
            throw EnhancementError.notConfigured
        }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = TimeInterval(max(3, min(120, timeoutSeconds)))

        let userMessage = composeUserMessage(text: text, prompt: userPrompt, context: context)
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "temperature": 0.2,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw EnhancementError.http(http.statusCode, bodyText)
        }

        struct MessagesResponse: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
        }
        do {
            let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
            // Concatenate every text block — Anthropic returns an array
            // and tool-use messages can interleave text blocks.
            return decoded.content
                .filter { $0.type == "text" }
                .compactMap(\.text)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw EnhancementError.decoding(error.localizedDescription)
        }
    }
}
