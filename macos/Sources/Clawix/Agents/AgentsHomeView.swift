import SwiftUI

/// Catalog grid of every agent the user has on disk plus the built-in
/// default Codex agent. Mirrors `SecretsHomeView` / `ProjectsRepository`
/// for visual consistency (header chrome, list / detail split). The
/// detail pane lives on its own route (`.agentDetail`) so the user can
/// deep-link / bookmark a single agent without staying in the home
/// surface.
struct AgentsHomeView: View {
    @EnvironmentObject private var store: AgentStore
    @EnvironmentObject private var appState: AppState
    @State private var showNewMenu: Bool = false
    @State private var editorAgent: Agent?
    @State private var importPicker: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            CardDivider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $editorAgent) { draft in
            AgentEditorSheet(initial: draft, isPresented: Binding(
                get: { editorAgent != nil },
                set: { if !$0 { editorAgent = nil } }
            )) { saved in
                store.upsertAgent(saved)
                editorAgent = nil
                appState.navigate(to: .agentDetail(id: saved.id))
            }
        }
        .fileImporter(isPresented: $importPicker,
                      allowedContentTypes: [.zip],
                      allowsMultipleSelection: false) { result in
            // Importer is wired in as a stub: the on-disk layout per
            // `~/.clawjs/agents/<id>/` is already a directory we can zip
            // and unzip with the OS. Wiring this end-to-end (zip parse,
            // id collision resolution, re-derive defaults) is part of
            // MVP step 7 — fileImporter handles the file selection so
            // the surface is ready when the unpack helper lands.
            _ = result
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Agents")
                    .font(BodyFont.system(size: 16, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text("\(store.agents.count) agent\(store.agents.count == 1 ? "" : "s") · filesystem-backed at ~/.clawjs/agents/")
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer()
            IconChipButton(symbol: "tray.and.arrow.down",
                           label: "Import",
                           action: { importPicker = true })
            IconChipButton(symbol: "plus",
                           label: "New agent",
                           isPrimary: true,
                           action: { editorAgent = Agent.newDraft() })
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.agents.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 14) {
                    ForEach(store.agents) { agent in
                        AgentCard(agent: agent)
                            .onTapGesture {
                                appState.navigate(to: .agentDetail(id: agent.id))
                            }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
            .thinScrollers()
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 14, alignment: .leading)]
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ClawixLogoIcon(size: 38)
                .foregroundColor(Palette.textSecondary)
            Text("No agents yet")
                .font(BodyFont.system(size: 14, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Text("Create one to give it a runtime, a personality, skills and projects.")
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(Palette.textSecondary)
                .multilineTextAlignment(.center)
            IconChipButton(symbol: "plus", label: "New agent", isPrimary: true) {
                editorAgent = Agent.newDraft()
            }
            .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Card

private struct AgentCard: View {
    let agent: Agent
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AgentAvatarBadge(avatar: agent.avatar, size: 38)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(agent.name)
                        .font(BodyFont.system(size: 13.5, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                        .lineLimit(1)
                    if agent.isBuiltin {
                        Text("Built-in")
                            .font(BodyFont.system(size: 9.5, wght: 600))
                            .foregroundColor(Palette.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )
                    }
                }
                if !agent.role.isEmpty {
                    Text(agent.role)
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(agent.runtime.label)
                        .font(BodyFont.system(size: 10.5, wght: 600))
                        .foregroundColor(Palette.textSecondary)
                    Text("·")
                        .foregroundColor(Palette.textSecondary)
                    Text(agent.model)
                        .font(BodyFont.system(size: 10.5, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(hovered ? 0.04 : 0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 0.6)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

// MARK: - Avatar badge

/// Standardised avatar: tinted ClawixLogoIcon on a faint dark squircle.
/// Custom-image avatars fall back to the tinted logo while the image
/// loader is still being wired (today the user picks a tint hex; image
/// uploads are post-MVP).
struct AgentAvatarBadge: View {
    let avatar: AgentAvatar
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(avatar.tintColor.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .stroke(avatar.tintColor.opacity(0.35), lineWidth: 0.6)
                )
            ClawixLogoIcon(size: size * 0.58)
                .foregroundColor(avatar.tintColor)
        }
        .frame(width: size, height: size)
    }
}
