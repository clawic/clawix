import Foundation

/// Shared OpenAI-compatible chat-completions implementation. Groq,
/// Mistral, xAI, OpenRouter and the user's "Custom" endpoint all
/// expose the same `/v1/chat/completions` shape that OpenAI defined,
/// so a single body builder + decoder covers them all. Each
/// concrete provider only contributes its base URL, headers, and
/// API-key handling.
struct OpenAICompatibleClient {
    let baseURL: URL
    let extraHeaders: [String: String]
    let apiKey: String?
    /// Ollama and a few self-hosted endpoints expose
    /// `/v1/chat/completions` as well; `endpointPath` lets the same
    /// client target either OpenAI-style (`/chat/completions`) or
    /// Ollama-style (`/api/chat`) without forking the body.
    let endpointPath: String

    init(
        baseURL: URL,
        apiKey: String?,
        extraHeaders: [String: String] = [:],
        endpointPath: String = "/chat/completions"
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.extraHeaders = extraHeaders
        self.endpointPath = endpointPath
    }

    func enhance(
        text: String,
        systemPrompt: String,
        userPrompt: String,
        model: String,
        context: EnhancementContext?,
        timeoutSeconds: Int,
        composeUser: (String, String, EnhancementContext?) -> String
    ) async throws -> String {
        let url = baseURL.appendingPathComponent(endpointPath)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        for (k, v) in extraHeaders {
            request.setValue(v, forHTTPHeaderField: k)
        }
        request.timeoutInterval = TimeInterval(max(3, min(120, timeoutSeconds)))

        let userMessage = composeUser(text, userPrompt, context)
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
            return decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            throw EnhancementError.decoding(error.localizedDescription)
        }
    }
}

// MARK: - Groq

struct GroqEnhancementProvider: EnhancementProvider {
    let id: EnhancementProviderID = .groq

    func isConfigured() async -> Bool { await EnhancementSecrets.hasAPIKey(for: id) }

    func enhance(
        text: String,
        systemPrompt: String,
        userPrompt: String,
        model: String,
        context: EnhancementContext?,
        timeoutSeconds: Int
    ) async throws -> String {
        guard let key = await EnhancementSecrets.apiKey(for: id) else {
            throw EnhancementError.notConfigured
        }
        let client = OpenAICompatibleClient(
            baseURL: URL(string: "https://api.groq.com/openai/v1")!,
            apiKey: key
        )
        return try await client.enhance(
            text: text,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            model: model,
            context: context,
            timeoutSeconds: timeoutSeconds,
            composeUser: { self.composeUserMessage(text: $0, prompt: $1, context: $2) }
        )
    }
}

// MARK: - Mistral

struct MistralEnhancementProvider: EnhancementProvider {
    let id: EnhancementProviderID = .mistral

    func isConfigured() async -> Bool { await EnhancementSecrets.hasAPIKey(for: id) }

    func enhance(
        text: String,
        systemPrompt: String,
        userPrompt: String,
        model: String,
        context: EnhancementContext?,
        timeoutSeconds: Int
    ) async throws -> String {
        guard let key = await EnhancementSecrets.apiKey(for: id) else {
            throw EnhancementError.notConfigured
        }
        let client = OpenAICompatibleClient(
            baseURL: URL(string: "https://api.mistral.ai/v1")!,
            apiKey: key
        )
        return try await client.enhance(
            text: text,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            model: model,
            context: context,
            timeoutSeconds: timeoutSeconds,
            composeUser: { self.composeUserMessage(text: $0, prompt: $1, context: $2) }
        )
    }
}

// MARK: - xAI

struct XAIEnhancementProvider: EnhancementProvider {
    let id: EnhancementProviderID = .xai

    func isConfigured() async -> Bool { await EnhancementSecrets.hasAPIKey(for: id) }

    func enhance(
        text: String,
        systemPrompt: String,
        userPrompt: String,
        model: String,
        context: EnhancementContext?,
        timeoutSeconds: Int
    ) async throws -> String {
        guard let key = await EnhancementSecrets.apiKey(for: id) else {
            throw EnhancementError.notConfigured
        }
        let client = OpenAICompatibleClient(
            baseURL: URL(string: "https://api.x.ai/v1")!,
            apiKey: key
        )
        return try await client.enhance(
            text: text,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            model: model,
            context: context,
            timeoutSeconds: timeoutSeconds,
            composeUser: { self.composeUserMessage(text: $0, prompt: $1, context: $2) }
        )
    }
}

// MARK: - OpenRouter

struct OpenRouterEnhancementProvider: EnhancementProvider {
    let id: EnhancementProviderID = .openrouter

    func isConfigured() async -> Bool { await EnhancementSecrets.hasAPIKey(for: id) }

    func enhance(
        text: String,
        systemPrompt: String,
        userPrompt: String,
        model: String,
        context: EnhancementContext?,
        timeoutSeconds: Int
    ) async throws -> String {
        guard let key = await EnhancementSecrets.apiKey(for: id) else {
            throw EnhancementError.notConfigured
        }
        // OpenRouter recommends a referer + title for analytics; we
        // identify Clawix so the dashboard doesn't show "unknown".
        let client = OpenAICompatibleClient(
            baseURL: URL(string: "https://openrouter.ai/api/v1")!,
            apiKey: key,
            extraHeaders: [
                "HTTP-Referer": "https://github.com/clawic/clawix",
                "X-Title": "Clawix"
            ]
        )
        return try await client.enhance(
            text: text,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            model: model,
            context: context,
            timeoutSeconds: timeoutSeconds,
            composeUser: { self.composeUserMessage(text: $0, prompt: $1, context: $2) }
        )
    }
}

// MARK: - Custom (user-supplied OpenAI-compatible endpoint)

struct CustomEnhancementProvider: EnhancementProvider {
    let id: EnhancementProviderID = .custom

    func isConfigured() async -> Bool {
        // Custom requires at minimum a base URL; API key is optional
        // (some self-hosted gateways don't authenticate locally).
        guard let raw = UserDefaults.standard.string(
            forKey: EnhancementSettings.baseURLKey(for: id.rawValue)
        ), !raw.isEmpty,
            URL(string: raw) != nil
        else { return false }
        return true
    }

    func enhance(
        text: String,
        systemPrompt: String,
        userPrompt: String,
        model: String,
        context: EnhancementContext?,
        timeoutSeconds: Int
    ) async throws -> String {
        let raw = UserDefaults.standard.string(
            forKey: EnhancementSettings.baseURLKey(for: id.rawValue)
        ) ?? ""
        guard let baseURL = URL(string: raw) else {
            throw EnhancementError.notConfigured
        }
        let key = await EnhancementSecrets.apiKey(for: id) // may be nil
        let client = OpenAICompatibleClient(baseURL: baseURL, apiKey: key)
        return try await client.enhance(
            text: text,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            model: model,
            context: context,
            timeoutSeconds: timeoutSeconds,
            composeUser: { self.composeUserMessage(text: $0, prompt: $1, context: $2) }
        )
    }
}
