import SwiftUI

struct GeneralPage: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var flags: FeatureFlags
    @State private var workMode: WorkMode = .daily
    @State private var permDefault: Bool = true
    @State private var permAuto: Bool = true
    @State private var permFull: Bool = true
    @State private var openTarget: String = "Ghostty"
    @State private var showInMenuBar: Bool = true
    @State private var preventSleep: Bool = true
    @StateObject private var backgroundBridge: BackgroundBridgeService = .shared
    @State private var requireCmdEnter: Bool = false
    @State private var speed: String = "Standard"
    @State private var followBehavior: FollowBehavior = .queue
    @State private var codeReview: CodeReview = .inline
    @State private var dictionaryEntries: [String] = ["Jane Doe"]
    @State private var recentDictations: [(stamp: String, text: String)] = [
        ("May 1, 11:42", "OK, this is a test, let's see how it works."),
        ("May 1, 11:35", "Hi, just testing how this works.")
    ]
    @State private var completionNotify: String = "Siempre"
    @State private var permissionNotify: Bool = true
    @State private var questionNotify: Bool = true
    @State private var syncArchiveWithCodex: Bool = SyncSettings.syncArchiveWithCodex
    @State private var syncRenamesWithCodex: Bool = SyncSettings.syncRenamesWithCodex
    @State private var autoReloadOnFocus: Bool = SyncSettings.autoReloadOnFocus

    enum WorkMode: Hashable { case coding, daily }
    enum FollowBehavior: Hashable { case queue, drive }
    enum CodeReview: Hashable { case inline, detached }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "General")

#if DEBUG
            // Beta + Experimental toggles ship in dev builds only. Release
            // builds compile both flags as `let beta = false` /
            // `let experimental = false` (see FeatureFlags.swift), so the
            // setter Binding below cannot exist there. Hiding the whole
            // card keeps the Settings page tidy and prevents users on a
            // notarized build from poking at half-finished surfaces.
            SectionLabel(title: "Feature previews")
            SettingsCard {
                ToggleRow(
                    title: "Beta features",
                    detail: "Show features in active development. They generally work but may still have rough edges. Off by default.",
                    isOn: Binding(
                        get: { flags.beta },
                        set: { flags.beta = $0 }
                    )
                )
                CardDivider()
                ToggleRow(
                    title: "Experimental features",
                    detail: "Show very early features that may not work well yet. For previewing only, not for serious use. Off by default.",
                    isOn: Binding(
                        get: { flags.experimental },
                        set: { flags.experimental = $0 }
                    )
                )
            }
            .padding(.bottom, 8)
#endif

            if flags.experimental {
                Text("Work mode")
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text("Choose how much technical detail Clawix shows")
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .padding(.bottom, 14)

                HStack(spacing: 12) {
                    WorkModeCard(
                        icon: "chevron.left.forwardslash.chevron.right",
                        title: "For coding",
                        subtitle: "More technical responses and finer control",
                        isOn: workMode == .coding
                    ) { workMode = .coding }
                    WorkModeCard(
                        icon: "bubble.left.and.bubble.right",
                        title: "For daily work",
                        subtitle: "Same power, fewer technical details...",
                        isOn: workMode == .daily
                    ) { workMode = .daily }
                }
                .padding(.bottom, 4)

                SectionLabel(title: "Permissions")
                SettingsCard {
                    ToggleRow(
                        title: "Default permissions",
                        detail: "By default, Clawix can read and edit files in your workspace. It can request additional access when needed.",
                        isOn: $permDefault
                    )
                    CardDivider()
                    ToggleRow(
                        title: "Automatic review",
                        detail: "Clawix can read and edit files in your workspace. Clawix automatically reviews requests for additional access. Auto-review may make mistakes. Learn more about the elevated risks.",
                        isOn: $permAuto
                    )
                    CardDivider()
                    ToggleRow(
                        title: "Full access",
                        detail: "When Clawix runs with full access, it can edit any file on your computer and run commands over the network without your authorization. This significantly increases the risk of data loss, leaks, or unexpected behavior. Learn more about the elevated risks.",
                        isOn: $permFull
                    )
                }
            }

            SectionLabel(title: "General")
            SettingsCard {
                DropdownRow(
                    title: "Language",
                    detail: "App interface language",
                    options: AppLanguage.allCases.map { ($0, $0.displayName) },
                    selection: Binding(
                        get: { appState.preferredLanguage },
                        set: { appState.preferredLanguage = $0 }
                    )
                )
                CardDivider()
                ToggleRow(
                    title: "Run bridge in background",
                    detail: "Registers a LaunchAgent helper that keeps a bridge process alive even after Clawix is fully quit. Closing the window already keeps the in-process bridge alive thanks to the menu bar item; this toggle is a foundation for the upcoming \"daemon owns chat state\" mode and currently registers a stub helper that won't have your chats yet. Status: \(backgroundBridge.statusLabel)\(backgroundBridge.lastError.map { " — \($0)" } ?? "")",
                    isOn: Binding(
                        get: { backgroundBridge.isEnabled },
                        set: { backgroundBridge.toggle($0) }
                    )
                )
                if flags.experimental {
                    CardDivider()
                    SegmentedRow(
                        title: "Agent runtime",
                        detail: appState.selectedAgentRuntime == .opencode
                            ? "OpenCode uses \(appState.openCodeModelSelection). Restart the background bridge after switching."
                            : "Codex remains the default runtime.",
                        options: AgentRuntimeChoice.visibleCases().map { ($0, $0.label) },
                        selection: $appState.selectedAgentRuntime
                    )
                    CardDivider()
                    DropdownRow(
                        title: "OpenCode model",
                        detail: "Provider/model id used when OpenCode is active. DeepSeek V4 Pro is selected by default.",
                        options: [(AgentRuntimeChoice.defaultOpenCodeModel, AgentRuntimeChoice.defaultOpenCodeModel)],
                        selection: Binding(
                            get: { appState.openCodeModelSelection },
                            set: {
                                appState.selectedModel = $0
                                appState.selectedAgentRuntime = .opencode
                            }
                        )
                    )
                    CardDivider()
                    DropdownRow(
                        title: "Default open destination",
                        detail: "Where files and folders open by default",
                        options: [("Ghostty", "Ghostty"), ("Terminal", "Terminal"), ("VS Code", "VS Code")],
                        selection: $openTarget,
                        iconForOption: { openTargetIcon(for: $0) }
                    )
                    CardDivider()
                    ToggleRow(
                        title: "Show in the menu bar",
                        detail: "Keep Clawix in the macOS menu bar when the main window closes",
                        isOn: $showInMenuBar
                    )
                    CardDivider()
                    ActionPillRow(
                        title: "Popover keyboard shortcut",
                        detail: "Set a global keyboard shortcut for the popover. Leave empty to keep it disabled.",
                        primaryLabel: "Change",
                        trailingDisabled: "⌥Space",
                        isEnabled: false,
                        onPrimary: {}
                    )
                    CardDivider()
                    ToggleRow(
                        title: "Prevent sleep during execution",
                        detail: "Keep the computer awake while Clawix is running a chat",
                        isOn: $preventSleep
                    )
                    CardDivider()
                    ToggleRow(
                        title: "Require ⌘ + Return to send long prompts",
                        detail: "When enabled, multi-line prompts require ⌘ + Return to send.",
                        isOn: $requireCmdEnter
                    )
                    CardDivider()
                    DropdownRow(
                        title: "Speed",
                        detail: "Choose how fast inference runs in chats, sub-agents and compaction. Fast uses more of the plan",
                        options: [
                            ("Standard", "Standard"),
                            ("Fast", "Fast"),
                            ("Auto", "Auto")
                        ],
                        selection: $speed
                    )
                    CardDivider()
                    SegmentedRow(
                        title: "Follow-up behavior",
                        detail: "Queue follow-up messages while Clawix runs, or steer the current run. Press ⌘Return to do the opposite for a single message.",
                        options: [(.queue, L10n.t("Queue")), (.drive, L10n.t("Drive"))],
                        selection: $followBehavior
                    )
                    CardDivider()
                    SegmentedRow(
                        title: "Code review",
                        detail: "Start /review in the current chat when possible, or open a separate review chat",
                        options: [(.inline, L10n.t("Inline")), (.detached, L10n.t("Detached"))],
                        selection: $codeReview
                    )
                    CardDivider()
                    ImportAgentRow()
                }
            }

            SectionLabel(title: "Sync with Codex")
            SettingsCard {
                ToggleRow(
                    title: "Sync archived chats with Codex",
                    detail: "When you archive or unarchive a chat, mirror that to Codex CLI. Disable to keep archive state local to this app. Reactivating sync does not propagate previous local-only changes.",
                    isOn: Binding(
                        get: { syncArchiveWithCodex },
                        set: { newValue in
                            syncArchiveWithCodex = newValue
                            SyncSettings.syncArchiveWithCodex = newValue
                        }
                    )
                )
                CardDivider()
                ToggleRow(
                    title: "Sync chat renames with Codex",
                    detail: "When you rename a chat, also update the title in Codex CLI. Disable to keep custom titles only in this app.",
                    isOn: Binding(
                        get: { syncRenamesWithCodex },
                        set: { newValue in
                            syncRenamesWithCodex = newValue
                            SyncSettings.syncRenamesWithCodex = newValue
                        }
                    )
                )
                CardDivider()
                PinsSourceInfoRow()
            }

            HiddenCodexFoldersSection()

            if flags.experimental {
                SectionLabel(title: "Dictation")
                SettingsCard {
                    ActionPillRow(
                        title: "Push-to-dictate keyboard shortcut",
                        detail: "Hold down anywhere on the desktop to dictate where the cursor is",
                        primaryLabel: "Set",
                        trailingDisabled: "Off",
                        isEnabled: false,
                        onPrimary: {}
                    )
                    CardDivider()
                    ActionPillRow(
                        title: "Toggle dictation keyboard shortcut",
                        detail: "Press once anywhere on the desktop to dictate, press again to stop",
                        primaryLabel: "Set",
                        trailingDisabled: "Off",
                        isEnabled: false,
                        onPrimary: {}
                    )
                    CardDivider()
                    DictionaryExpandableRow(entries: $dictionaryEntries)
                    ForEach(Array(recentDictations.enumerated()), id: \.offset) { _, item in
                        CardDivider()
                        RecentDictationRow(stamp: item.stamp, text: item.text)
                    }
                }

                SectionLabel(title: "Notifications")
                SettingsCard {
                    DropdownRow(
                        title: "Enable completion notifications",
                        detail: "Set when Clawix notifies you it has finished",
                        options: [
                            ("Siempre", "Siempre"),
                            ("Solo en segundo plano", "Solo en segundo plano"),
                            ("Nunca", "Nunca")
                        ],
                        selection: $completionNotify
                    )
                    CardDivider()
                    ToggleRow(
                        title: "Enable permission notifications",
                        detail: "Show alerts when notification permissions are required",
                        isOn: $permissionNotify
                    )
                    CardDivider()
                    ToggleRow(
                        title: "Enable question notifications",
                        detail: "Show alerts when your input is needed to continue",
                        isOn: $questionNotify
                    )
                }
            }

            SectionLabel(title: "App behavior")
            SettingsCard {
                ToggleRow(
                    title: "Auto-refresh on focus",
                    detail: "Reload chats from Codex automatically when this app becomes the active window.",
                    isOn: Binding(
                        get: { autoReloadOnFocus },
                        set: { newValue in
                            autoReloadOnFocus = newValue
                            SyncSettings.autoReloadOnFocus = newValue
                        }
                    )
                )
            }

            SectionLabel(title: "Danger zone")
            SettingsCard {
                ResetLocalOverridesRow()
            }
        }
    }

}

struct PinsSourceInfoRow: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pins")
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Color(white: 0.94))
                Text("Pins are stored locally in Clawix and session state is synchronized through the ClawJS sessions adapter.")
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Color(white: 0.55))
            }
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct HiddenCodexFoldersSection: View {
    @EnvironmentObject var appState: AppState
    @State private var hidden: [String] = []

    var body: some View {
        SectionLabel(title: "Hidden Codex folders")
        SettingsCard {
            if hidden.isEmpty {
                HStack {
                    Text("No hidden folders. Right-click a Codex folder in the sidebar to hide it.")
                        .font(BodyFont.system(size: 12, wght: 500))
                        .foregroundColor(Color(white: 0.55))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            } else {
                ForEach(Array(hidden.enumerated()), id: \.element) { idx, path in
                    if idx > 0 { CardDivider() }
                    HiddenFolderRow(path: path) {
                        appState.showCodexRoot(path: path)
                        reload()
                    }
                }
            }
        }
        .onAppear { reload() }
        .onChange(of: appState.projects) { _, _ in reload() }
    }

    private func reload() {
        hidden = appState.hiddenCodexRoots()
    }
}

struct HiddenFolderRow: View {
    let path: String
    let onShow: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text((path as NSString).lastPathComponent)
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Color(white: 0.94))
                Text(path)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Color(white: 0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            Button("Show", action: onShow)
                .buttonStyle(SheetCancelButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct ResetLocalOverridesRow: View {
    @EnvironmentObject var appState: AppState
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reset local overrides")
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Color(white: 0.94))
                Text("Permanently delete all local pins, archives, custom titles, project overrides and hidden Codex folders. The app will resync from Codex on next refresh. Codex's data is not affected.")
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Color(white: 0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Reset") { presentConfirmation() }
                .buttonStyle(SheetDestructiveButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func presentConfirmation() {
        let counts = appState.localOverrideCounts()
        let header = NSLocalizedString(
            "This will permanently delete the following local data from this app:",
            comment: "reset local overrides body header"
        )
        let footer = NSLocalizedString(
            "After reset, the app will reload from Codex on the next refresh. Codex's data and other Codex apps are not affected. This cannot be undone.",
            comment: "reset local overrides body footer"
        )
        let lines = [
            String(format: "• %@: %d", NSLocalizedString("Pinned threads", comment: ""), counts.pins),
            String(format: "• %@: %d", NSLocalizedString("Local projects", comment: ""), counts.projects),
            String(format: "• %@: %d", NSLocalizedString("Chat-project overrides", comment: ""), counts.chatProjectOverrides),
            String(format: "• %@: %d", NSLocalizedString("Projectless markers", comment: ""), counts.projectlessThreads),
            String(format: "• %@: %d", NSLocalizedString("Local archive entries", comment: ""), counts.archives),
            String(format: "• %@: %d", NSLocalizedString("Custom titles", comment: ""), counts.titles),
            String(format: "• %@: %d", NSLocalizedString("Hidden Codex folders", comment: ""), counts.hiddenRoots)
        ].joined(separator: "\n")
        let body = "\(header)\n\n\(lines)\n\n\(footer)"
        appState.pendingConfirmation = ConfirmationRequest(
            title: "Reset local overrides?",
            body: LocalizedStringKey(body),
            confirmLabel: "Reset",
            isDestructive: true,
            onConfirm: { appState.resetLocalOverrides() }
        )
    }
}

struct WorkModeCard: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let isOn: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                LucideIcon.auto(icon, size: 14)
                    .foregroundColor(Color(white: 0.86))
                    .frame(width: 28, height: 28)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(BodyFont.system(size: 13, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                    Text(subtitle)
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        .frame(width: 16, height: 16)
                    if isOn {
                        Circle()
                            .fill(Color(red: 0.30, green: 0.55, blue: 1.0))
                            .frame(width: 16, height: 16)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(width: 18)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(white: 0.085))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isOn ? Color.white.opacity(0.16) : Color.white.opacity(0.06),
                                    lineWidth: 0.7)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct ImportAgentRow: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 30, height: 30)
                SettingsIcon(size: 19)
                    .foregroundColor(Color(white: 0.86))
                Text("2")
                    .font(BodyFont.system(size: 9, wght: 700))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color(red: 0.30, green: 0.55, blue: 1.0)))
                    .offset(x: 10, y: 10)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Import another agent configuration")
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text("Clawix detected useful preferences from another local agent on this Mac")
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer(minLength: 12)
            Button {} label: {
                Text("Import")
                    .font(BodyFont.system(size: 12, wght: 600))
                    .foregroundColor(Palette.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .disabled(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct CollapsibleRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @State private var open: Bool = false

    var body: some View {
        Button {
            open.toggle()
        } label: {
            HStack(alignment: .center, spacing: 14) {
                RowLabel(title: title, detail: detail)
                Spacer(minLength: 12)
                LucideIcon.auto(open ? "chevron.up" : "chevron.down", size: 11)
                    .foregroundColor(Palette.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct DictionaryExpandableRow: View {
    @Binding var entries: [String]
    @State private var open: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { open.toggle() }
            } label: {
                HStack(alignment: .center, spacing: 14) {
                    RowLabel(title: "Dictation dictionary",
                             detail: "Words or phrases dictation should recognize")
                    Spacer(minLength: 12)
                    LucideIcon.auto(open ? "chevron.up" : "chevron.down", size: 11)
                        .foregroundColor(Palette.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                VStack(spacing: 8) {
                    ForEach(entries.indices, id: \.self) { idx in
                        DictionaryEntryField(
                            text: $entries[idx],
                            onDelete: {
                                guard entries.indices.contains(idx) else { return }
                                entries.remove(at: idx)
                            }
                        )
                    }
                    Button {
                        entries.append("")
                    } label: {
                        HStack(spacing: 6) {
                            LucideIcon(.plus, size: 11)
                            Text("Add entry")
                                .font(BodyFont.system(size: 12.5))
                        }
                        .foregroundColor(Color(white: 0.65))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.black.opacity(0.30))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
    }
}

struct DictionaryEntryField: View {
    @Binding var text: String
    let onDelete: () -> Void
    @FocusState private var focused: Bool
    @State private var trashHovered: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .font(BodyFont.system(size: 13, wght: 500))
                .foregroundColor(Palette.textPrimary)
                .padding(.leading, 12)
                .padding(.vertical, 9)
            Spacer(minLength: 8)
            Button(action: onDelete) {
                LucideIcon(.trash, size: 13)
                    .foregroundColor(Color(white: trashHovered ? 0.94 : 0.55))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { trashHovered = $0 }
            .padding(.trailing, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.30))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(focused
                                ? Color(red: 0.30, green: 0.55, blue: 1.0).opacity(0.85)
                                : Color.white.opacity(0.08),
                                lineWidth: focused ? 1.0 : 0.5)
                )
        )
        .animation(.easeOut(duration: 0.12), value: focused)
    }
}

struct RecentDictationRow: View {
    let stamp: String
    let text: String
    @State private var copyHovered: Bool = false
    @State private var copied: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Text(stamp)
                .font(BodyFont.system(size: 12.5))
                .foregroundColor(Palette.textSecondary)
                .frame(width: 90, alignment: .leading)
            Text(text)
                .font(BodyFont.system(size: 12.5))
                .foregroundColor(Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 12)
            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
                withAnimation(.easeOut(duration: 0.12)) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.easeOut(duration: 0.18)) { copied = false }
                }
            } label: {
                Group {
                    if copied {
                        CheckIcon(size: 13)
                    } else {
                        CopyIconViewSquircle(
                            color: Color(white: copyHovered ? 0.94 : 0.60),
                            lineWidth: 1.0
                        )
                        .frame(width: 13, height: 13)
                    }
                }
                .foregroundColor(Color(white: copyHovered ? 0.94 : 0.60))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { copyHovered = $0 }
            .hoverHint(L10n.t("Copy"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
