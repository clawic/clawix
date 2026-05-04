import SwiftUI

private let chatRailMaxWidth: CGFloat = 720

struct ChatView: View {
    let chatId: UUID
    @EnvironmentObject var appState: AppState

    @State private var workMenuOpen = false
    @State private var branchMenuOpen = false
    @State private var branchCreateOpen = false
    @State private var branchSearch = ""
    /// Toggled by the "N mensajes anteriores ›" link. Reset whenever
    /// the chat selection changes so each chat starts collapsed.
    @State private var showAllMessages = false

    private var chat: Chat? {
        appState.chats.first { $0.id == chatId }
    }

    /// Default-collapsed view shows the last user prompt and the
    /// assistant reply right before it (the second-to-last user turn
    /// onwards). Everything earlier is hidden behind the
    /// "N mensajes anteriores" link so opening a long conversation
    /// doesn't dump the whole history at once.
    ///
    /// `hiddenLabelCount` is the number we show in the disclosure: it
    /// matches the runtime count, where each reasoning chunk and each tool
    /// item folded under an assistant turn counts as its own "message"
    /// (a 4-command exec block contributes 4, not 1). Without this
    /// expansion the disclosure undercounts by ~7-13 per turn.
    private func visibleSlice(of messages: [ChatMessage]) -> (hiddenLabelCount: Int, slice: ArraySlice<ChatMessage>) {
        if showAllMessages || messages.count <= 3 {
            return (0, messages[messages.startIndex..<messages.endIndex])
        }
        let userIndices = messages.enumerated()
            .compactMap { $0.element.role == .user ? $0.offset : nil }
        let visibleStart: Int
        if userIndices.count >= 2 {
            visibleStart = userIndices[userIndices.count - 2]
        } else if let only = userIndices.first {
            visibleStart = only
        } else {
            visibleStart = 0
        }
        let hidden = messages[messages.startIndex..<visibleStart]
            .reduce(0) { acc, m in acc + ChatView.messageWeight(of: m) }
        return (hidden, messages[visibleStart..<messages.endIndex])
    }

    /// Maps one `ChatMessage` to the "messages anteriores" weight used by
    /// the disclosure counter. User messages count as one; assistant turns
    /// count one per reasoning chunk plus one per tool item (so a 4-command
    /// exec block contributes 4, not 1).
    static func messageWeight(of message: ChatMessage) -> Int {
        if message.role == .user { return 1 }
        if message.timeline.isEmpty {
            return message.content.isEmpty ? 0 : 1
        }
        return message.timeline.reduce(0) { acc, entry in
            switch entry {
            case .reasoning: return acc + 1
            case .tools(_, let items): return acc + items.count
            }
        }
    }

    var body: some View {
        RenderProbe.tick("ChatView")
        return Group {
            if let chat {
                let (hiddenLabelCount, slice) = visibleSlice(of: chat.messages)
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 28) {
                                if hiddenLabelCount > 0 {
                                    PreviousMessagesLink(count: hiddenLabelCount) {
                                        // Anchor the scroll on the first message of
                                        // the collapsed slice so expanding inserts
                                        // the older history above without pushing
                                        // the currently visible turn out of view.
                                        let anchorId = slice.first?.id
                                        showAllMessages = true
                                        if let anchorId {
                                            DispatchQueue.main.async {
                                                proxy.scrollTo(anchorId, anchor: .top)
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                let lastUserMessageId = chat.messages.last(where: { $0.role == .user })?.id
                                let lastAssistantMessageId = chat.messages.last(where: {
                                    $0.role == .assistant && $0.streamingFinished && !$0.isError
                                })?.id
                                let responseStreaming: Bool = {
                                    if let lastAssistant = chat.messages.last(where: { $0.role == .assistant }) {
                                        return !lastAssistant.streamingFinished
                                    }
                                    return chat.hasActiveTurn
                                }()
                                ForEach(slice) { msg in
                                    MessageRow(
                                        chatId: chat.id,
                                        message: msg,
                                        isLastUserMessage: msg.id == lastUserMessageId,
                                        isLastAssistantMessage: msg.id == lastAssistantMessageId,
                                        responseStreaming: responseStreaming
                                    )
                                    .id(msg.id)
                                }
                            }
                            .textSelection(.enabled)
                            .frame(maxWidth: chatRailMaxWidth)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 24)
                            .padding(.top, 24)
                            .padding(.bottom, 12)
                        }
                        .onChange(of: chat.messages.count) { _, _ in
                            if let last = chat.messages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                        .onAppear { appState.ensureSelectedChat() }
                        .onChange(of: chatId) { _, _ in
                            appState.ensureSelectedChat()
                            showAllMessages = false
                            appState.requestComposerFocus()
                        }
                    }

                    VStack(spacing: 14) {
                        ComposerView(chatMode: true)
                            .frame(maxWidth: chatRailMaxWidth)

                        HStack(spacing: 14) {
                            ChatFooterPill(
                                icon: "desktopcomputer",
                                label: String(localized: "Work locally", bundle: AppLocale.bundle, locale: AppLocale.current),
                                accessibilityLabel: "Work mode",
                                isOpen: workMenuOpen
                            ) {
                                workMenuOpen.toggle()
                            }
                            .anchorPreference(key: WorkPillAnchorKey.self, value: .bounds) { $0 }

                            if chat.hasGitRepo {
                                ChatFooterPill(
                                    icon: "arrow.triangle.branch",
                                    label: chat.branch ?? "main",
                                    accessibilityLabel: "Change branch",
                                    isOpen: branchMenuOpen
                                ) {
                                    branchMenuOpen.toggle()
                                }
                                .anchorPreference(key: BranchPillAnchorKey.self, value: .bounds) { $0 }
                            }

                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: chatRailMaxWidth)
                        .padding(.leading, 6)
                    }
                    .padding(.horizontal, 38)
                    .padding(.top, 14)
                    .padding(.bottom, 22)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.background)
                .overlayPreferenceValue(WorkPillAnchorKey.self) { anchor in
                    GeometryReader { proxy in
                        if workMenuOpen, let anchor {
                            let buttonFrame = proxy[anchor]
                            WorkLocallyMenuPopup(isPresented: $workMenuOpen)
                                .alignmentGuide(.top) { d in d[.bottom] - buttonFrame.minY + 6 }
                                .alignmentGuide(.leading) { d in d[.leading] - buttonFrame.minX + 4 }
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .transition(.softNudge(y: 4))
                        }
                    }
                    .allowsHitTesting(workMenuOpen)
                }
                .overlayPreferenceValue(BranchPillAnchorKey.self) { anchor in
                    GeometryReader { proxy in
                        if branchMenuOpen, let anchor {
                            let buttonFrame = proxy[anchor]
                            BranchPickerPopup(
                                isPresented: $branchMenuOpen,
                                searchText: $branchSearch,
                                branches: chat.availableBranches,
                                currentBranch: chat.branch,
                                uncommittedFiles: chat.uncommittedFiles,
                                onSelect: { branch in
                                    appState.switchBranch(chatId: chat.id, to: branch)
                                    branchMenuOpen = false
                                },
                                onCreate: {
                                    branchMenuOpen = false
                                    branchCreateOpen = true
                                }
                            )
                            .alignmentGuide(.top) { d in d[.bottom] - buttonFrame.minY + 6 }
                            .alignmentGuide(.leading) { d in d[.leading] - buttonFrame.minX + 4 }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .transition(.softNudge(y: 4))
                        }
                    }
                    .allowsHitTesting(branchMenuOpen)
                }
                .animation(.easeOut(duration: 0.20), value: workMenuOpen)
                .animation(.easeOut(duration: 0.20), value: branchMenuOpen)
                .sheet(isPresented: $branchCreateOpen) {
                    BranchCreateSheet(
                        initialName: suggestedNewBranchName(for: chat),
                        onCancel: { branchCreateOpen = false },
                        onCreate: { name in
                            appState.createBranch(chatId: chat.id, name: name)
                            branchCreateOpen = false
                        }
                    )
                }
            } else {
                Text("Chat not found")
                    .foregroundColor(Palette.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.background)
            }
        }
    }

    private func suggestedNewBranchName(for chat: Chat) -> String {
        // Prefix `clawix/` + slug derived from title.
        let slugSource = chat.title.lowercased()
        let allowed = CharacterSet.lowercaseLetters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: "-/"))
        var slug = ""
        for scalar in slugSource.unicodeScalars {
            if allowed.contains(scalar) {
                slug.unicodeScalars.append(scalar)
            } else if scalar == " " || scalar == "_" {
                slug.append("-")
            }
        }
        slug = slug.replacingOccurrences(of: "--", with: "-")
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.isEmpty { slug = "feature" }
        return "clawix/" + String(slug.prefix(40))
    }
}

// MARK: - Anchor keys for footer pills

private struct WorkPillAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

private struct BranchPillAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

// MARK: - Previous-messages affordance

/// "N mensajes anteriores ›" link rendered above the visible chat slice
/// when older messages are collapsed. Tapping it expands the view to
/// the full history.
private struct PreviousMessagesLink: View {
    let count: Int
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(L10n.previousMessages(count))
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: hovered ? 0.78 : 0.55))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(white: hovered ? 0.78 : 0.55))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) { hovered = h }
        }
        .accessibilityLabel(L10n.previousMessages(count))
    }
}

// MARK: - User mention parsing
//
// On send, the composer flattens staged attachments into the message body
// as `@/absolute/path` tokens prefixed before the text (see
// `AppState.sendMessage`). Rendering them verbatim in the user bubble
// would show raw paths to the reader, so we parse them back out and
// render image mentions as squircle thumbnails above the bubble. The
// raw `message.content` is preserved untouched so copy and edit still
// see the mention syntax.

private enum UserBubbleContent {
    struct Parsed {
        var images: [URL]
        var files: [URL]
        var text: String
    }

    private static let imageExts: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "tif", "bmp", "webp"
    ]

    static func parse(_ raw: String) -> Parsed {
        // Mentions in user messages come from `AppState.sendMessage`, which
        // builds them as `@<absolute-path>` joined by single spaces and
        // separated from the body by `\n\n`. Paths can contain spaces
        // (e.g. "My Project Folder"), so we can't stop at the first
        // whitespace. Stop on either ` @/` (next mention), `\n`, or end of
        // string. Lazy `.+?` ensures we don't swallow the body.
        let pattern = #"@(/.+?)(?=\s+@/|\n|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return Parsed(
                images: [], files: [],
                text: raw.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        let ns = raw as NSString
        let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
        var images: [URL] = []
        var files: [URL] = []
        var ranges: [NSRange] = []
        for m in matches where m.numberOfRanges >= 2 {
            let path = ns.substring(with: m.range(at: 1))
                .trimmingCharacters(in: .whitespaces)
            guard path.hasPrefix("/") else { continue }
            let url = URL(fileURLWithPath: path)
            if imageExts.contains(url.pathExtension.lowercased()) {
                images.append(url)
            } else {
                files.append(url)
            }
            ranges.append(m.range)
        }
        var stripped: NSString = ns
        for r in ranges.reversed() {
            stripped = stripped.replacingCharacters(in: r, with: "") as NSString
        }
        let text = (stripped as String)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return Parsed(images: images, files: files, text: text)
    }
}

private struct UserMentionPreviews: View {
    let parsed: UserBubbleContent.Parsed
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if !parsed.images.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(parsed.images.enumerated()), id: \.offset) { _, url in
                        UserImageThumbnail(url: url)
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    appState.imagePreviewURL = url
                                }
                            }
                    }
                }
            }
            if !parsed.files.isEmpty {
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(Array(parsed.files.enumerated()), id: \.offset) { _, url in
                        UserFileMentionChip(url: url)
                    }
                }
            }
        }
    }
}

private struct UserImageThumbnail: View {
    let url: URL
    @State private var image: NSImage? = nil
    @State private var hovered = false

    private let side: CGFloat = 86
    private let radius: CGFloat = 16

    var body: some View {
        ZStack {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.05)
                Image(systemName: "photo")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(Color(white: 0.45))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.white.opacity(hovered ? 0.18 : 0.08), lineWidth: 0.6)
        )
        .scaleEffect(hovered ? 0.985 : 1.0)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .onHover { hovered = $0 }
        .help(url.lastPathComponent)
        .task(id: url) {
            let loaded = await Task.detached(priority: .userInitiated) {
                NSImage(contentsOf: url)
            }.value
            self.image = loaded
        }
    }
}

private struct UserFileMentionChip: View {
    let url: URL

    var body: some View {
        HStack(spacing: 6) {
            FileChipIcon(size: 11)
                .foregroundColor(Color(white: 0.78))
            Text(url.lastPathComponent)
                .font(.system(size: 14))
                .foregroundColor(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .help(url.path)
    }
}

// MARK: - Message row

private struct MessageRow: View {
    let chatId: UUID
    let message: ChatMessage
    var isLastUserMessage: Bool = false
    var isLastAssistantMessage: Bool = false
    var responseStreaming: Bool = false
    @EnvironmentObject var appState: AppState
    @State private var rowHovered = false
    @State private var justCopied = false
    @State private var copyResetTask: Task<Void, Never>? = nil
    @State private var isEditing = false
    @State private var editDraft: String = ""
    /// Toggled by the in-bubble "N mensajes anteriores" disclosure. The
    /// hidden portion = every timeline entry up to and including the last
    /// `.tools` group; the visible portion is the closing reasoning chunk
    /// (the final answer Clawix writes after the work is done).
    @State private var timelineExpanded = false

    private var isUser: Bool { message.role == .user }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 10) {
            if isUser {
                if isEditing {
                    UserMessageEditor(
                        text: $editDraft,
                        onCancel: { isEditing = false },
                        onSubmit: {
                            let trimmed = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            appState.editUserMessage(
                                chatId: chatId,
                                messageId: message.id,
                                newContent: trimmed
                            )
                            isEditing = false
                        }
                    )
                    .frame(maxWidth: CGFloat.infinity)
                } else {
                    let parsed = UserBubbleContent.parse(message.content)
                    if !parsed.images.isEmpty || !parsed.files.isEmpty {
                        UserMentionPreviews(parsed: parsed)
                    }
                    if !parsed.text.isEmpty {
                        Text(parsed.text)
                            .font(.system(size: 14))
                            .foregroundColor(Palette.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                }
            } else {
                if let summary = message.workSummary,
                   !message.isError,
                   !summary.isActive,
                   !summary.items.isEmpty {
                    WorkSummaryHeader(summary: summary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Clawix-style timeline: reasoning summary chunks and
                // tool groups interleave in the order they arrived, so
                // the user reads "text → Ran 1 command → text → Ran 3
                // commands" exactly as Clawix emitted them. When the turn
                // produced any tool work, the prelude collapses into a
                // "N mensajes anteriores" disclosure inside the bubble,
                // matching how Clawix hides intermediate work behind the
                // final answer until the user opens it.
                let split = splitTimeline(message.timeline)
                if !split.hidden.isEmpty {
                    InlinePreviousMessagesLink(
                        count: split.hidden.reduce(0) { acc, e in
                            switch e {
                            case .reasoning: return acc + 1
                            case .tools(_, let items): return acc + items.count
                            }
                        },
                        expanded: timelineExpanded
                    ) {
                        withAnimation(.easeOut(duration: 0.16)) {
                            timelineExpanded.toggle()
                        }
                    }
                    Rectangle()
                        .fill(Color(white: 0.18))
                        .frame(height: 0.5)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 2)
                    if timelineExpanded {
                        ForEach(split.hidden) { entry in
                            timelineEntry(entry)
                        }
                    }
                }
                ForEach(split.visible) { entry in
                    timelineEntry(entry)
                }

                if !message.content.isEmpty {
                    let segments = PlanSegmenter.segments(from: message.content)
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        switch segment {
                        case .text(let body):
                            AssistantMarkdownText(
                                text: body,
                                weight: message.isError ? .regular : .light,
                                color: message.isError
                                    ? Color(red: 0.95, green: 0.45, blue: 0.45)
                                    : Palette.textPrimary.opacity(0.85)
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        case .plan(let body, let completed):
                            PlanCardView(content: body, completed: completed)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                // One pill per file the agent edited during this turn,
                // mirroring the Codex Desktop "README.md / Document · MD"
                // attachment cards. Order matches first-touch, deduped.
                let changedFiles = Self.changedFilePaths(in: message.timeline)
                if !changedFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(changedFiles, id: \.self) { path in
                            ChangedFileCard(path: path)
                                .frame(maxWidth: chatRailMaxWidth * 0.7, alignment: .leading)
                        }
                    }
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // The runtime shows a "Sitio web · Abrir" preview card under the
                // final answer whenever the message embeds a URL. Limit it
                // to the very last assistant message so older turns stay
                // tight. Skip when the message carries a Plan card so a
                // URL inside the plan body doesn't double up as a separate
                // trailing card.
                if isLastAssistantMessage,
                   message.streamingFinished,
                   !message.isError,
                   !PlanSegmenter.containsPlan(message.content),
                   let lastURL = AssistantMarkdown.extractLinkURLs(in: message.content).last {
                    LinkPreviewCard(url: lastURL)
                        .padding(.top, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !message.streamingFinished && !message.isError {
                    ThinkingShimmer(text: String(localized: "Thinking", bundle: AppLocale.bundle, locale: AppLocale.current))
                        .padding(.top, 2)
                }
            }

            if !isEditing {
                let alwaysVisible = (isUser && isLastUserMessage) || (!isUser && isLastAssistantMessage)
                actionBar
                    .opacity(alwaysVisible ? 1 : (rowHovered ? 1 : 0))
                    .allowsHitTesting(alwaysVisible || rowHovered)
                    .animation(.easeOut(duration: 0.15), value: rowHovered)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            rowHovered = hovering
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(.leading, isUser ? chatRailMaxWidth * 0.2 : 0)
        .accessibilityLabel(isUser
                            ? L10n.a11yYou(message.content)
                            : L10n.a11yAssistant(message.content))
    }

    /// Walk the message timeline and return every absolute file path the
    /// agent edited via apply_patch during the turn, deduped, in
    /// first-touch order. Drives the trailing `ChangedFileCard` strip.
    static func changedFilePaths(in timeline: [AssistantTimelineEntry]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for entry in timeline {
            guard case .tools(_, let items) = entry else { continue }
            for item in items {
                guard case .fileChange(let paths) = item.kind else { continue }
                for path in paths where seen.insert(path).inserted {
                    result.append(path)
                }
            }
        }
        return result
    }

    /// Hidden = every timeline entry up to and including the last `.tools`
    /// group; visible = whatever reasoning chunks Clawix wrote AFTER the
    /// last tool finished (the closing summary). Returns hidden=[] when
    /// the assistant never used a tool, so short answers render flat.
    private func splitTimeline(
        _ timeline: [AssistantTimelineEntry]
    ) -> (hidden: [AssistantTimelineEntry], visible: [AssistantTimelineEntry]) {
        var lastToolsIdx: Int? = nil
        for (i, entry) in timeline.enumerated() {
            if case .tools = entry { lastToolsIdx = i }
        }
        guard let idx = lastToolsIdx, idx + 1 < timeline.count else {
            return ([], timeline)
        }
        return (Array(timeline[..<(idx + 1)]), Array(timeline[(idx + 1)...]))
    }

    @ViewBuilder
    private func timelineEntry(_ entry: AssistantTimelineEntry) -> some View {
        switch entry {
        case .reasoning(_, let text):
            AssistantMarkdownText(
                text: text,
                weight: .light,
                color: Palette.textPrimary.opacity(0.85)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        case .tools(_, let items):
            ToolGroupView(items: items)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        let copyLabel = justCopied
            ? String(localized: "Copied", bundle: AppLocale.bundle, locale: AppLocale.current)
            : String(localized: "Copy", bundle: AppLocale.bundle, locale: AppLocale.current)
        let editLabel = String(localized: "Edit", bundle: AppLocale.bundle, locale: AppLocale.current)
        let branchLabel = String(localized: "Branch out", bundle: AppLocale.bundle, locale: AppLocale.current)

        HStack(spacing: -1) {
            if isUser {
                Spacer(minLength: 0)
                timestampLabel
                    .opacity(isLastUserMessage ? (rowHovered ? 1 : 0) : 1)
                    .animation(.easeOut(duration: 0.15), value: rowHovered)
                MessageActionIcon(kind: .copy(showCheck: justCopied),
                                  label: copyLabel,
                                  action: handleCopy)
                if isLastUserMessage && !responseStreaming {
                    MessageActionIcon(kind: .pencil,
                                      label: editLabel) {
                        editDraft = message.content
                        isEditing = true
                    }
                }
            } else {
                MessageActionIcon(kind: .copy(showCheck: justCopied),
                                  label: copyLabel,
                                  action: handleCopy)
                MessageActionIcon(kind: .branchArrows,
                                  label: branchLabel) {}
                timestampLabel
                    .opacity(isLastAssistantMessage ? (rowHovered ? 1 : 0) : 1)
                    .animation(.easeOut(duration: 0.15), value: rowHovered)
            }
        }
        .padding(.leading, isUser ? 0 : -6)
        .padding(.trailing, isUser ? -2 : 0)
        .padding(.top, isUser ? -3 : 0)
    }

    private var timestampLabel: some View {
        Text(formattedTimestamp)
            .font(.system(size: 11))
            .foregroundColor(Color(white: 0.45))
            .padding(.horizontal, 4)
    }

    private var formattedTimestamp: String {
        let cal = Calendar.current
        let timeFmt = DateFormatter()
        timeFmt.locale = Locale.current
        timeFmt.dateStyle = .none
        timeFmt.timeStyle = .short
        if cal.isDateInToday(message.timestamp) {
            return timeFmt.string(from: message.timestamp)
        }
        let startOfMsg = cal.startOfDay(for: message.timestamp)
        let startOfToday = cal.startOfDay(for: Date())
        let dayDiff = cal.dateComponents([.day], from: startOfMsg, to: startOfToday).day ?? 0
        if dayDiff >= 1 && dayDiff <= 6 {
            let weekdayFmt = DateFormatter()
            weekdayFmt.locale = Locale.current
            weekdayFmt.dateFormat = "EEEE"
            return "\(weekdayFmt.string(from: message.timestamp)), \(timeFmt.string(from: message.timestamp))"
        }
        let dateFmt = DateFormatter()
        dateFmt.locale = Locale.current
        dateFmt.dateStyle = .short
        dateFmt.timeStyle = .none
        return dateFmt.string(from: message.timestamp)
    }

    private func handleCopy() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(message.content, forType: .string)

        copyResetTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) {
            justCopied = true
        }
        copyResetTask = Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.2)) {
                    justCopied = false
                }
            }
        }
    }
}

private struct MessageActionIcon: View {
    enum Kind {
        case copy(showCheck: Bool)
        case pencil
        case branchArrows
        case system(String)
    }

    let kind: Kind
    let label: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(hovered ? 0.07 : 0))
                iconView
            }
            .frame(width: 27, height: 27)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) { hovered = h }
        }
        .accessibilityLabel(label)
        .hoverHint(label)
    }

    @ViewBuilder
    private var iconView: some View {
        switch kind {
        case .copy(let showCheck):
            if showCheck {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(white: hovered ? 0.94 : 0.78))
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            } else {
                CopyIconViewSquircle(color: Color(white: hovered ? 0.88 : 0.55), lineWidth: 0.85)
                    .frame(width: 14, height: 14)
                    .transition(.opacity)
            }
        case .pencil:
            PencilIconView(color: Color(white: hovered ? 0.88 : 0.55), lineWidth: 0.85)
                .frame(width: 16, height: 16)
        case .branchArrows:
            BranchArrowsIconView(color: Color(white: hovered ? 0.88 : 0.55), lineWidth: 0.85)
                .frame(width: 14, height: 14)
        case .system(let name):
            IconImage(name, size: 13)
                .foregroundColor(Color(white: hovered ? 0.82 : 0.45))
        }
    }
}

// MARK: - Inline editor for user messages

private struct UserMessageEditor: View {
    @Binding var text: String
    var onCancel: () -> Void
    var onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ComposerTextEditor(
                text: $text,
                contentHeight: .constant(0),
                autofocus: true,
                onSubmit: onSubmit
            )
            .frame(minHeight: 60)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 4)

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 13))
                        .foregroundColor(Palette.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(white: 0.22))
                        )
                }
                .buttonStyle(.plain)

                Button(action: onSubmit) {
                    Text("Send")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(white: 0.13))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(white: 0.22), lineWidth: 0.5)
        )
    }
}

private struct ChatFooterPill: View {
    let icon: String
    let label: String
    let accessibilityLabel: String
    var isOpen: Bool = false
    var action: () -> Void = {}

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                IconImage(icon, size: 12)
                Text(label)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(Color(white: (hovered || isOpen) ? 0.82 : 0.55))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - "Continue in" popup (work-locally pill)

private struct WorkLocallyMenuPopup: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelMenuHeader(String(localized: "Continue in", bundle: AppLocale.bundle, locale: AppLocale.current))

            WorkLocallyRow(
                icon: "desktopcomputer",
                label: String(localized: "Work locally", bundle: AppLocale.bundle, locale: AppLocale.current),
                trailing: .check
            ) {
                isPresented = false
            }
            WorkLocallyRow(
                icon: "gauge.with.dots.needle.33percent",
                label: String(localized: "Remaining usage limits", bundle: AppLocale.bundle, locale: AppLocale.current),
                trailing: .chevron
            ) {
                isPresented = false
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: 268, alignment: .leading)
        .menuStandardBackground()
        .background(MenuOutsideClickWatcher(isPresented: $isPresented))
    }
}

private struct WorkLocallyRow: View {
    enum Trailing { case none, check, chevron }

    let icon: String
    let label: String
    var trailing: Trailing = .none
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(MenuStyle.rowIcon)
                    .frame(width: 18, alignment: .center)
                Text(label)
                    .font(.system(size: 13.5))
                    .foregroundColor(MenuStyle.rowText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                switch trailing {
                case .none:
                    EmptyView()
                case .check:
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(MenuStyle.rowText)
                case .chevron:
                    Image(systemName: "chevron.right")
                        .font(.system(size: MenuStyle.rowTrailingIconSize, weight: .semibold))
                        .foregroundColor(MenuStyle.rowSubtle)
                }
            }
            .padding(.leading, MenuStyle.rowHorizontalPadding)
            .padding(.trailing, MenuStyle.rowHorizontalPadding
                                + (trailing == .chevron ? MenuStyle.rowTrailingIconExtra : 0))
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Branch picker popup

private struct BranchPickerPopup: View {
    @Binding var isPresented: Bool
    @Binding var searchText: String
    let branches: [String]
    let currentBranch: String?
    let uncommittedFiles: Int?
    let onSelect: (String) -> Void
    let onCreate: () -> Void

    @FocusState private var searchFocused: Bool

    private var filtered: [String] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return branches }
        return branches.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                SearchIcon(size: 12)
                    .foregroundColor(MenuStyle.rowSubtle)
                TextField(
                    String(localized: "Search branches", bundle: AppLocale.bundle, locale: AppLocale.current),
                    text: $searchText
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .foregroundColor(MenuStyle.rowText)
                .focused($searchFocused)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)

            ModelMenuHeader(String(localized: "Branches", bundle: AppLocale.bundle, locale: AppLocale.current))

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered, id: \.self) { branch in
                        BranchRow(
                            label: branch,
                            isCurrent: branch == currentBranch,
                            uncommittedFiles: branch == currentBranch ? uncommittedFiles : nil
                        ) {
                            onSelect(branch)
                        }
                    }
                }
            }
            .frame(maxHeight: 256)

            MenuStandardDivider()
                .padding(.vertical, 4)

            BranchCreateRow(action: onCreate)
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: 340, alignment: .leading)
        .menuStandardBackground()
        .background(MenuOutsideClickWatcher(isPresented: $isPresented))
        .onAppear { searchFocused = true }
    }
}

private struct BranchRow: View {
    let label: String
    let isCurrent: Bool
    let uncommittedFiles: Int?
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                BranchIcon(size: 13)
                    .foregroundColor(MenuStyle.rowIcon)
                    .frame(width: 18, alignment: .center)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 13.5))
                        .foregroundColor(MenuStyle.rowText)
                        .lineLimit(1)
                    if let files = uncommittedFiles, files > 0 {
                        Text(uncommittedLabel(files))
                            .font(.system(size: 11.5))
                            .foregroundColor(MenuStyle.rowSubtle)
                    }
                }
                Spacer(minLength: 8)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(MenuStyle.rowText)
                        .padding(.top, 1)
                }
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    private func uncommittedLabel(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "Uncommitted: 1 file", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        return String(format: String(localized: "Uncommitted: %d files", bundle: AppLocale.bundle, locale: AppLocale.current), count)
    }
}

private struct BranchCreateRow: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(MenuStyle.rowIcon)
                    .frame(width: 18, alignment: .center)
                Text(String(localized: "Create and switch to a new branch...", bundle: AppLocale.bundle, locale: AppLocale.current))
                    .font(.system(size: 13.5))
                    .foregroundColor(MenuStyle.rowText)
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - "Create and switch branch" sheet

private struct BranchCreateSheet: View {
    let initialName: String
    let onCancel: () -> Void
    let onCreate: (String) -> Void

    @State private var name: String
    @FocusState private var nameFocused: Bool

    init(initialName: String,
         onCancel: @escaping () -> Void,
         onCreate: @escaping (String) -> Void) {
        self.initialName = initialName
        self.onCancel = onCancel
        self.onCreate = onCreate
        self._name = State(initialValue: initialName)
    }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "Create and switch branch", bundle: AppLocale.bundle, locale: AppLocale.current))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Color(white: 0.97))
                Spacer(minLength: 12)
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(white: 0.70))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.bottom, 18)

            HStack {
                Text(String(localized: "Branch name", bundle: AppLocale.bundle, locale: AppLocale.current))
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: 0.78))
                Spacer(minLength: 8)
                Button {
                    // Prefix toggle is visual-only for now: same suggestion
                    // shape Clawix shows in screenshot.
                } label: {
                    Text(String(localized: "Set prefix", bundle: AppLocale.bundle, locale: AppLocale.current))
                        .font(.system(size: 12.5))
                        .foregroundColor(Color(white: 0.55))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)

            TextField("", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(Color(white: 0.95))
                .focused($nameFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(white: 0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                )
                .padding(.bottom, 22)

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button(action: onCancel) {
                    Text(String(localized: "Close", bundle: AppLocale.bundle, locale: AppLocale.current))
                }
                .buttonStyle(SheetCancelButtonStyle())

                Button {
                    guard !trimmed.isEmpty else { return }
                    onCreate(trimmed)
                } label: {
                    Text(String(localized: "Create and switch", bundle: AppLocale.bundle, locale: AppLocale.current))
                }
                .buttonStyle(SheetPrimaryButtonStyle(enabled: !trimmed.isEmpty))
                .disabled(trimmed.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .frame(width: 460)
        .sheetStandardBackground()
        .onAppear { nameFocused = true }
    }
}

private struct CopyIconView: View {
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let sq = s * 0.55
            let off = s * 0.135
            let r = s * 0.08

            let cx = size.width / 2
            let cy = size.height / 2

            let backRect = CGRect(
                x: cx - sq / 2 + off,
                y: cy - sq / 2 - off,
                width: sq,
                height: sq
            )
            let frontRect = CGRect(
                x: cx - sq / 2 - off,
                y: cy - sq / 2 + off,
                width: sq,
                height: sq
            )

            let backPath = Path(
                roundedRect: backRect,
                cornerSize: CGSize(width: r, height: r),
                style: .continuous
            )
            let frontPath = Path(
                roundedRect: frontRect,
                cornerSize: CGSize(width: r, height: r),
                style: .continuous
            )

            let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)

            context.drawLayer { ctx in
                ctx.clip(to: frontPath, options: .inverse)
                ctx.stroke(backPath, with: .color(color), style: stroke)
            }
            context.stroke(frontPath, with: .color(color), style: stroke)
        }
    }
}

private struct CopyIconViewSquircle: View {
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let sq = s * 0.62
            let off = s * 0.105
            let r = s * 0.145

            let cx = size.width / 2
            let cy = size.height / 2

            let backRect = CGRect(
                x: cx - sq / 2 + off,
                y: cy - sq / 2 - off,
                width: sq,
                height: sq
            )
            let frontRect = CGRect(
                x: cx - sq / 2 - off,
                y: cy - sq / 2 + off,
                width: sq,
                height: sq
            )

            let backPath = Path(
                roundedRect: backRect,
                cornerSize: CGSize(width: r, height: r),
                style: .continuous
            )
            let frontPath = Path(
                roundedRect: frontRect,
                cornerSize: CGSize(width: r, height: r),
                style: .continuous
            )

            let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)

            context.drawLayer { ctx in
                ctx.clip(to: frontPath, options: .inverse)
                ctx.stroke(backPath, with: .color(color), style: stroke)
            }
            context.stroke(frontPath, with: .color(color), style: stroke)
        }
    }
}

struct PencilIconView: View {
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let baseX = (size.width - s) / 2
            let baseY = (size.height - s) / 2

            // Pencil tilted 45 degrees, rounded cap upper-right, rounded tip lower-left.
            // Geometry parameterized along axis (a) and perpendicular (p).
            let ux: CGFloat = -0.7071
            let uy: CGFloat =  0.7071
            let nx: CGFloat = -uy
            let ny: CGFloat =  ux

            let w: CGFloat = 0.144
            let bodyLen: CGFloat = 0.54
            let taperLen: CGFloat = 0.21
            let transitionLen: CGFloat = 0.060
            let tipCapExt: CGFloat = 0.020
            let taperWidth: CGFloat = 0.132
            let tipWidth: CGFloat = 0.032
            let transitionOvershoot: CGFloat = 0.006
            let ferruleA: CGFloat = 0.065

            // Center the bbox of the pencil on (0.5, 0.5) regardless of length tweaks.
            let midA = (bodyLen + taperLen + tipCapExt - w) / 2
            let cx: CGFloat = 0.5 - midA * ux
            let cy: CGFloat = 0.5 - midA * uy

            func pt(_ a: CGFloat, _ p: CGFloat) -> CGPoint {
                CGPoint(
                    x: baseX + (cx + a * ux + p * nx) * s,
                    y: baseY + (cy + a * uy + p * ny) * s
                )
            }

            let bTop = pt(0,  w)
            let bBot = pt(0, -w)
            let backApex = pt(-w, 0)
            let mTop = pt(bodyLen,  w)
            let mBot = pt(bodyLen, -w)
            let tTop = pt(bodyLen + transitionLen,  taperWidth)
            let tBot = pt(bodyLen + transitionLen, -taperWidth)
            let tipUpper = pt(bodyLen + taperLen,  tipWidth)
            let tipLower = pt(bodyLen + taperLen, -tipWidth)
            let tipPoint = pt(bodyLen + taperLen + tipCapExt, 0)

            // 0.5523 is the standard cubic Bezier approximation factor for a quarter circle.
            let k: CGFloat = 0.5523
            let bcap1c1 = pt(-w * k, -w)
            let bcap1c2 = pt(-w,     -w * k)
            let bcap2c1 = pt(-w,      w * k)
            let bcap2c2 = pt(-w * k,  w)

            let transTopCtl = pt(bodyLen + transitionLen * 0.45,  w + transitionOvershoot)
            let transBotCtl = pt(bodyLen + transitionLen * 0.45, -(w + transitionOvershoot))

            var pencil = Path()
            pencil.move(to: bTop)
            pencil.addLine(to: mTop)
            pencil.addQuadCurve(to: tTop, control: transTopCtl)
            pencil.addLine(to: tipUpper)
            pencil.addQuadCurve(to: tipLower, control: tipPoint)
            pencil.addLine(to: tBot)
            pencil.addQuadCurve(to: mBot, control: transBotCtl)
            pencil.addLine(to: bBot)
            pencil.addCurve(to: backApex, control1: bcap1c1, control2: bcap1c2)
            pencil.addCurve(to: bTop,     control1: bcap2c1, control2: bcap2c2)
            pencil.closeSubpath()

            var ferrule = Path()
            ferrule.move(to: pt(ferruleA,  w))
            ferrule.addLine(to: pt(ferruleA, -w))

            let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            context.stroke(pencil, with: .color(color), style: stroke)
            context.stroke(ferrule, with: .color(color), style: stroke)
        }
    }
}

struct BranchArrowsIconView: View {
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let baseX = (size.width - s) / 2
            let baseY = (size.height - s) / 2

            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: baseX + x * s, y: baseY + y * s)
            }

            // Top: horizontal stem then NE diagonal with arrowhead.
            var topShaft = Path()
            topShaft.move(to: p(4.0 / 24, 12.0 / 24))
            topShaft.addLine(to: p(11.0 / 24, 12.0 / 24))
            topShaft.addLine(to: p(20.0 / 24, 3.0 / 24))

            var topHead = Path()
            topHead.move(to: p(14.0 / 24, 3.0 / 24))
            topHead.addLine(to: p(20.0 / 24, 3.0 / 24))
            topHead.addLine(to: p(20.0 / 24, 9.0 / 24))

            // Bottom: shorter SE diagonal with arrowhead, offset below the stem.
            var botShaft = Path()
            botShaft.move(to: p(13.0 / 24, 14.0 / 24))
            botShaft.addLine(to: p(20.0 / 24, 21.0 / 24))

            var botHead = Path()
            botHead.move(to: p(14.0 / 24, 21.0 / 24))
            botHead.addLine(to: p(20.0 / 24, 21.0 / 24))
            botHead.addLine(to: p(20.0 / 24, 15.0 / 24))

            let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            context.stroke(topShaft, with: .color(color), style: stroke)
            context.stroke(topHead, with: .color(color), style: stroke)
            context.stroke(botShaft, with: .color(color), style: stroke)
            context.stroke(botHead, with: .color(color), style: stroke)
        }
    }
}

// MARK: - In-bubble "N mensajes anteriores" disclosure

/// Sits at the top of an assistant bubble whose timeline starts with
/// reasoning + tool work. Renders "N mensajes anteriores" with a chevron
/// that rotates when toggled, mirroring the disclosure Clawix uses to
/// hide intermediate work behind the final answer.
private struct InlinePreviousMessagesLink: View {
    let count: Int
    let expanded: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(L10n.previousMessages(count))
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: hovered ? 0.78 : 0.55))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(white: hovered ? 0.78 : 0.55))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .animation(.easeOut(duration: 0.16), value: expanded)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) { hovered = h }
        }
        .accessibilityLabel(L10n.previousMessages(count))
    }
}

// MARK: - Trailing "Website" preview card

/// Compact link card shown under the last assistant answer when the body
/// embeds a URL. Renders the "Memory · Sitio web · Abrir" affordance:
/// favicon-style globe pill, resolved `<title>` (or host while the fetch
/// is in flight), subtitle "Website", and an "Open" button that hands
/// off to the right-sidebar browser.
private struct LinkPreviewCard: View {
    let url: URL
    @EnvironmentObject var appState: AppState
    @State private var hovered = false
    @State private var openHovered = false

    private var title: String {
        appState.linkMetadata.title(for: url) ?? LinkMetadataStore.fallback(for: url)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(red: 0.20, green: 0.45, blue: 0.92))
                    .frame(width: 38, height: 38)
                Image(systemName: "globe")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(String(localized: "Website", bundle: AppLocale.bundle, locale: AppLocale.current))
                    .font(.system(size: 12.5))
                    .foregroundColor(Color(white: 0.55))
            }
            Spacer(minLength: 8)
            Button {
                appState.openLinkInBrowser(url)
            } label: {
                Text(String(localized: "Open", bundle: AppLocale.bundle, locale: AppLocale.current))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(white: 0.94))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(openHovered ? 0.10 : 0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .onHover { openHovered = $0 }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(hovered ? 0.05 : 0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { appState.openLinkInBrowser(url) }
        .onAppear { appState.linkMetadata.ensureTitle(for: url) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(title), Sitio web"))
        .accessibilityAddTraits(.isLink)
    }
}

// MARK: - Assistant markdown rendering

/// Renders assistant prose with the small subset of markdown Clawix emits:
/// `[label](url)` links (drawn with a leading globe icon when label==url)
/// and inline `` `code` `` chips. Each link is its own hoverable atom
/// inside a flow layout so tap routes to the sidebar browser and a
/// dotted hover underline tells the user it is interactive.
private struct AssistantMarkdownText: View {
    let text: String
    let weight: Font.Weight
    let color: Color
    @EnvironmentObject var appState: AppState

    var body: some View {
        let paragraphs = AssistantMarkdown.parse(text)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                ParagraphFlow(paragraph: paragraph, weight: weight, color: color) { url in
                    appState.openLinkInBrowser(url)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One paragraph laid out as a vertical stack of "lines" (split on `\n`).
/// Each line is a wrapping flow of word / code / link atoms. Splitting by
/// word lets the link atoms participate in line wrapping while letting us
/// attach per-link `.onHover` and `.onTapGesture` modifiers.
private struct ParagraphFlow: View {
    let paragraph: AssistantMarkdown.Paragraph
    let weight: Font.Weight
    let color: Color
    let onLinkTap: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(paragraph.lines.enumerated()), id: \.offset) { _, line in
                FlowLayout(horizontalSpacing: 0, verticalSpacing: 4) {
                    ForEach(Array(line.atoms.enumerated()), id: \.offset) { _, atom in
                        AtomView(
                            atom: atom,
                            weight: weight,
                            color: color,
                            onLinkTap: onLinkTap
                        )
                    }
                }
            }
        }
    }
}

private struct AtomView: View {
    let atom: AssistantMarkdown.Atom
    let weight: Font.Weight
    let color: Color
    let onLinkTap: (URL) -> Void

    var body: some View {
        switch atom {
        case .word(let s):
            Text(s)
                .font(.system(size: 14, weight: weight))
                .foregroundColor(color)
        case .code(let s):
            Text(s)
                .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                .foregroundColor(Color(white: 0.92))
                .padding(.horizontal, 4)
        case .link(let label, let url, let isBareUrl):
            LinkAtom(label: label, url: url, isBareUrl: isBareUrl, weight: weight, onTap: onLinkTap)
        }
    }
}

/// Inline link with hover affordance: cursor flips to a pointing hand and
/// a subtle dotted underline appears so the user can tell it is tappable.
/// Tap routes through `onTap` (wired to `AppState.openLinkInBrowser`) so
/// the URL lands in the right-sidebar browser instead of the system one.
private struct LinkAtom: View {
    let label: String
    let url: URL
    let isBareUrl: Bool
    let weight: Font.Weight
    let onTap: (URL) -> Void

    @State private var hovered = false
    private let linkColor = Color(red: 0.60, green: 0.78, blue: 0.96)

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            if isBareUrl {
                Image(systemName: "globe")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(linkColor.opacity(hovered ? 0.78 : 1))
            }
            Text(label)
                .font(.system(size: 14, weight: weight))
                .foregroundColor(linkColor.opacity(hovered ? 0.78 : 1))
                .underline(hovered, pattern: .dot, color: linkColor.opacity(0.85))
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            hovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture { onTap(url) }
        .accessibilityAddTraits(.isLink)
    }
}

/// Wrapping flow layout used for paragraph lines: places children left to
/// right, breaking to a new line whenever the next subview would overflow
/// the proposed width. Handles word-by-word atoms so link/code chips can
/// sit inline with surrounding prose without breaking text wrap.
struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 0
    var verticalSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if lineWidth + size.width > maxWidth, lineWidth > 0 {
                totalWidth = max(totalWidth, lineWidth)
                totalHeight += lineHeight + verticalSpacing
                lineWidth = 0
                lineHeight = 0
            }
            lineWidth += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }
        totalWidth = max(totalWidth, lineWidth)
        totalHeight += lineHeight
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x - bounds.minX + size.width > maxWidth, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + verticalSpacing
                lineHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

enum AssistantMarkdown {
    struct Paragraph {
        let lines: [Line]
    }

    struct Line {
        let atoms: [Atom]
    }

    enum Atom {
        case word(String)        // a token + trailing whitespace
        case code(String)
        case link(label: String, url: URL, isBareUrl: Bool)
    }

    static func parse(_ text: String) -> [Paragraph] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        return normalized
            .components(separatedBy: "\n\n")
            .map { block -> Paragraph in
                let lines = block
                    .components(separatedBy: "\n")
                    .map { Line(atoms: parseAtoms(in: $0)) }
                    .filter { !$0.atoms.isEmpty }
                return Paragraph(lines: lines)
            }
            .filter { !$0.lines.isEmpty }
    }

    /// Tokenise one line into atoms. Plain prose is split into word atoms
    /// (each carries its trailing space) so the FlowLayout can wrap mid
    /// paragraph; links and code chips become their own atoms so they keep
    /// per-element hover / tap handling.
    private static func parseAtoms(in input: String) -> [Atom] {
        var atoms: [Atom] = []
        var pending = ""
        var i = input.startIndex

        func flushWords() {
            guard !pending.isEmpty else { return }
            atoms.append(contentsOf: splitIntoWords(pending))
            pending = ""
        }

        while i < input.endIndex {
            let ch = input[i]
            if ch == "[" {
                if let close = input[i...].firstIndex(of: "]"),
                   input.index(after: close) < input.endIndex,
                   input[input.index(after: close)] == "(" {
                    let labelStart = input.index(after: i)
                    let urlOpen = input.index(after: close)
                    if let urlClose = input[urlOpen...].firstIndex(of: ")") {
                        let label = String(input[labelStart..<close])
                        let urlStr = String(input[input.index(after: urlOpen)..<urlClose])
                        if let url = URL(string: urlStr) {
                            flushWords()
                            atoms.append(.link(
                                label: label,
                                url: url,
                                isBareUrl: label == urlStr
                            ))
                            i = input.index(after: urlClose)
                            continue
                        }
                    }
                }
            } else if ch == "`" {
                let afterTick = input.index(after: i)
                if afterTick < input.endIndex,
                   let close = input[afterTick...].firstIndex(of: "`") {
                    flushWords()
                    atoms.append(.code(String(input[afterTick..<close])))
                    i = input.index(after: close)
                    continue
                }
            }
            pending.append(ch)
            i = input.index(after: i)
        }
        flushWords()
        return atoms
    }

    /// Split prose into word atoms, attaching trailing whitespace to each
    /// word so FlowLayout has a natural break point between them.
    private static func splitIntoWords(_ s: String) -> [Atom] {
        var out: [Atom] = []
        var current = ""
        var inWhitespaceTail = false
        for ch in s {
            if ch == " " || ch == "\t" {
                current.append(ch)
                inWhitespaceTail = true
            } else {
                if inWhitespaceTail, !current.isEmpty {
                    out.append(.word(current))
                    current = ""
                    inWhitespaceTail = false
                }
                current.append(ch)
            }
        }
        if !current.isEmpty {
            out.append(.word(current))
        }
        return out
    }

    /// Walk a paragraph's atoms and return the URLs of every `.link` token.
    /// Used by callers that want to surface the assistant's links outside
    /// the prose flow (e.g. the trailing "Website" card).
    static func extractLinkURLs(in text: String) -> [URL] {
        var urls: [URL] = []
        for paragraph in parse(text) {
            for line in paragraph.lines {
                for atom in line.atoms {
                    if case .link(_, let url, _) = atom {
                        urls.append(url)
                    }
                }
            }
        }
        return urls
    }
}
