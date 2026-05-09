import Foundation
import SwiftUI

/// Observable wrapper around `TelegramServiceClient`. The Settings page
/// holds one as a `@StateObject` and binds its `bots` array to the
/// master pane. A 5s refresh task runs while the page is on screen and
/// is cancelled on disappear.
@MainActor
final class TelegramServiceManager: ObservableObject {

    @Published private(set) var bots: [TelegramBot] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    /// Per-bot inflight markers so the UI can disable buttons while an
    /// action is running. Keyed by bot.id.
    @Published private(set) var inflight: Set<String> = []

    /// Per-bot last action result (envelope) so the UI can render
    /// stderr / stdout if a CLI call failed. Keyed by bot.id.
    @Published private(set) var lastActionResult: [String: ClawCliResult] = [:]

    /// Per-bot fetched chats. Populated lazily when the user opens the
    /// detail pane. Keyed by bot.id.
    @Published private(set) var chats: [String: [TelegramKnownChat]] = [:]

    /// Per-bot fetched commands. Populated lazily.
    @Published private(set) var commands: [String: [TelegramCommandSpec]] = [:]

    private let client: TelegramServiceClient
    private var refreshTask: Task<Void, Never>?

    init(client: TelegramServiceClient = TelegramServiceClient()) {
        self.client = client
    }

    // MARK: - Lifecycle

    func startRefreshing() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { return }
                await self.refresh()
            }
        }
    }

    func stopRefreshing() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func resetForUnavailableService() {
        refreshTask?.cancel()
        refreshTask = nil
        bots = []
        isLoading = false
        lastError = nil
    }

    // MARK: - Listing

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let next = try await client.listBots()
            self.bots = next
            self.lastError = nil
        } catch {
            self.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Actions

    @discardableResult
    func registerBot(
        secretName: String,
        accountId: String?,
        label: String?
    ) async -> Result<ClawCliResult, Swift.Error> {
        do {
            let result = try await client.registerBot(
                secretName: secretName,
                accountId: accountId,
                label: label
            )
            await refresh()
            return .success(result)
        } catch {
            return .failure(error)
        }
    }

    func startPolling(_ bot: TelegramBot) async {
        await runAction(bot: bot) { try await self.client.startPolling(botId: bot.id) }
    }

    func stopPolling(_ bot: TelegramBot) async {
        await runAction(bot: bot) { try await self.client.stopPolling(botId: bot.id) }
    }

    func setWebhook(_ bot: TelegramBot, url: String, secretToken: String?) async {
        await runAction(bot: bot) {
            try await self.client.setWebhook(
                botId: bot.id,
                url: url,
                secretToken: secretToken
            )
        }
    }

    func clearWebhook(_ bot: TelegramBot) async {
        await runAction(bot: bot) { try await self.client.clearWebhook(botId: bot.id) }
    }

    func reloadCommands(_ bot: TelegramBot) async {
        do {
            let envelope = try await client.getCommands(botId: bot.id)
            commands[bot.id] = TelegramCommandSpec.extract(from: envelope.json)
            lastActionResult[bot.id] = envelope
        } catch {
            lastActionResult[bot.id] = ClawCliResult(
                ok: false,
                exitCode: nil,
                stdout: "",
                stderr: error.localizedDescription,
                json: nil
            )
        }
    }

    func saveCommands(_ bot: TelegramBot, commands: [TelegramCommandSpec]) async {
        await runAction(bot: bot) {
            try await self.client.setCommands(botId: bot.id, commands: commands)
        }
        await reloadCommands(bot)
    }

    func reloadChats(_ bot: TelegramBot, query: String? = nil) async {
        do {
            let envelope = try await client.listChats(botId: bot.id, query: query)
            chats[bot.id] = TelegramChatsExtractor.extract(from: envelope.json)
            lastActionResult[bot.id] = envelope
        } catch {
            lastActionResult[bot.id] = ClawCliResult(
                ok: false,
                exitCode: nil,
                stdout: "",
                stderr: error.localizedDescription,
                json: nil
            )
        }
    }

    func sendMessage(
        _ bot: TelegramBot,
        chatId: String,
        text: String,
        parseMode: String? = nil
    ) async {
        await runAction(bot: bot) {
            try await self.client.sendMessage(
                botId: bot.id,
                chatId: chatId,
                body: .text(text),
                parseMode: parseMode
            )
        }
    }

    // MARK: - Internal

    private func runAction(
        bot: TelegramBot,
        _ work: @escaping () async throws -> ClawCliResult
    ) async {
        inflight.insert(bot.id)
        defer { inflight.remove(bot.id) }
        do {
            let envelope = try await work()
            lastActionResult[bot.id] = envelope
        } catch {
            lastActionResult[bot.id] = ClawCliResult(
                ok: false,
                exitCode: nil,
                stdout: "",
                stderr: error.localizedDescription,
                json: nil
            )
        }
        await refresh()
    }
}
