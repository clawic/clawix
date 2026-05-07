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
    @State private var showRenameAlert = false
    @State private var renameDraft: String = ""

    // Deriving live from `store.chats` (instead of the captured
    // `project.chats` snapshot) is what makes new chats and metadata
    // updates land here without leaving and re-entering the folder.
    // The captured `project` only carries the cwd identity; everything
    // else flows from the observable store.
    private var chats: [WireChat] {
        store.chats
            .filter { !$0.isArchived && $0.cwd == project.cwd }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                let l = lhs.lastMessageAt ?? lhs.createdAt
                let r = rhs.lastMessageAt ?? rhs.createdAt
                return l > r
            }
    }

    private var allProjects: [DerivedProject] {
        DerivedProject.from(chats: store.chats.filter { !$0.isArchived })
    }

    private var displayName: String {
        store.projectDisplayName(cwd: project.cwd, fallback: project.name)
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
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(Palette.background.ignoresSafeArea())
        .topBarBlurFade(height: 130)
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showProjectPicker) {
            ProjectPickerSheet(
                projects: allProjects,
                currentCwd: project.cwd,
                store: store,
                onSelect: { selected in
                    showProjectPicker = false
                    guard selected.cwd != project.cwd else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        onSwitchProject(selected.cwd)
                    }
                },
                onDismiss: { showProjectPicker = false }
            )
            .presentationDetents([.fraction(0.55), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Palette.surface)
            .preferredColorScheme(.dark)
        }
        .alert("Rename folder", isPresented: $showRenameAlert) {
            TextField("Folder name", text: $renameDraft)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                store.renameProject(cwd: project.cwd, newName: renameDraft)
            }
        } message: {
            Text("Choose a new name for this folder. The change is kept on this iPhone.")
        }
    }

    // MARK: Top bar

    // Mirrors ChatDetailView's top bar so drilling from chat → project
    // (or vice versa) doesn't shift the chrome's geometry. The 1pt
    // vertical padding on the side circles lets the HStack settle at
    // the chip's 48pt height while the visible glass circles stay 46.
    private var topBar: some View {
        HStack(spacing: 8) {
            GlassIconButton(
                systemName: "chevron.left",
                size: 46,
                iconSize: 20,
                action: handleBack
            )
            .padding(.vertical, 1)
            titlePill
            Spacer()
            ellipsisButton
                .padding(.vertical, 1)
        }
    }

    private var ellipsisButton: some View {
        Menu {
            Button {
                renameDraft = displayName
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    showRenameAlert = true
                }
            } label: {
                if let img = MenuIconImage.pencil {
                    Label { Text("Edit") } icon: { Image(uiImage: img) }
                } else {
                    Label("Edit", systemImage: "pencil")
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.clear)
                    .glassEffect(.regular, in: Circle())
                Image(systemName: "ellipsis")
                    .font(BodyFont.system(size: 20, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
            }
            .frame(width: 46, height: 46)
            .contentShape(Circle())
        }
        .menuOrder(.fixed)
        .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
    }

    private func handleBack() {
        onBack()
        dismiss()
    }

    private var titlePill: some View {
        Button {
            Haptics.tap()
            showProjectPicker = true
        } label: {
            HStack(spacing: 8) {
                FolderClosedIcon(size: 20, weight: 1.4)
                    .foregroundStyle(Palette.textPrimary)
                Text(displayName)
                    .font(BodyFont.manrope(size: 17, wght: 500))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(BodyFont.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
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
            ForEach(chats) { chat in
                Button {
                    Haptics.tap()
                    onOpen(chat.id)
                } label: {
                    ChatRow(chat: chat, isUnread: store.isUnread(chatId: chat.id))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Project picker sheet

// Bottom sheet shown when the user taps the project pill in the top
// bar. Lists every project the paired Mac surfaces, with the active
// one marked. Tapping a different one tells the host to swap the
// current screen for that project's detail without growing the nav
// stack (replace, not push). Internal so ChatDetailView reuses it.
struct ProjectPickerSheet: View {
    let projects: [DerivedProject]
    let currentCwd: String
    let store: BridgeStore
    let onSelect: (DerivedProject) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, AppLayout.screenHorizontalPadding)
                    .padding(.top, 28)
                    .padding(.bottom, 10)

                ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                    Button {
                        Haptics.selection()
                        onSelect(project)
                    } label: {
                        ProjectPickerRow(
                            project: project,
                            displayName: store.projectDisplayName(cwd: project.cwd, fallback: project.name),
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
        .background(Palette.surface.ignoresSafeArea())
    }

    private var header: some View {
        Text("Switch project")
            .font(BodyFont.system(size: 22, weight: .bold))
            .foregroundStyle(Palette.textPrimary)
    }
}

private struct ProjectPickerRow: View {
    let project: DerivedProject
    let displayName: String
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            FolderClosedIcon(size: 20)
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 24, alignment: .center)

            Text(displayName)
                .font(Typography.bodyFont)
                .tracking(-0.2)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)

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
