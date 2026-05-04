import SwiftUI
import ClawixCore

struct ChatListView: View {
    @Bindable var store: BridgeStore
    let onOpen: (String) -> Void

    private var visible: [WireChat] {
        store.chats
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                let l = lhs.lastMessageAt ?? lhs.createdAt
                let r = rhs.lastMessageAt ?? rhs.createdAt
                return l > r
            }
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    headerRow
                        .padding(.bottom, 4)
                    ForEach(visible, id: \.id) { chat in
                        ChatRow(chat: chat)
                            .contentShape(Rectangle())
                            .onTapGesture { onOpen(chat.id) }
                    }
                    Spacer().frame(height: 80)
                }
                .padding(.horizontal, Layout.screenHorizontalPadding)
                .padding(.top, 16)
            }
            .scrollIndicators(.hidden)
            .fadeEdge()
        }
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Chats")
                    .font(Typography.titleFont)
                    .foregroundStyle(Palette.textPrimary)
                Text(connectionLabel)
                    .font(Typography.captionFont)
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer()
            connectionBadge
        }
    }

    private var connectionLabel: String {
        switch store.connection {
        case .unpaired:                  return "Not paired"
        case .connecting:                return "Connecting..."
        case .connected(let macName):    return macName.map { "Connected to \($0)" } ?? "Connected"
        case .error(let msg):            return msg
        }
    }

    private var connectionBadge: some View {
        let color: Color
        switch store.connection {
        case .connected: color = Color(red: 0.30, green: 0.78, blue: 0.45)
        case .connecting: color = Color(red: 0.95, green: 0.78, blue: 0.30)
        case .error:      color = Color(red: 0.85, green: 0.30, blue: 0.30)
        case .unpaired:   color = Palette.textTertiary
        }
        return Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle().strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
    }
}

private struct ChatRow: View {
    let chat: WireChat

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if chat.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    Text(chat.title)
                        .font(Typography.bodyEmphasized)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(timeLabel)
                        .font(Typography.captionFont)
                        .foregroundStyle(Palette.textTertiary)
                }
                if let preview = chat.lastMessagePreview, !preview.isEmpty {
                    Text(preview)
                        .font(Typography.secondaryFont)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if chat.hasActiveTurn || chat.branch != nil {
                    HStack(spacing: 8) {
                        if chat.hasActiveTurn {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(red: 0.30, green: 0.78, blue: 0.45))
                                    .frame(width: 6, height: 6)
                                Text("Working")
                                    .font(Typography.captionFont)
                                    .foregroundStyle(Palette.textTertiary)
                            }
                        }
                        if let branch = chat.branch {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundStyle(Palette.textTertiary)
                                Text(branch)
                                    .font(Typography.captionFont)
                                    .foregroundStyle(Palette.textTertiary)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Layout.listRowVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous)
                .fill(Palette.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous)
                .strokeBorder(Palette.popupStroke, lineWidth: Palette.popupStrokeWidth)
        )
    }

    private var timeLabel: String {
        let date = chat.lastMessageAt ?? chat.createdAt
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86_400 { return "\(Int(interval / 3600))h" }
        let days = Int(interval / 86_400)
        if days < 7 { return "\(days)d" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

#Preview("Chat list") {
    ChatListView(store: BridgeStore.mock(), onOpen: { _ in })
        .preferredColorScheme(.dark)
}
