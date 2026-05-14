import Foundation

/// Anthropic Messages API implementation. Distinct shape from OpenAI:
/// system prompt is its own top-level field (not a chat role) and
/// every model id starts with `claude-`. Defaults to `claude-haiku-4-5`
/// because it's the cheapest of the 4.x family while still producing
/// good text-cleanup output.
struct AnthropicEnhancementProvider: EnhancementProvider {
    let id: EnhancementProviderID = .anthropic

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

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
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
                "x-api-key": "{{\(EnhancementSecrets.internalName(for: id)).value}}",
                "anthropic-version": "2023-06-01"
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
