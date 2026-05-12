import SwiftUI

struct P2PChatView: View {
    @ObservedObject var store: ProfileStore
    @State private var selected: ProfileClient.ChatThread?

    var body: some View {
        NavigationStack {
            List(store.threads) { thread in
                Button(action: { selected = thread }) {
                    ThreadRow(thread: thread)
                }
                .buttonStyle(.plain)
                .listRowBackground(Palette.background)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("Chats")
            .task { await store.refreshChats() }
            .refreshable { await store.refreshChats() }
            .navigationDestination(item: $selected) { thread in
                P2PChatDetailView(store: store, thread: thread)
            }
        }
    }
}

private struct ThreadRow: View {
    let thread: ProfileClient.ChatThread

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                Text(initials).font(.system(size: 13, weight: .semibold))
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(thread.peer.handle.alias)").font(.system(size: 14, weight: .medium)).kerning(-0.2)
                Text(".\(thread.peer.handle.fingerprint)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            if thread.unreadCount > 0 {
                Text(String(thread.unreadCount))
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Palette.unreadDot))
                    .foregroundStyle(.white)
            }
        }
        .padding(.vertical, 4)
    }

    private var initials: String {
        let parts = thread.peer.handle.alias.split(separator: "_").flatMap { $0.split(separator: "-") }
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(thread.peer.handle.alias.prefix(2)).uppercased()
    }
}

struct P2PChatDetailView: View {
    @ObservedObject var store: ProfileStore
    let thread: ProfileClient.ChatThread
    @State private var messages: [ProfileClient.ChatMessage] = []
    @State private var draft: String = ""

    var body: some View {
        VStack(spacing: 0) {
            messageList
            composer
        }
        .navigationTitle(thread.peer.handle.alias)
        .navigationBarTitleDisplayMode(.inline)
        .background(Palette.background)
        .task { await load() }
    }

    private var messageList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(messages) { m in Bubble(message: m) }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .font(.system(size: 14))
                .padding(.horizontal, 14).padding(.vertical, 12)
                .glassCapsule()
            Button(action: { Task { await send() } }) {
                ZStack {
                    Circle().fill(draft.isEmpty ? Color.white.opacity(0.12) : Color.white)
                    LucideIcon(.arrowUp, size: 16)
                        .foregroundStyle(draft.isEmpty ? Palette.textSecondary : .black)
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(draft.isEmpty)
        }
        .padding(.horizontal, 12).padding(.bottom, 12)
    }

    private func load() async {
        messages = await store.loadMessages(peer: thread.peer.handle.fingerprint)
    }

    private func send() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        if let m = await store.sendMessage(peer: thread.peer.handle.fingerprint, body: body) {
            messages.append(m)
            draft = ""
        }
    }
}

private struct Bubble: View {
    let message: ProfileClient.ChatMessage

    var body: some View {
        HStack {
            if message.fromMe { Spacer(minLength: 50) }
            Text(message.body)
                .font(.system(size: 14))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(message.fromMe ? Palette.userBubbleFill : Color.white.opacity(0.06))
                )
                .foregroundStyle(message.fromMe ? Palette.userBubbleText : Palette.textPrimary)
            if !message.fromMe { Spacer(minLength: 50) }
        }
    }
}
