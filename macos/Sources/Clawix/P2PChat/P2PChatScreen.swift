import SwiftUI

struct P2PChatScreen: View {
    @ObservedObject var manager: ProfileManager
    @State private var selectedThreadId: String?
    @State private var messages: [ClawJSProfileClient.ChatMessage] = []
    @State private var draft: String = ""
    @State private var isSending = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 280)
            Divider().background(Color.white.opacity(0.06))
            detail
        }
        .background(Color.black)
        .task { await manager.refreshChats() }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Chats").font(.system(size: 14, weight: .semibold)).kerning(-0.2)
                Spacer()
                LucideIcon(.plus, size: 13).foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(manager.chatThreads) { thread in
                        ThreadRow(thread: thread, isSelected: thread.id == selectedThreadId)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedThreadId = thread.id
                                Task { await loadMessages(for: thread) }
                            }
                    }
                }
            }
            .thinScrollers()
        }
        .frame(maxHeight: .infinity)
        .background(Color(white: 0.06))
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let thread = currentThread {
            VStack(spacing: 0) {
                ThreadHeader(thread: thread)
                Divider().background(Color.white.opacity(0.06))
                MessagesList(messages: messages, currentAlias: thread.peer.handle.alias)
                Divider().background(Color.white.opacity(0.06))
                composer(thread: thread)
            }
        } else {
            VStack(spacing: 8) {
                LucideIcon(.messageCircle, size: 28)
                Text("Pick a peer to start the conversation")
                    .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var currentThread: ClawJSProfileClient.ChatThread? {
        guard let id = selectedThreadId else { return nil }
        return manager.chatThreads.first { $0.id == id }
    }

    private func composer(thread: ClawJSProfileClient.ChatThread) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5),
                )
            Button(action: { Task { await send(thread: thread) } }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.white.opacity(draft.isEmpty ? 0.04 : 0.92))
                    LucideIcon(.arrowUp, size: 14)
                        .foregroundStyle(draft.isEmpty ? Palette.textSecondary : .black)
                }
                .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .disabled(draft.isEmpty || isSending)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(Color.black)
    }

    // MARK: - Side-effects

    private func loadMessages(for thread: ClawJSProfileClient.ChatThread) async {
        do {
            self.messages = try await manager.loadMessages(peer: thread.peer.handle.fingerprint)
        } catch {
            self.messages = []
        }
    }

    private func send(thread: ClawJSProfileClient.ChatThread) async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            let sent = try await manager.sendMessage(peer: thread.peer.handle.fingerprint, body: body)
            self.messages.append(sent)
            self.draft = ""
        } catch {
            // Silent for now; an error toast would land here.
        }
    }
}

private struct ThreadRow: View {
    let thread: ClawJSProfileClient.ChatThread
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                Text(initials).font(.system(size: 12, weight: .semibold))
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(thread.peer.handle.alias)").font(.system(size: 13, weight: .medium)).kerning(-0.2)
                Text("." + thread.peer.handle.fingerprint).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            if thread.unreadCount > 0 {
                Text(String(thread.unreadCount))
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.white)
                    )
                    .foregroundStyle(.black)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.07) : .clear)
                .padding(.horizontal, 4)
        )
    }

    private var initials: String {
        let parts = thread.peer.handle.alias.split(separator: "_").flatMap { $0.split(separator: "-") }
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(thread.peer.handle.alias.prefix(2)).uppercased()
    }
}

private struct ThreadHeader: View {
    let thread: ClawJSProfileClient.ChatThread

    var body: some View {
        HStack(spacing: 10) {
            Text("@\(thread.peer.handle.alias)").font(.system(size: 14, weight: .semibold)).kerning(-0.2)
            Text("." + thread.peer.handle.fingerprint).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
            Spacer()
            LucideIcon(.info, size: 14).foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(Color.black)
    }
}

private struct MessagesList: View {
    let messages: [ClawJSProfileClient.ChatMessage]
    let currentAlias: String

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(messages) { m in
                    MessageBubble(message: m)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
        }
        .thinScrollers()
        .frame(maxHeight: .infinity)
    }
}

private struct MessageBubble: View {
    let message: ClawJSProfileClient.ChatMessage

    var body: some View {
        HStack {
            if message.fromMe { Spacer(minLength: 64) }
            VStack(alignment: .leading, spacing: 4) {
                if message.draftFromAgent {
                    Text("Agent draft").font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                }
                Text(message.body)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(message.fromMe ? Color.white : Color.white.opacity(0.06))
                    )
                    .foregroundStyle(message.fromMe ? .black : Palette.textPrimary)
            }
            if !message.fromMe { Spacer(minLength: 64) }
        }
    }
}
