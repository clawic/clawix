import Foundation

/// HTTP client for the `@clawjs/telegram` surface. Mirrors
/// `ClawJSDatabaseClient.swift` in style. Talks to
/// `127.0.0.1:CLAWJS_TELEGRAM_PORT` (default 22011); the path layout
/// mirrors `clawjs/telegram/src/server/app.ts`.
struct TelegramServiceClient {

    enum Error: Swift.Error, LocalizedError {
        case invalidURL
        case http(status: Int, body: String?)
        case decoding(Swift.Error)
        case transport(Swift.Error)
        case cliFailure(stderr: String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Could not build a URL for the Telegram service."
            case .http(let status, let body):
                return "Telegram returned HTTP \(status)" + (body.map { ": \($0)" } ?? "")
            case .decoding(let error):
                return "Could not decode Telegram response: \(error.localizedDescription)"
            case .transport(let error):
                return "Could not reach Telegram service: \(error.localizedDescription)"
            case .cliFailure(let stderr):
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty
                    ? "Telegram CLI returned a non-zero exit code."
                    : "Telegram CLI: \(trimmed)"
            }
        }
    }

    let origin: URL

    init(origin: URL = URL(string: "http://127.0.0.1:\(ClawJSService.telegram.port)")!) {
        self.origin = origin
    }

    // MARK: - Health & list

    func probeHealth() async throws -> TelegramHealth {
        try await get("/v1/health")
    }

    private struct BotsResponse: Decodable {
        let workspace: String
        let bots: [TelegramBot]
    }

    func listBots() async throws -> [TelegramBot] {
        let response: BotsResponse = try await get("/v1/bots")
        return response.bots
    }

    // MARK: - Register a bot

    /// Wraps `claw channels telegram connect`. The Secrets vault must
    /// already contain the bot token under `secretName`. Returns the
    /// raw envelope so the UI can show the CLI stderr if the connect
    /// failed (e.g. secret not found, token invalid).
    func registerBot(
        secretName: String,
        accountId: String?,
        label: String?
    ) async throws -> ClawCliResult {
        var body: [String: Any] = ["secretName": secretName]
        if let accountId, !accountId.isEmpty { body["accountId"] = accountId }
        if let label, !label.isEmpty { body["label"] = label }
        return try await post("/v1/bots", body: body)
    }

    // MARK: - Per-bot actions

    func status(botId: String) async throws -> ClawCliResult {
        try await get("/v1/bots/\(escape(botId))/status")
    }

    func startPolling(
        botId: String,
        limit: Int? = nil,
        timeoutSeconds: Int? = nil,
        dropPendingUpdates: Bool? = nil
    ) async throws -> ClawCliResult {
        var body: [String: Any] = [:]
        if let limit { body["limit"] = limit }
        if let timeoutSeconds { body["timeoutSeconds"] = timeoutSeconds }
        if let dropPendingUpdates { body["dropPendingUpdates"] = dropPendingUpdates }
        return try await post("/v1/bots/\(escape(botId))/polling/start", body: body)
    }

    func stopPolling(botId: String) async throws -> ClawCliResult {
        try await post("/v1/bots/\(escape(botId))/polling/stop", body: [:])
    }

    func setWebhook(
        botId: String,
        url: String,
        secretToken: String? = nil,
        allowedUpdates: [String]? = nil,
        maxConnections: Int? = nil,
        ipAddress: String? = nil,
        dropPendingUpdates: Bool? = nil
    ) async throws -> ClawCliResult {
        var body: [String: Any] = ["url": url]
        if let secretToken, !secretToken.isEmpty { body["secretToken"] = secretToken }
        if let allowedUpdates { body["allowedUpdates"] = allowedUpdates }
        if let maxConnections { body["maxConnections"] = maxConnections }
        if let ipAddress, !ipAddress.isEmpty { body["ipAddress"] = ipAddress }
        if let dropPendingUpdates { body["dropPendingUpdates"] = dropPendingUpdates }
        return try await post("/v1/bots/\(escape(botId))/webhook", body: body)
    }

    func clearWebhook(
        botId: String,
        dropPendingUpdates: Bool? = nil
    ) async throws -> ClawCliResult {
        var body: [String: Any] = [:]
        if let dropPendingUpdates { body["dropPendingUpdates"] = dropPendingUpdates }
        return try await delete("/v1/bots/\(escape(botId))/webhook", body: body)
    }

    func getCommands(botId: String) async throws -> ClawCliResult {
        try await get("/v1/bots/\(escape(botId))/commands")
    }

    func setCommands(
        botId: String,
        commands: [TelegramCommandSpec]
    ) async throws -> ClawCliResult {
        let payload: [[String: String]] = commands.map { ["command": $0.command, "description": $0.description] }
        return try await post(
            "/v1/bots/\(escape(botId))/commands",
            body: ["commands": payload]
        )
    }

    func listChats(
        botId: String,
        query: String? = nil
    ) async throws -> ClawCliResult {
        var path = "/v1/bots/\(escape(botId))/chats"
        if let query, !query.isEmpty {
            let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            path += "?q=\(q)"
        }
        return try await get(path)
    }

    enum SendBody {
        case text(String)
        case media(url: String, kind: String, caption: String?)
    }

    func sendMessage(
        botId: String,
        chatId: String,
        body: SendBody,
        parseMode: String? = nil,
        replyToMessageId: Int64? = nil
    ) async throws -> ClawCliResult {
        var payload: [String: Any] = ["chatId": chatId]
        switch body {
        case .text(let text):
            payload["text"] = text
        case .media(let url, let kind, let caption):
            payload["media"] = url
            payload["mediaType"] = kind
            if let caption, !caption.isEmpty { payload["caption"] = caption }
        }
        if let parseMode { payload["parseMode"] = parseMode }
        if let replyToMessageId { payload["replyToMessageId"] = replyToMessageId }
        return try await post("/v1/bots/\(escape(botId))/messages", body: payload)
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await request(path: path, method: "GET", body: nil)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        try await request(path: path, method: "POST", body: body)
    }

    private func delete<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        try await request(path: path, method: "DELETE", body: body)
    }

    private func request<T: Decodable>(
        path: String,
        method: String,
        body: [String: Any]?
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: origin)?.absoluteURL else {
            throw Error.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body, !body.isEmpty {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } else if method != "GET" {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = "{}".data(using: .utf8)
        }
        req.timeoutInterval = 30

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw Error.transport(error)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // The action endpoints return 502 with the same envelope when
            // the wrapped CLI fails. Try to decode it so the caller can
            // still show stderr.
            if T.self == ClawCliResult.self,
               let envelope = try? JSONDecoder().decode(ClawCliResult.self, from: data) {
                return envelope as! T
            }
            let body = String(data: data, encoding: .utf8)
            throw Error.http(status: http.statusCode, body: body)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw Error.decoding(error)
        }
    }

    private func escape(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? component
    }
}
