import SwiftUI
import ClawixCore

// Project surface. A "project" is the set of chats that share a
// `cwd` (working directory) on the paired Mac. The Mac's Codex CLI
// already organizes work that way, so grouping here matches the
// mental model the user already has on the desktop.
//
// Layout mirrors the home screen's vibe:
//   - Floating glass back button + project name pill on the left,
//     ellipsis on the right.
//   - Header inside the scroll: folder badge + project name +
//     full path subtitle.
//   - Bare-text chat rows separated by hairlines, identical row
//     style to the home so the two screens read as one system.

struct ProjectDetailView: View {
    @Bindable var store: BridgeStore
    let project: DerivedProject
    let onOpen: (String) -> Void
    let onBack: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var chats: [WireChat] {
        project.chats.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            let l = lhs.lastMessageAt ?? lhs.createdAt
            let r = rhs.lastMessageAt ?? rhs.createdAt
            return l > r
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, AppLayout.screenHorizontalPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 18)

                chatRows

                Color.clear.frame(height: 80)
            }
        }
        .scrollIndicators(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            GlassIconButton(systemName: "chevron.left", action: handleBack)
            titlePill
            Spacer()
            GlassIconButton(systemName: "ellipsis", action: {})
        }
    }

    private func handleBack() {
        onBack()
        dismiss()
    }

    private var titlePill: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Palette.textPrimary)
            Text(project.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: AppLayout.topBarPillHeight)
        .glassCapsule()
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Palette.cardFill)
                        .frame(width: 48, height: 48)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Palette.textPrimary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Text(project.cwd)
                        .font(Typography.captionFont)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Text("\(chats.count) chat\(chats.count == 1 ? "" : "s")")
                .font(Typography.secondaryFont)
                .foregroundStyle(Palette.textSecondary)
                .padding(.top, 4)
        }
    }

    // MARK: Chat rows

    @ViewBuilder
    private var chatRows: some View {
        if chats.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 28))
                    .foregroundStyle(Palette.textTertiary)
                Text("No chats yet")
                    .font(Typography.bodyEmphasized)
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        } else {
            ForEach(Array(chats.enumerated()), id: \.element.id) { index, chat in
                Button {
                    onOpen(chat.id)
                } label: {
                    ChatRow(chat: chat)
                }
                .buttonStyle(.plain)
                if index < chats.count - 1 {
                    Rectangle()
                        .fill(Palette.borderSubtle)
                        .frame(height: 0.5)
                        .padding(.leading, AppLayout.screenHorizontalPadding)
                }
            }
        }
    }
}

#Preview("Project detail") {
    let store = BridgeStore.mock()
    let project = DerivedProject(
        cwd: "/workspace/auth-service",
        chats: store.chats.filter { $0.cwd == "/workspace/auth-service" }
    )
    return NavigationStack {
        ProjectDetailView(
            store: store,
            project: project,
            onOpen: { _ in },
            onBack: {}
        )
    }
    .preferredColorScheme(.dark)
}
