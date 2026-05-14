import Foundation

/// OpenAI Chat Completions implementation. Uses the modern
/// `gpt-4o-mini` family by default; user can pick any chat-capable
/// model via the picker.
struct OpenAIEnhancementProvider: EnhancementProvider {
    let id: EnhancementProviderID = .openai

    func isConfigured() async -> Bool {
        await EnhancementSecrets.hasAPIKey(for: id)
    }

    func enhance(
        text: String,
        systemPrompt: String,
        userPrompt: String,
        model: String,
        context: EnhancementContext?,
        timeoutSeconds: Int
    ) async throws -> String {
        guard await EnhancementSecrets.hasAPIKey(for: id) else {
            throw EnhancementError.notConfigured
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        let userMessage = composeUserMessage(text: text, prompt: userPrompt, context: context)
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        guard let bodyText = String(data: bodyData, encoding: .utf8) else {
            throw EnhancementError.decoding("Unable to encode request body.")
        }

        let response = try await SystemSecrets.brokerHttp(
            internalName: EnhancementSecrets.internalName(for: id),
            method: "POST",
            url: url,
            headers: [
                "Content-Type": "application/json",
                "Authorization": "Bearer {{\(EnhancementSecrets.internalName(for: id)).value}}"
            ],
            body: bodyText,
            agent: "clawix-enhancement",
            riskTier: "cost",
            approvalSatisfied: true,
            timeoutMs: max(3, min(120, timeoutSeconds)) * 1000
        )
        guard response.ok else {
            throw EnhancementError.http(response.status ?? 0, response.bodyText ?? "")
        }
        guard let responseBody = response.bodyText, let data = responseBody.data(using: .utf8) else {
            throw EnhancementError.decoding("Empty broker response.")
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
