import Foundation

/// OpenAI Chat Completions implementation. Uses the modern
/// `gpt-4o-mini` family by default; user can pick any chat-capable
/// model via the picker. API key lives in Keychain.
struct OpenAIEnhancementProvider: EnhancementProvider {
    let id: EnhancementProviderID = .openai

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

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = TimeInterval(max(3, min(120, timeoutSeconds)))

        let userMessage = composeUserMessage(text: text, prompt: userPrompt, context: context)
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
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

        struct CompletionResponse: Decodable {
            struct Choice: Decodable { struct Msg: Decodable { let content: String? }; let message: Msg }
            let choices: [Choice]
        }
        do {
            let decoded = try JSONDecoder().decode(CompletionResponse.self, from: data)
            return decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""
        } catch {
            throw EnhancementError.decoding(error.localizedDescription)
        }
    }
}
