import SwiftUI

/// Popover surfaced from the chat-title click in the QuickAsk hover
/// header. Lists the user's recent (non-archived, non-temporary) chats
/// so they can hop between conversations without leaving the HUD.
/// Mirror of ChatGPT's recent-chats dropdown but compact: 320pt wide,
/// dark glass, search bar at top, list below capped at ~12 rows with
/// scrolling for the rest.
struct QuickAskRecentChatsPicker: View {
    @ObservedObject var appState: AppState
    @ObservedObject var controller: QuickAskController
    @Binding var isPresented: Bool

    @State private var query: String = ""
    @FocusState private var searchFocused: Bool

    private var allChats: [Chat] {
        appState.chats
            .filter { !$0.isArchived && !$0.isQuickAskTemporary }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var filteredChats: [Chat] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return allChats }
        return allChats.filter { $0.title.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
                TextField(
                    "",
                    text: $query,
                    prompt: Text("Search chats")
                        .foregroundColor(.white.opacity(0.45))
                )
                .textFieldStyle(.plain)
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(.white)
                .focused($searchFocused)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .padding(8)

            Divider()
                .background(Color.white.opacity(0.10))

            if filteredChats.isEmpty {
                Text("No chats yet")
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredChats.prefix(40)) { chat in
                            QuickAskRecentChatRow(
                                chat: chat,
                                isActive: chat.id == controller.activeChatId
                            ) {
                                controller.activateChat(chat.id)
                                isPresented = false
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 320)
        .background(
            VisualEffectBlur(material: .menu, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.7)
        )
        .onAppear { searchFocused = true }
    }
}

private struct QuickAskRecentChatRow: View {
    let chat: Chat
    let isActive: Bool
    let onSelect: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(width: 14)
                } else {
                    Color.clear.frame(width: 14)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(chat.title)
                        .font(BodyFont.system(size: 12, wght: 600))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(relativeTimestamp)
                        .font(BodyFont.system(size: 10, wght: 500))
                        .foregroundColor(.white.opacity(0.45))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                Color.white.opacity(hovered ? 0.06 : 0)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    private var relativeTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: chat.createdAt, relativeTo: Date())
    }
}
