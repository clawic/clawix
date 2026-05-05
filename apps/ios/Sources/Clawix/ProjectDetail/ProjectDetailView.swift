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
//   - Bare-text chat rows separated by hairlines, identical row
//     style to the home so the two screens read as one system.
//   - Tapping the project pill opens a bottom sheet that lists every
//     other project so the user can switch context without going
//     back to the home.

struct ProjectDetailView: View {
    @Bindable var store: BridgeStore
    let project: DerivedProject
    let onOpen: (String) -> Void
    let onSwitchProject: (String) -> Void
    let onBack: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showProjectPicker = false

    private var chats: [WireChat] {
        project.chats.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            let l = lhs.lastMessageAt ?? lhs.createdAt
            let r = rhs.lastMessageAt ?? rhs.createdAt
            return l > r
        }
    }

    private var allProjects: [DerivedProject] {
        DerivedProject.from(chats: store.chats.filter { !$0.isArchived })
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 8)

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
        .sheet(isPresented: $showProjectPicker) {
            ProjectPickerSheet(
                projects: allProjects,
                currentCwd: project.cwd,
                onSelect: { selected in
                    showProjectPicker = false
                    guard selected.cwd != project.cwd else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        onSwitchProject(selected.cwd)
                    }
                },
                onDismiss: { showProjectPicker = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Palette.background)
            .preferredColorScheme(.dark)
        }
    }

    // MARK: Top bar

    // Slightly more compact than the home top bar so the chrome reads
    // as "drilled into a project" rather than peer-level. The chevron
    // on the back button is bumped up a touch so it stays legible at
    // the smaller circle size.
    private static let pillHeight: CGFloat = 42

    private var topBar: some View {
        HStack(spacing: 8) {
            GlassIconButton(
                systemName: "chevron.left",
                size: Self.pillHeight,
                iconSize: 19,
                iconWeight: .semibold,
                action: handleBack
            )
            titlePill
            Spacer()
            GlassIconButton(
                systemName: "ellipsis",
                size: Self.pillHeight,
                action: {}
            )
        }
    }

    private func handleBack() {
        onBack()
        dismiss()
    }

    private var titlePill: some View {
        Button {
            showProjectPicker = true
        } label: {
            HStack(spacing: 8) {
                FolderClosedIcon(size: 17, weight: 2.1)
                    .foregroundStyle(Palette.textPrimary)
                Text(project.name)
                    .font(BodyFont.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(BodyFont.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, 14)
            .frame(height: Self.pillHeight)
            .glassCapsule()
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Chat rows

    @ViewBuilder
    private var chatRows: some View {
        if chats.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "bubble.left")
                    .font(BodyFont.system(size: 28))
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

// MARK: - Project picker sheet

// Bottom sheet shown when the user taps the project pill in the top
// bar. Lists every project the paired Mac surfaces, with the active
// one marked. Tapping a different one tells the host to swap the
// current screen for that project's detail without growing the nav
// stack (replace, not push).
private struct ProjectPickerSheet: View {
    let projects: [DerivedProject]
    let currentCwd: String
    let onSelect: (DerivedProject) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, AppLayout.screenHorizontalPadding)
                    .padding(.top, 18)
                    .padding(.bottom, 10)

                ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                    Button {
                        onSelect(project)
                    } label: {
                        ProjectPickerRow(
                            project: project,
                            isCurrent: project.cwd == currentCwd
                        )
                    }
                    .buttonStyle(.plain)

                    if index < projects.count - 1 {
                        Rectangle()
                            .fill(Palette.borderSubtle)
                            .frame(height: 0.5)
                            .padding(.leading, AppLayout.screenHorizontalPadding + 36)
                    }
                }

                Color.clear.frame(height: 32)
            }
        }
        .scrollIndicators(.hidden)
        .background(Palette.background)
    }

    private var header: some View {
        Text("Switch project")
            .font(AppFont.system(size: 22, weight: .bold))
            .foregroundStyle(Palette.textPrimary)
    }
}

private struct ProjectPickerRow: View {
    let project: DerivedProject
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            FolderClosedIcon(size: 20)
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(Typography.bodyFont)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(project.cwd)
                    .font(Typography.captionFont)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if isCurrent {
                Image(systemName: "checkmark")
                    .font(BodyFont.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
            } else if project.hasActiveTurn {
                Circle()
                    .fill(Color(red: 0.30, green: 0.78, blue: 0.45))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, AppLayout.screenHorizontalPadding)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
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
            onSwitchProject: { _ in },
            onBack: {}
        )
    }
    .preferredColorScheme(.dark)
}
