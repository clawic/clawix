import SwiftUI

/// Compact horizontal pill row showing the skills currently active for
/// a chat (resolved across the global → project → chat hierarchy).
/// Lives below the chat composer when at least one skill is active so
/// the user always knows what's loading into the system prompt without
/// having to open the Skills page.
///
/// Tap on a chip → navigate to the skill detail page for that slug.
/// Long-press / right-click → quick "deactivate for this chat"
/// (decided per-chat, never affects global/project state).
struct SkillsChipBar: View {
    let chatId: UUID?
    @EnvironmentObject var appState: AppState

    private var states: [ActiveSkillState] {
        guard let store = appState.skillsStore else { return [] }
        let projectId: String? = {
            if let chatId,
               let chat = appState.chats.first(where: { $0.id == chatId }),
               let pid = chat.projectId {
                return pid.uuidString
            }
            return appState.selectedProject?.id.uuidString
        }()
        return store.resolveActive(projectId: projectId, chatId: chatId)
    }

    var body: some View {
        if states.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(states) { state in
                        chip(for: state)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chip(for state: ActiveSkillState) -> some View {
        let skill = appState.skillsStore?.skill(slug: state.slug)
        let scopeIcon: String = {
            if state.scopeTag == "global" { return "globe" }
            if state.scopeTag.hasPrefix("project:") { return "square.stack.3d.up" }
            if state.scopeTag.hasPrefix("chat:") { return "bubble.left" }
            return "circle"
        }()
        return Button {
            appState.currentRoute = .skillDetail(slug: state.slug)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: state.kind.icon)
                    .font(.system(size: 9.5, weight: .semibold))
                Text(skill?.name ?? state.slug)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Image(systemName: scopeIcon)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color.gray.opacity(0.14))
            )
            .overlay(
                Capsule().stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open detail") {
                appState.currentRoute = .skillDetail(slug: state.slug)
            }
            if let chatId {
                Button("Deactivate for this chat") {
                    appState.skillsStore?.setActive(
                        slug: state.slug,
                        scopeTag: "chat:\(chatId.uuidString)",
                        active: false
                    )
                }
            }
            Button("Deactivate everywhere") {
                if let store = appState.skillsStore {
                    for scopeTag in store.activeByScope.keys {
                        store.setActive(slug: state.slug, scopeTag: scopeTag, active: false)
                    }
                }
            }
        }
    }
}
