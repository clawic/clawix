import AppKit
import SwiftUI

/// Settings page for the Telegram surface. Master-detail layout: bot
/// list on the left, full-bot detail on the right (Profile, Transport,
/// Commands, Chats, Errors). Reads from `TelegramServiceManager`, which
/// polls the local `clawjs/telegram` server every 5 seconds while the
/// page is on screen.
struct TelegramSettingsPage: View {

    @StateObject private var manager = TelegramServiceManager()
    @StateObject private var supervisor = ClawJSServiceManager.shared
    @State private var selectedBotId: String?
    @State private var addBotPresented = false
    @State private var sendMessageContext: SendMessageContext?

    private struct SendMessageContext: Identifiable {
        let bot: TelegramBot
        let chat: TelegramKnownChat
        var id: String { "\(bot.id)|\(chat.id)" }
    }

    private var serviceState: ClawJSServiceState {
        supervisor.snapshots[.telegram]?.state ?? .idle
    }

    /// True when either the GUI or the background daemon has confirmed
    /// the Telegram surface is reachable.
    private var telegramAvailable: Bool {
        serviceState.isReady
    }

    private var selectedBot: TelegramBot? {
        guard let selectedBotId else { return manager.bots.first }
        return manager.bots.first(where: { $0.id == selectedBotId })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            statusBanner
                .padding(.top, 14)

            HStack(alignment: .top, spacing: 16) {
                botListPane
                    .frame(width: 260)

                detailPane
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.top, 16)
        }
        .onAppear {
            updateRefreshLoop(for: serviceState)
        }
        .onChange(of: serviceState) { _, newState in
            updateRefreshLoop(for: newState)
        }
        .onDisappear {
            manager.stopRefreshing()
        }
        .sheet(isPresented: $addBotPresented) {
            AddBotSheet(manager: manager, isPresented: $addBotPresented) { newBotId in
                selectedBotId = newBotId
            }
        }
        .sheet(item: $sendMessageContext) { ctx in
            SendMessageSheet(
                manager: manager,
                bot: ctx.bot,
                chat: ctx.chat
            )
        }
    }

    // MARK: - Header & banner

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Telegram")
                .font(BodyFont.system(size: 22, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
            Text("Manage Telegram bots and their chats. Backed by the `clawjs/telegram` sidecar.")
                .font(BodyFont.system(size: 12.5))
                .foregroundColor(Palette.textSecondary)
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch serviceState {
        case .ready, .readyFromDaemon:
            EmptyView()
        case .starting:
            banner(text: "Telegram surface starting…", color: .yellow)
        case .blocked(let reason):
            banner(text: reason, color: .orange)
        case .crashed(let reason):
            banner(text: "Telegram surface crashed: \(reason)", color: .red)
        case .daemonUnavailable(let reason):
            banner(text: reason, color: .red)
        case .idle:
            banner(text: "Telegram surface is idle.", color: Color.white.opacity(0.4))
        }
    }

    private func banner(text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(Palette.textSecondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(white: 0.085))
        )
    }

    // MARK: - Bot list pane

    private var botListPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Bots")
                    .font(BodyFont.system(size: 12, wght: 600))
                    .foregroundColor(Palette.textSecondary)
                Spacer()
                if manager.isLoading && telegramAvailable {
                    ProgressView().controlSize(.mini)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)

            if manager.bots.isEmpty {
                Text(telegramAvailable ? "No bots yet." : "Bot list unavailable until Telegram responds.")
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(Palette.textSecondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 2) {
                    ForEach(manager.bots) { bot in
                        BotListRow(
                            bot: bot,
                            isSelected: bot.id == (selectedBotId ?? manager.bots.first?.id)
                        ) {
                            selectedBotId = bot.id
                        }
                    }
                }
            }

            if telegramAvailable, let error = manager.lastError {
                Text(error)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Divider().background(Color.white.opacity(0.06)).padding(.vertical, 8)

            Button {
                addBotPresented = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add bot")
                }
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(white: 0.13))
                )
            }
            .buttonStyle(.plain)
            .disabled(!telegramAvailable)
            .opacity(telegramAvailable ? 1 : 0.45)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: 0.065))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
        )
    }

    // MARK: - Detail pane

    @ViewBuilder
    private var detailPane: some View {
        if let bot = selectedBot {
            BotDetailView(
                bot: bot,
                manager: manager,
                onSendMessageRequested: { chat in
                    sendMessageContext = SendMessageContext(bot: bot, chat: chat)
                }
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Select a bot to see its details, or add one to get started.")
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textSecondary)
            }
            .padding(.top, 4)
        }
    }

    private func updateRefreshLoop(for state: ClawJSServiceState) {
        if state.isReady {
            manager.startRefreshing()
        } else {
            manager.resetForUnavailableService()
        }
    }
}

// MARK: - Bot list row

private struct BotListRow: View {
    let bot: TelegramBot
    let isSelected: Bool
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(transportColor)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bot.label)
                        .font(BodyFont.system(size: 12.5, wght: 500))
                        .foregroundColor(Palette.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(BodyFont.system(size: 10.5))
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(backgroundFill)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    private var subtitle: String {
        if let username = bot.displayUsername { return username }
        return bot.accountId
    }

    private var transportColor: Color {
        switch bot.transport {
        case .polling: return .green
        case .webhook: return .blue
        case .off:     return Color.white.opacity(0.35)
        }
    }

    private var backgroundFill: Color {
        if isSelected { return Color.white.opacity(0.07) }
        if hovered    { return Color.white.opacity(0.035) }
        return .clear
    }
}

// MARK: - Detail

private struct BotDetailView: View {
    let bot: TelegramBot
    @ObservedObject var manager: TelegramServiceManager
    let onSendMessageRequested: (TelegramKnownChat) -> Void

    @State private var webhookURL: String = ""
    @State private var webhookSecret: String = ""
    @State private var commandsDraft: [TelegramCommandSpec] = []
    @State private var commandsLoaded = false

    private var inflight: Bool { manager.inflight.contains(bot.id) }
    private var lastResult: ClawCliResult? { manager.lastActionResult[bot.id] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                profileCard
                transportCard
                commandsCard
                chatsCard
                errorsCard
                resultCard
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 24)
        }
        .thinScrollers()
        .onAppear { load() }
        .onChange(of: bot.id) { _ in load() }
        .onChange(of: bot.webhookUrl) { newValue in
            webhookURL = newValue ?? ""
        }
    }

    private func load() {
        webhookURL = bot.webhookUrl ?? ""
        webhookSecret = ""
        commandsLoaded = false
        commandsDraft = []
        Task { await manager.reloadCommands(bot) }
        Task { await manager.reloadChats(bot) }
    }

    // MARK: Profile

    private var profileCard: some View {
        SectionCard(title: "Profile") {
            VStack(alignment: .leading, spacing: 10) {
                row("Label") {
                    Text(bot.label)
                        .font(BodyFont.system(size: 12.5, wght: 500))
                        .foregroundColor(Palette.textPrimary)
                }
                Divider().background(Color.white.opacity(0.07))
                row("Account ID") {
                    Text(bot.accountId)
                        .font(BodyFont.system(size: 12.5))
                        .foregroundColor(Palette.textPrimary)
                        .monospaced()
                }
                if let username = bot.displayUsername {
                    Divider().background(Color.white.opacity(0.07))
                    row("Username") {
                        Text(username)
                            .font(BodyFont.system(size: 12.5))
                            .foregroundColor(Palette.textPrimary)
                    }
                }
                if let firstName = bot.firstName, !firstName.isEmpty {
                    Divider().background(Color.white.opacity(0.07))
                    row("First name") {
                        Text(firstName)
                            .font(BodyFont.system(size: 12.5))
                            .foregroundColor(Palette.textPrimary)
                    }
                }
                Divider().background(Color.white.opacity(0.07))
                row("Status") {
                    Text(bot.status)
                        .font(BodyFont.system(size: 12.5))
                        .foregroundColor(Palette.textPrimary)
                }
                if let masked = bot.maskedCredential, !masked.isEmpty {
                    Divider().background(Color.white.opacity(0.07))
                    row("Token") {
                        Text(masked)
                            .font(BodyFont.system(size: 12, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                            .monospaced()
                    }
                }
            }
        }
    }

    // MARK: Transport

    private var transportCard: some View {
        SectionCard(title: "Transport") {
            VStack(alignment: .leading, spacing: 12) {
                row("Mode") {
                    Text(bot.transport.label)
                        .font(BodyFont.system(size: 12.5, wght: 500))
                        .foregroundColor(Palette.textPrimary)
                }
                Divider().background(Color.white.opacity(0.07))

                HStack(spacing: 10) {
                    Button("Start polling") {
                        Task { await manager.startPolling(bot) }
                    }
                    .buttonStyle(.borderless)
                    .disabled(inflight)

                    Button("Stop polling") {
                        Task { await manager.stopPolling(bot) }
                    }
                    .buttonStyle(.borderless)
                    .disabled(inflight)

                    if inflight {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                }
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(Palette.textPrimary)

                Divider().background(Color.white.opacity(0.07))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Webhook URL")
                        .font(BodyFont.system(size: 11.5))
                        .foregroundColor(Palette.textSecondary)
                    TextField("https://example.com/telegram", text: $webhookURL)
                        .textFieldStyle(.roundedBorder)
                        .disabled(inflight)
                    Text("Secret token (optional)")
                        .font(BodyFont.system(size: 11.5))
                        .foregroundColor(Palette.textSecondary)
                        .padding(.top, 4)
                    SecureField("Optional", text: $webhookSecret)
                        .textFieldStyle(.roundedBorder)
                        .disabled(inflight)
                    HStack(spacing: 10) {
                        Button("Set webhook") {
                            Task {
                                await manager.setWebhook(
                                    bot,
                                    url: webhookURL,
                                    secretToken: webhookSecret.isEmpty ? nil : webhookSecret
                                )
                            }
                        }
                        .disabled(inflight || webhookURL.isEmpty)
                        Button("Clear webhook") {
                            Task { await manager.clearWebhook(bot) }
                        }
                        .disabled(inflight)
                        Spacer()
                    }
                    .buttonStyle(.borderless)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: Commands

    private var commandsCard: some View {
        SectionCard(title: "Commands") {
            VStack(alignment: .leading, spacing: 10) {
                if !commandsLoaded {
                    let stored = manager.commands[bot.id] ?? []
                    let _ = DispatchQueue.main.async {
                        commandsDraft = stored
                        commandsLoaded = !stored.isEmpty
                    }
                    EmptyView()
                }
                if commandsDraft.isEmpty {
                    Text("No commands set. Add one and Sync to publish to Telegram.")
                        .font(BodyFont.system(size: 11.5))
                        .foregroundColor(Palette.textSecondary)
                } else {
                    ForEach(Array(commandsDraft.enumerated()), id: \.offset) { idx, _ in
                        HStack(spacing: 8) {
                            TextField("start", text: $commandsDraft[idx].command)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                            TextField("Description", text: $commandsDraft[idx].description)
                                .textFieldStyle(.roundedBorder)
                            Button {
                                commandsDraft.remove(at: idx)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(Palette.textSecondary)
                        }
                    }
                }
                HStack(spacing: 10) {
                    Button("Add row") {
                        commandsDraft.append(TelegramCommandSpec(command: "", description: ""))
                    }
                    .buttonStyle(.borderless)

                    Button("Sync to Telegram") {
                        Task {
                            let cleaned = commandsDraft.filter { !$0.command.isEmpty }
                            await manager.saveCommands(bot, commands: cleaned)
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(inflight)

                    Button("Reload") {
                        Task {
                            await manager.reloadCommands(bot)
                            commandsDraft = manager.commands[bot.id] ?? []
                            commandsLoaded = true
                        }
                    }
                    .buttonStyle(.borderless)

                    Spacer()
                }
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(Palette.textPrimary)
            }
        }
    }

    // MARK: Chats

    private var chatsCard: some View {
        let chats = manager.chats[bot.id] ?? []
        return SectionCard(title: "Chats") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(chats.count) known")
                        .font(BodyFont.system(size: 11.5))
                        .foregroundColor(Palette.textSecondary)
                    Spacer()
                    Button("Reload") {
                        Task { await manager.reloadChats(bot) }
                    }
                    .buttonStyle(.borderless)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                }

                if chats.isEmpty {
                    Text("No chats observed yet. Once polling is on or a webhook fires, chats will appear here.")
                        .font(BodyFont.system(size: 11.5))
                        .foregroundColor(Palette.textSecondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(chats.enumerated()), id: \.element.id) { idx, chat in
                            if idx > 0 {
                                Divider().background(Color.white.opacity(0.06))
                            }
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chatTitle(chat))
                                        .font(BodyFont.system(size: 12, wght: 500))
                                        .foregroundColor(Palette.textPrimary)
                                    Text(chatSubtitle(chat))
                                        .font(BodyFont.system(size: 10.5))
                                        .foregroundColor(Palette.textSecondary)
                                }
                                Spacer()
                                Button("Send") {
                                    onSendMessageRequested(chat)
                                }
                                .buttonStyle(.borderless)
                                .font(BodyFont.system(size: 11.5, wght: 500))
                                .foregroundColor(Palette.textPrimary)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
        }
    }

    private func chatTitle(_ chat: TelegramKnownChat) -> String {
        if let title = chat.title, !title.isEmpty { return title }
        if let username = chat.username, !username.isEmpty { return "@\(username)" }
        return chat.chatId
    }

    private func chatSubtitle(_ chat: TelegramKnownChat) -> String {
        var parts: [String] = []
        parts.append("id \(chat.chatId)")
        if let type = chat.type, !type.isEmpty { parts.append(type) }
        return parts.joined(separator: " · ")
    }

    // MARK: Errors

    @ViewBuilder
    private var errorsCard: some View {
        let errors = bot.recentErrors ?? []
        if !errors.isEmpty {
            SectionCard(title: "Recent errors") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(errors.prefix(8).enumerated()), id: \.offset) { _, message in
                        Text(message)
                            .font(BodyFont.system(size: 11))
                            .foregroundColor(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: Last result

    @ViewBuilder
    private var resultCard: some View {
        if let result = lastResult, !(result.ok && result.stderr.isEmpty) {
            SectionCard(title: "Last action") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(result.ok ? Color.green : Color.red)
                            .frame(width: 7, height: 7)
                        Text(result.ok ? "ok" : "failed (exit \(result.exitCode.map(String.init) ?? "n/a"))")
                            .font(BodyFont.system(size: 11.5, wght: 500))
                            .foregroundColor(Palette.textPrimary)
                    }
                    if !result.stderr.isEmpty {
                        Text(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(BodyFont.system(size: 11))
                            .foregroundColor(result.ok ? Palette.textSecondary : .orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !result.stdout.isEmpty {
                        Text(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(BodyFont.system(size: 11))
                            .foregroundColor(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    // MARK: Helpers

    private func row<Trailing: View>(_ label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(label)
                .font(BodyFont.system(size: 12.5))
                .foregroundColor(Palette.textSecondary)
            Spacer()
            trailing()
        }
    }
}

// MARK: - Add bot sheet

private struct AddBotSheet: View {
    @ObservedObject var manager: TelegramServiceManager
    @Binding var isPresented: Bool
    let onCreated: (String?) -> Void

    @State private var secretName = ""
    @State private var accountId = ""
    @State private var label = ""
    @State private var inflight = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect a Telegram bot")
                .font(BodyFont.system(size: 16, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
            Text("Save the bot token in your Secrets vault first, then reference it here by name.")
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                fieldGroup(label: "Secret name (required)") {
                    TextField("telegram_bot_token", text: $secretName)
                        .textFieldStyle(.roundedBorder)
                }
                fieldGroup(label: "Account ID (optional)") {
                    TextField("default", text: $accountId)
                        .textFieldStyle(.roundedBorder)
                }
                fieldGroup(label: "Label (optional)") {
                    TextField("Support bot", text: $label)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if let failure {
                Text(failure)
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Connect") {
                    Task { await connect() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(inflight || secretName.isEmpty)
                if inflight {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func fieldGroup<Field: View>(
        label: String,
        @ViewBuilder field: () -> Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(Palette.textSecondary)
            field()
        }
    }

    private func connect() async {
        inflight = true
        defer { inflight = false }
        let result = await manager.registerBot(
            secretName: secretName,
            accountId: accountId.isEmpty ? nil : accountId,
            label: label.isEmpty ? nil : label
        )
        switch result {
        case .success(let envelope):
            if envelope.ok {
                isPresented = false
                onCreated(extractAccountId(envelope))
            } else {
                failure = envelope.stderr.isEmpty
                    ? "CLI exited with code \(envelope.exitCode.map(String.init) ?? "?")."
                    : envelope.stderr
            }
        case .failure(let error):
            failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func extractAccountId(_ envelope: ClawCliResult) -> String? {
        guard case let .object(dict)? = envelope.json else { return nil }
        if case let .string(s)? = dict["id"] { return s }
        if case let .string(s)? = dict["accountId"] { return s }
        return nil
    }
}

// MARK: - Send message sheet

private struct SendMessageSheet: View {
    @ObservedObject var manager: TelegramServiceManager
    let bot: TelegramBot
    let chat: TelegramKnownChat

    @State private var text = ""
    @State private var inflight = false
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Send a message")
                .font(BodyFont.system(size: 16, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
            Text("From `\(bot.label)` to `\(chatLabel)`")
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(Palette.textSecondary)

            TextEditor(text: $text)
                .font(BodyFont.system(size: 13))
                .frame(minHeight: 120)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(white: 0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
                )

            if let failure {
                Text(failure)
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Send") { Task { await send() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(inflight || text.isEmpty)
                if inflight {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var chatLabel: String {
        if let title = chat.title, !title.isEmpty { return title }
        if let username = chat.username, !username.isEmpty { return "@\(username)" }
        return chat.chatId
    }

    private func send() async {
        inflight = true
        defer { inflight = false }
        await manager.sendMessage(bot, chatId: chat.chatId, text: text)
        if let envelope = manager.lastActionResult[bot.id], envelope.ok {
            dismiss()
        } else if let envelope = manager.lastActionResult[bot.id] {
            failure = envelope.stderr.isEmpty ? "CLI exited non-zero." : envelope.stderr
        }
    }
}
