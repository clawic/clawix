import SwiftUI

/// Detail surface for a single agent. The tab set mirrors the plan:
/// Chats / Skills / Secrets / Projects / Integrations / Settings. Chat
/// invocations are still routed through the central composer (the
/// "New chat with X" CTA navigates to `.home` with the agent
/// preselected, which the composer dropdown picks up).
struct AgentDetailView: View {
    let agentId: String

    @EnvironmentObject private var store: AgentStore
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab: Tab = .settings
    @State private var showEditor: Bool = false
    @State private var deleteConfirm: Bool = false
    @State private var pendingApproval: AgentApprovalRequest?

    enum Tab: String, CaseIterable, Identifiable, Hashable {
        case chats, skills, secrets, projects, integrations, settings
        var id: String { rawValue }
        var label: String {
            switch self {
            case .chats:        return "Chats"
            case .skills:       return "Skills"
            case .secrets:      return "Secrets"
            case .projects:     return "Projects"
            case .integrations: return "Integrations"
            case .settings:     return "Settings"
            }
        }
    }

    private var agent: Agent? { store.agent(id: agentId) }

    var body: some View {
        if let agent {
            VStack(spacing: 0) {
                header(for: agent)
                CardDivider()
                tabBar(for: agent)
                CardDivider()
                tabBody(for: agent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .sheet(isPresented: $showEditor) {
                AgentEditorSheet(initial: agent, isPresented: $showEditor) { saved in
                    store.upsertAgent(saved)
                    showEditor = false
                }
            }
            .sheet(item: $pendingApproval) { req in
                AgentApprovalRequestSheet(request: req) { decision in
                    // Audit + dismiss. The actual enforcement plugs into
                    // the runtime via `BridgeProtocol.agentApprovalResponse`;
                    // surfacing here keeps the UX testable end-to-end.
                    store.appendAudit(AgentAuditEntry(
                        id: UUID().uuidString,
                        timestamp: Date(),
                        actorAgentId: agent.id,
                        subjectAgentId: nil,
                        action: req.action,
                        result: decision.rawValue,
                        note: req.detail
                    ), on: agent.id)
                    pendingApproval = nil
                }
            }
            .alert("Delete \(agent.name)?",
                   isPresented: $deleteConfirm,
                   actions: {
                Button("Delete", role: .destructive) {
                    store.deleteAgent(id: agent.id)
                    appState.navigate(to: .agentsHome)
                }
                Button("Cancel", role: .cancel) {}
            }, message: {
                Text("Removes ~/.clawjs/agents/\(agent.id)/ from disk. Chats started with this agent stay; they fall back to the default Codex agent.")
            })
        } else {
            VStack(spacing: 12) {
                Text("Agent not found")
                    .font(BodyFont.system(size: 14, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                IconChipButton(symbol: "arrow.left", label: "Back to Agents") {
                    appState.navigate(to: .agentsHome)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Header

    private func header(for agent: Agent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AgentAvatarBadge(avatar: agent.avatar, size: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text(agent.name)
                    .font(BodyFont.system(size: 18, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                HStack(spacing: 6) {
                    Text(agent.runtime.label)
                        .font(BodyFont.system(size: 11.5, wght: 600))
                        .foregroundColor(Palette.textSecondary)
                    Text("·").foregroundColor(Palette.textSecondary)
                    Text(agent.model)
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                    if !agent.role.isEmpty {
                        Text("·").foregroundColor(Palette.textSecondary)
                        Text(agent.role)
                            .font(BodyFont.system(size: 11.5, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            IconChipButton(symbol: "bubble.left.and.bubble.right",
                           label: "New chat with \(agent.name)",
                           isPrimary: true) {
                // Pre-select the agent for the next composer send.
                appState.selectedAgentId = agent.id
                appState.navigate(to: .home)
                appState.composer.focusToken &+= 1
            }
            IconChipButton(symbol: "doc.on.doc", label: "Duplicate") {
                _ = store.duplicateAgent(id: agent.id)
            }
            if !agent.isBuiltin {
                IconChipButton(symbol: "pencil", label: "Edit") { showEditor = true }
                IconChipButton(symbol: "trash") { deleteConfirm = true }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    // MARK: - Tab bar

    private func tabBar(for agent: Agent) -> some View {
        HStack(spacing: 14) {
            ForEach(Tab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 6) {
                        Text(tab.label)
                            .font(BodyFont.system(size: 12.5,
                                                  wght: selectedTab == tab ? 600 : 500))
                            .foregroundColor(selectedTab == tab ? Palette.textPrimary : Palette.textSecondary)
                        Rectangle()
                            .fill(selectedTab == tab ? Palette.textPrimary : Color.clear)
                            .frame(height: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
    }

    // MARK: - Tab body

    @ViewBuilder
    private func tabBody(for agent: Agent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch selectedTab {
                case .chats:
                    chatsTab(for: agent)
                case .skills:
                    skillsTab(for: agent)
                case .secrets:
                    secretsTab(for: agent)
                case .projects:
                    projectsTab(for: agent)
                case .integrations:
                    integrationsTab(for: agent)
                case .settings:
                    settingsTab(for: agent)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .thinScrollers()
    }

    // MARK: - Tabs

    @ViewBuilder
    private func chatsTab(for agent: Agent) -> some View {
        let chats = appState.chats.filter { $0.agentId == agent.id }
        if chats.isEmpty {
            emptyTab(icon: "bubble.left",
                     title: "No chats yet",
                     blurb: "Start one from the composer above; the chat will be tagged with this agent and live here.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(chats) { chat in
                    Button {
                        appState.navigate(to: .chat(chat.id))
                    } label: {
                        HStack(spacing: 10) {
                            Text(chat.title)
                                .font(BodyFont.system(size: 13, wght: 500))
                                .foregroundColor(Palette.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            if let last = chat.lastMessageAt {
                                Text(last, style: .relative)
                                    .font(BodyFont.system(size: 11, wght: 500))
                                    .foregroundColor(Palette.textSecondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.03))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func skillsTab(for agent: Agent) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Skill collections subscribed")
                .font(BodyFont.system(size: 11.5, wght: 600))
                .foregroundColor(Palette.textSecondary)
            if agent.skillCollectionIds.isEmpty {
                Text("None. Subscribe to a collection from the Settings tab.")
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            } else {
                ForEach(agent.skillCollectionIds, id: \.self) { id in
                    if let c = store.collection(id: id) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "square.stack")
                                .foregroundColor(Palette.textSecondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(c.name)
                                    .font(BodyFont.system(size: 13, wght: 600))
                                    .foregroundColor(Palette.textPrimary)
                                Text(c.includedTags.joined(separator: " · "))
                                    .font(BodyFont.system(size: 11, wght: 500))
                                    .foregroundColor(Palette.textSecondary)
                            }
                        }
                    }
                }
            }
            CardDivider()
            Text("Skill allowlist")
                .font(BodyFont.system(size: 11.5, wght: 600))
                .foregroundColor(Palette.textSecondary)
            if agent.skillAllowlist.isEmpty {
                Text("Empty. Add explicit skill IDs from the Settings tab.")
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            } else {
                FlowChips(items: agent.skillAllowlist)
            }
        }
    }

    @ViewBuilder
    private func secretsTab(for agent: Agent) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Secret tags subscribed")
                .font(BodyFont.system(size: 11.5, wght: 600))
                .foregroundColor(Palette.textSecondary)
            if agent.secretTags.isEmpty {
                Text("None. Tag-based subscriptions auto-grant matching secrets.")
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            } else {
                FlowChips(items: agent.secretTags)
            }
            CardDivider()
            Text("Secret allowlist")
                .font(BodyFont.system(size: 11.5, wght: 600))
                .foregroundColor(Palette.textSecondary)
            if agent.secretAllowlist.isEmpty {
                Text("Empty. Add explicit secret IDs from the Settings tab.")
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            } else {
                FlowChips(items: agent.secretAllowlist)
            }
        }
    }

    @ViewBuilder
    private func projectsTab(for agent: Agent) -> some View {
        if agent.projectIds.isEmpty {
            emptyTab(icon: "square.stack.3d.up",
                     title: "No projects assigned",
                     blurb: "Assign projects from the Settings tab. Projects are N↔N; an agent can own none, one or many.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(agent.projectIds, id: \.self) { pid in
                    HStack(spacing: 8) {
                        Image(systemName: "square.stack.3d.up")
                            .foregroundColor(Palette.textSecondary)
                        Text(pid)
                            .font(BodyFont.system(size: 12.5, wght: 500))
                            .foregroundColor(Palette.textPrimary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.03))
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func integrationsTab(for agent: Agent) -> some View {
        if agent.integrationBindings.isEmpty {
            emptyTab(icon: "link.circle",
                     title: "No integrations bound",
                     blurb: "Bind a Connection (Telegram, Slack, …) from the Settings tab so this agent can receive messages from that channel.")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(agent.integrationBindings) { binding in
                    HStack(spacing: 10) {
                        Image(systemName: store.connection(id: binding.connectionId)?.service.icon ?? "link")
                            .foregroundColor(Palette.textSecondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.connection(id: binding.connectionId)?.label ?? binding.connectionId)
                                .font(BodyFont.system(size: 13, wght: 600))
                                .foregroundColor(Palette.textPrimary)
                            Text("Channel: \(binding.channelRef) · \(binding.direction.rawValue)")
                                .font(BodyFont.system(size: 11.5, wght: 500))
                                .foregroundColor(Palette.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.03))
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func settingsTab(for agent: Agent) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsBlock(title: "Identity") {
                row(label: "ID", value: agent.id)
                row(label: "Role", value: agent.role.isEmpty ? "—" : agent.role)
                row(label: "Avatar tint", value: agent.avatar.tintHex)
            }
            settingsBlock(title: "Runtime") {
                row(label: "Runtime", value: agent.runtime.label)
                row(label: "Model", value: agent.model)
            }
            settingsBlock(title: "Autonomy") {
                row(label: "Level", value: agent.autonomyLevel.label)
                Text(agent.autonomyLevel.blurb)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                if !agent.autonomyOverrides.isEmpty {
                    ForEach(agent.autonomyOverrides, id: \.action) { o in
                        row(label: o.action, value: o.level.label)
                    }
                }
            }
            settingsBlock(title: "Delegation") {
                row(label: "Reports to", value: agent.delegation.reportsTo ?? "—")
                row(label: "Allowed subagents",
                    value: agent.delegation.allowedSubagents.isEmpty
                        ? "—"
                        : agent.delegation.allowedSubagents.joined(separator: ", "))
                row(label: "Inherits caller scope",
                    value: agent.delegation.scopeInherits ? "Yes" : "No")
            }
            if !agent.instructionsFreeText.isEmpty {
                settingsBlock(title: "Free-text instructions") {
                    Text(agent.instructionsFreeText)
                        .font(BodyFont.system(size: 12, wght: 500))
                        .foregroundColor(Palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if !agent.isBuiltin {
                IconChipButton(symbol: "pencil", label: "Edit agent", isPrimary: true) {
                    showEditor = true
                }
            }
        }
    }

    @ViewBuilder
    private func settingsBlock<Content: View>(title: String,
                                              @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(BodyFont.system(size: 10.5, wght: 600))
                .foregroundColor(Palette.textSecondary)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.025))
            )
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(Palette.textSecondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func emptyTab(icon: String, title: String, blurb: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(BodyFont.system(size: 24, wght: 500))
                .foregroundColor(Palette.textSecondary)
            Text(title)
                .font(BodyFont.system(size: 13.5, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Text(blurb)
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 36)
    }
}

// MARK: - FlowChips

struct FlowChips: View {
    let items: [String]
    var body: some View {
        // SwiftUI lacks a native flow layout on older targets; use a
        // simple wrapped HStack via Layout. Keep it small + dependency
        // free so the surface renders on day one.
        AgentChipFlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(BodyFont.system(size: 11, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }
        }
    }
}

/// Minimal flow layout (rows wrap when total width exceeds container).
/// Lives next to its only caller for now; if a second surface needs
/// chip wrapping we promote it to a shared file.
struct AgentChipFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if rowWidth + size.width > width {
                totalHeight += rowHeight + spacing
                rowWidth = size.width + spacing
                rowHeight = size.height
            } else {
                rowWidth += size.width + spacing
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        return CGSize(width: width.isFinite ? width : rowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
