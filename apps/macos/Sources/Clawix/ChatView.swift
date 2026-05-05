import SwiftUI

private let chatRailMaxWidth: CGFloat = 720

struct ChatView: View {
    let chatId: UUID
    @EnvironmentObject var appState: AppState

    @State private var workMenuOpen = false
    @State private var branchMenuOpen = false
    @State private var branchCreateOpen = false
    @State private var branchSearch = ""

    private var chat: Chat? {
        appState.chats.first { $0.id == chatId }
    }

    var body: some View {
        RenderProbe.tick("ChatView")
        return Group {
            if let chat {
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 44) {
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
                                ForEach(chat.messages) { msg in
                                    MessageRow(
                                        chatId: chat.id,
                                        message: msg,
                                        isLastUserMessage: msg.id == lastUserMessageId,
                                        isLastAssistantMessage: msg.id == lastAssistantMessageId,
                                        responseStreaming: responseStreaming,
                                        onTimelineExpanded: { expandedId in
                                            // Pin the bottom of the expanded
                                            // bubble so the inserted prelude
                                            // grows upward off-screen instead
                                            // of pushing the closing answer
                                            // and everything below it down.
                                            DispatchQueue.main.async {
                                                proxy.scrollTo(expandedId, anchor: .bottom)
                                            }
                                        }
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
                            .background(ThinScrollerInstaller().allowsHitTesting(false))
                        }
                        .onChange(of: chat.messages.count) { _, _ in
                            if let last = chat.messages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                        .onAppear { appState.ensureSelectedChat() }
                        .onChange(of: chatId) { _, _ in
                            appState.ensureSelectedChat()
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
    var onTimelineExpanded: ((UUID) -> Void)? = nil
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
        VStack(alignment: isUser ? .trailing : .leading, spacing: 24) {
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
                        let paragraphs = parsed.text
                            .replacingOccurrences(of: "\r\n", with: "\n")
                            .components(separatedBy: "\n\n")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, p in
                                Text(p)
                                    .font(.system(size: 13.5))
                                    .foregroundColor(Palette.textPrimary)
                                    .lineSpacing(5)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                    }
                }
            } else {
                // One streaming-state header sits at the top of the
                // bubble and walks through three visual states:
                //   1. "Working" while the very first reasoning chunk is
                //      being typed (no seconds, no chevron).
                //   2. "Working for Xs" once a second action has begun
                //      (live ticking seconds, no chevron).
                //   3. "Worked for Xs ›" once the turn fully completes
                //      (chevron, expandable). The reasoning + tool
                //      entries that accumulated while streaming collapse
                //      behind the chevron so the user focuses on the
                //      final answer.
                //
                // Crucial nuance: the collapse only happens when the
                // turn ends, not when the final reply starts arriving.
                // While streaming, every reasoning chunk and tool call
                // stays visible and stacks below the header,
                // accumulating like the expanded "N previous messages"
                // disclosure used to show. The final answer streams in
                // alongside them and only becomes the bubble's only
                // visible content once streaming finishes.
                let isStreaming = !message.streamingFinished && !message.isError
                if let summary = message.workSummary, !message.isError {
                    if isStreaming {
                        if !message.timeline.isEmpty {
                            LiveWorkingHeader(
                                summary: summary,
                                timelineCount: message.timeline.count
                            )
                        }
                    } else if !message.timeline.isEmpty || !summary.items.isEmpty {
                        WorkSummaryHeader(
                            summary: summary,
                            expanded: $timelineExpanded
                        ) {
                            onTimelineExpanded?(message.id)
                        }
                    }
                }

                // Show every timeline entry inline while the turn is
                // still running so the user watches the agent's work
                // accumulate. After the turn ends, the entries collapse
                // behind the chevron and only resurface when the user
                // expands the disclosure.
                let showTimeline = isStreaming || timelineExpanded
                if showTimeline {
                    ForEach(message.timeline) { entry in
                        timelineEntry(entry)
                    }
                }

                if !message.content.isEmpty {
                    let segments = PlanSegmenter.segments(from: message.content)
                    // The streaming fade is keyed by character offsets
                    // into `message.content`, so it only lines up cleanly
                    // when the body is a single, contiguous text segment.
                    // The instant a Plan card splits the body we skip the
                    // fade rather than render misaligned ramps.
                    let onlyTextSegment: Bool = {
                        guard segments.count == 1, case .text = segments[0] else { return false }
                        return true
                    }()
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        switch segment {
                        case .text(let body):
                            AssistantMarkdownText(
                                text: body,
                                weight: message.isError ? .regular : .light,
                                color: message.isError
                                    ? Color(red: 0.95, green: 0.45, blue: 0.45)
                                    : Palette.textPrimary,
                                checkpoints: onlyTextSegment ? message.streamCheckpoints : [],
                                streamingFinished: message.streamingFinished
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
                // Only surfaces once the turn fully ends so the cards
                // don't pop in beside the still-streaming reasoning.
                let changedFiles = Self.changedFilePaths(in: message.timeline)
                if !changedFiles.isEmpty, message.streamingFinished {
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
                   let lastURL = AssistantMarkdown
                       .extractLinkURLs(in: message.content)
                       .last(where: { !$0.isFileURL }) {
                    LinkPreviewCard(url: lastURL)
                        .padding(.top, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !message.streamingFinished && !message.isError {
                    ThinkingShimmer(text: String(localized: "Thinking", bundle: AppLocale.bundle, locale: AppLocale.current))
                        .padding(.top, 2)
                }
            }

            // Action bar (copy / branch / edit / timestamp) only shows
            // once the assistant turn finishes. While streaming, the
            // bubble's chrome stays clean: no actions, no timestamp.
            let actionBarAvailable = isUser || message.streamingFinished
            if !isEditing, actionBarAvailable {
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

    @ViewBuilder
    private func timelineEntry(_ entry: AssistantTimelineEntry) -> some View {
        switch entry {
        case .reasoning(let entryId, let text):
            AssistantMarkdownText(
                text: text,
                weight: .light,
                color: Palette.textPrimary,
                checkpoints: message.reasoningCheckpoints[entryId] ?? [],
                streamingFinished: message.streamingFinished
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
        .padding(.leading, isUser ? 0 : 6)
        .padding(.trailing, isUser ? 6 : 0)
        .padding(.top, -18)
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

struct CopyIconViewSquircle: View {
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

/// Atom + the offset of its first character inside the original streamed
/// source. The renderer hands that offset to `StreamingFade` so each
/// character ramps from 0→1 opacity in step with the delta that brought
/// it in.
private struct AnnotatedAtom {
    let atom: AssistantMarkdown.Atom
    let offset: Int
}

private struct AnnotatedLine {
    let atoms: [AnnotatedAtom]
}

private struct AnnotatedParagraph {
    let lines: [AnnotatedLine]
}

private enum AnnotatedBlock {
    case paragraph(AnnotatedParagraph)
    case heading(level: Int, line: AnnotatedLine)
    case bulletList(items: [AnnotatedParagraph])
    case numberedList(items: [AnnotatedParagraph])
    case codeBlock(language: String, code: String)
    case table(headers: [AnnotatedLine], rows: [[AnnotatedLine]])
}

private func annotateBlocks(_ blocks: [AssistantMarkdown.Block], source: String) -> [AnnotatedBlock] {
    var resolver = AtomOffsetResolver(source: source)
    return blocks.map { annotate($0, with: &resolver) }
}

private func annotate(_ block: AssistantMarkdown.Block, with resolver: inout AtomOffsetResolver) -> AnnotatedBlock {
    switch block {
    case .paragraph(let p):
        return .paragraph(annotate(p, with: &resolver))
    case .heading(let level, let line):
        return .heading(level: level, line: annotate(line, with: &resolver))
    case .bulletList(let items):
        return .bulletList(items: items.map { annotate($0, with: &resolver) })
    case .numberedList(let items):
        return .numberedList(items: items.map { annotate($0, with: &resolver) })
    case .codeBlock(let language, let code):
        // The fenced body is rendered as a static block; we still walk the
        // resolver past it so subsequent atoms keep their offsets aligned.
        _ = resolver.locate(code)
        return .codeBlock(language: language, code: code)
    case .table(let headers, let rows):
        let hs = headers.map { annotate($0, with: &resolver) }
        let rs = rows.map { row in row.map { annotate($0, with: &resolver) } }
        return .table(headers: hs, rows: rs)
    }
}

private func annotate(_ paragraph: AssistantMarkdown.Paragraph, with resolver: inout AtomOffsetResolver) -> AnnotatedParagraph {
    AnnotatedParagraph(lines: paragraph.lines.map { annotate($0, with: &resolver) })
}

private func annotate(_ line: AssistantMarkdown.Line, with resolver: inout AtomOffsetResolver) -> AnnotatedLine {
    var atoms: [AnnotatedAtom] = []
    atoms.reserveCapacity(line.atoms.count)
    for atom in line.atoms {
        let needle: String
        switch atom {
        case .word(let s):              needle = s
        case .bold(let s):              needle = s
        case .italic(let s):            needle = s
        case .code(let s):              needle = s
        case .link(let label, _, _):    needle = label
        }
        let offset = resolver.locate(needle)
        atoms.append(AnnotatedAtom(atom: atom, offset: offset))
    }
    return AnnotatedLine(atoms: atoms)
}

/// Renders assistant prose with the markdown subset Clawix emits:
/// paragraphs, ATX headings, bullet/numbered lists, GitHub-style tables,
/// fenced code blocks, plus inline `**bold**`, `*italic*`, `` `code` ``,
/// and `[label](url)` links. Each link is its own hoverable atom inside
/// a flow layout so tap routes to the sidebar browser and a dotted hover
/// underline tells the user it is interactive.
///
/// While the body is still streaming (or just finished and the trailing
/// fade hasn't completed yet) the renderer wraps in `TimelineView` and
/// applies a per-character opacity ramp from `StreamingFade`, so newly
/// arrived characters glide in from invisible while older ones stay
/// settled at full opacity.
private struct AssistantMarkdownText: View {
    let text: String
    let weight: Font.Weight
    let color: Color
    var checkpoints: [StreamCheckpoint] = []
    var streamingFinished: Bool = true
    @EnvironmentObject var appState: AppState
    /// Bumped when the trailing fade window closes, so the body
    /// re-evaluates and tears down the `TimelineView` once nothing is
    /// animating any more.
    @State private var animationTick: Int = 0

    var body: some View {
        let blocks = annotateBlocks(AssistantMarkdown.parseBlocks(text), source: text)
        let now = Date()
        let animating = StreamingFade.isAnimating(
            checkpoints: checkpoints,
            finished: streamingFinished,
            now: now
        )

        Group {
            if animating {
                TimelineView(.animation) { ctx in
                    blocksView(blocks, now: ctx.date)
                }
            } else {
                blocksView(blocks, now: now)
            }
        }
        .task(id: TickKey(timestamp: checkpoints.last?.addedAt, finished: streamingFinished)) {
            await scheduleSettle()
        }
    }

    private func scheduleSettle() async {
        guard let last = checkpoints.last else { return }
        let remaining = StreamingFade.duration - Date().timeIntervalSince(last.addedAt)
        if remaining > 0 {
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }
        animationTick &+= 1
    }

    private struct TickKey: Hashable {
        let timestamp: Date?
        let finished: Bool
    }

    @ViewBuilder
    private func blocksView(_ blocks: [AnnotatedBlock], now: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block, now: now)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: AnnotatedBlock, now: Date) -> some View {
        switch block {
        case .paragraph(let p):
            ParagraphFlow(paragraph: p, weight: weight, color: color, checkpoints: checkpoints, now: now) { url in
                appState.openLinkInBrowser(url)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .heading(let level, let line):
            ParagraphFlow(
                paragraph: AnnotatedParagraph(lines: [line]),
                weight: .semibold,
                color: color,
                fontSize: headingFontSize(level),
                checkpoints: checkpoints,
                now: now
            ) { url in
                appState.openLinkInBrowser(url)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Circle()
                            .fill(color)
                            .frame(width: 5, height: 5)
                            .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4 }
                            .frame(width: 10, alignment: .leading)
                        ParagraphFlow(paragraph: item, weight: weight, color: color, checkpoints: checkpoints, now: now) { url in
                            appState.openLinkInBrowser(url)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

        case .numberedList(let items):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(idx + 1).")
                            .font(.system(size: 13.5, weight: weight))
                            .foregroundColor(color)
                            .frame(width: 20, alignment: .leading)
                        ParagraphFlow(paragraph: item, weight: weight, color: color, checkpoints: checkpoints, now: now) { url in
                            appState.openLinkInBrowser(url)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

        case .table(let headers, let rows):
            AssistantTableView(
                headers: headers,
                rows: rows,
                weight: weight,
                color: color,
                checkpoints: checkpoints,
                now: now
            ) { url in
                appState.openLinkInBrowser(url)
            }

        case .codeBlock(let language, let code):
            AssistantCodeBlockView(language: language, code: code)
        }
    }

    private func headingFontSize(_ level: Int) -> CGFloat {
        switch level {
        case 1:  return 20
        case 2:  return 17
        case 3:  return 15
        default: return 14
        }
    }
}

/// Table block rendered with the same look as the reference UI: column
/// headers in semibold weight, hairline horizontal divider after every
/// row, leading-aligned cells with generous vertical padding and no
/// vertical separators. Columns size by intrinsic content via `Grid`.
private struct AssistantTableView: View {
    let headers: [AnnotatedLine]
    let rows: [[AnnotatedLine]]
    let weight: Font.Weight
    let color: Color
    var checkpoints: [StreamCheckpoint] = []
    var now: Date = .distantPast
    let onLinkTap: (URL) -> Void

    private let divider = Color.white.opacity(0.14)
    private let dividerThickness: CGFloat = 0.75
    private let cellVPad: CGFloat = 7
    private let cellHPad: CGFloat = 32

    var body: some View {
        let columnCount = max(headers.count, rows.map { $0.count }.max() ?? 0)
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { idx, cell in
                    cellView(cell, weight: .semibold)
                        .padding(.leading, idx == 0 ? 0 : cellHPad)
                        .gridColumnAlignment(.leading)
                }
            }
            .padding(.vertical, cellVPad)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Rectangle()
                    .fill(divider)
                    .frame(height: dividerThickness)
                    .gridCellColumns(columnCount)
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { idx in
                        cellView(idx < row.count ? row[idx] : AnnotatedLine(atoms: []), weight: weight)
                            .padding(.leading, idx == 0 ? 0 : cellHPad)
                            .gridColumnAlignment(.leading)
                    }
                }
                .padding(.vertical, cellVPad)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func cellView(_ line: AnnotatedLine, weight: Font.Weight) -> some View {
        ParagraphFlow(
            paragraph: AnnotatedParagraph(lines: [line]),
            weight: weight,
            color: color,
            checkpoints: checkpoints,
            now: now
        ) { url in
            onLinkTap(url)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Fenced code block rendered with a header row showing the language
/// label and a copy affordance, matching the file-preview code block
/// style so multi-line snippets feel consistent across the app.
private struct AssistantCodeBlockView: View {
    let language: String
    let code: String

    @State private var copied = false
    @State private var hoverCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(language.isEmpty ? "code" : language)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundColor(Color(white: 0.55))
                Spacer(minLength: 8)
                Button(action: copyCode) {
                    Group {
                        if copied {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color(white: hoverCopy ? 0.94 : 0.78))
                        } else {
                            CopyIconViewSquircle(
                                color: Color(white: hoverCopy ? 0.88 : 0.55),
                                lineWidth: 0.85
                            )
                            .frame(width: 14, height: 14)
                        }
                    }
                    .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .onHover { hoverCopy = $0 }
                .accessibilityLabel("Copy code")
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Text(code)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundColor(Palette.textPrimary.opacity(0.94))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .textSelection(.enabled)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func copyCode() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(code, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            copied = false
        }
    }
}

/// One paragraph laid out as a vertical stack of "lines" (split on `\n`).
/// Each line is a wrapping flow of word / code / link atoms. Splitting by
/// word lets the link atoms participate in line wrapping while letting us
/// attach per-link `.onHover` and `.onTapGesture` modifiers.
private struct ParagraphFlow: View {
    let paragraph: AnnotatedParagraph
    let weight: Font.Weight
    let color: Color
    var fontSize: CGFloat = 13.5
    var checkpoints: [StreamCheckpoint] = []
    var now: Date = .distantPast
    let onLinkTap: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(paragraph.lines.enumerated()), id: \.offset) { _, line in
                FlowLayout(horizontalSpacing: 0, verticalSpacing: 6) {
                    ForEach(Array(line.atoms.enumerated()), id: \.offset) { _, annotated in
                        AtomView(
                            atom: annotated.atom,
                            sourceOffset: annotated.offset,
                            weight: weight,
                            color: color,
                            fontSize: fontSize,
                            checkpoints: checkpoints,
                            now: now,
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
    let sourceOffset: Int
    let weight: Font.Weight
    let color: Color
    var fontSize: CGFloat = 13.5
    var checkpoints: [StreamCheckpoint] = []
    var now: Date = .distantPast
    let onLinkTap: (URL) -> Void

    /// All characters in an atom belong to the same word (the parser
    /// splits at whitespace), so the entire atom rides one opacity value
    /// taken from its first character. Keeps per-frame work to a single
    /// multiplier instead of rebuilding an attributed string.
    private var atomOpacity: Double {
        guard !checkpoints.isEmpty else { return 1.0 }
        return StreamingFade.opacity(
            offset: sourceOffset,
            checkpoints: checkpoints,
            now: now
        )
    }

    var body: some View {
        switch atom {
        case .word(let s):
            Text(s)
                .font(.system(size: fontSize, weight: weight))
                .foregroundColor(color)
                .opacity(atomOpacity)
        case .bold(let s):
            Text(s)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundColor(color)
                .opacity(atomOpacity)
        case .italic(let s):
            Text(s)
                .font(.system(size: fontSize, weight: weight).italic())
                .foregroundColor(color)
                .opacity(atomOpacity)
        case .code(let s):
            Text(s)
                .font(.system(size: fontSize - 1.5, weight: .regular, design: .monospaced))
                .foregroundColor(Color(white: 0.94))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.09))
                )
                .padding(.horizontal, 2)
                .offset(y: -3)
                .opacity(atomOpacity)
        case .link(let label, let url, let isBareUrl):
            LinkAtom(label: label, url: url, isBareUrl: isBareUrl, weight: weight, onTap: onLinkTap)
                .opacity(atomOpacity)
        }
    }
}

/// Inline link with hover affordance: cursor flips to a pointing hand and
/// a subtle dotted underline appears so the user can tell it is tappable.
/// Tap routes through `onTap` (wired to `AppState.openLinkInBrowser`,
/// which itself dispatches `file://` URLs to the file viewer) so the
/// destination always lands in the right-sidebar panel instead of the
/// system browser. The leading icon picks `FileChipIcon` for `file://`
/// links and `GlobeIcon` for everything else, so a `[abrir markdown]
/// (/abs/path.md)` chip reads as a document and a `[clawix.com]
/// (https://…)` chip reads as a web link.
private struct LinkAtom: View {
    let label: String
    let url: URL
    let isBareUrl: Bool
    let weight: Font.Weight
    let onTap: (URL) -> Void

    @State private var hovered = false
    private let linkColor = Color(red: 0.42, green: 0.72, blue: 1.0)

    var body: some View {
        Button(action: { onTap(url) }) {
            HStack(alignment: .center, spacing: 4) {
                Group {
                    if url.isFileURL {
                        FileChipIcon(size: 15)
                    } else {
                        GlobeIcon(size: 15)
                    }
                }
                .foregroundColor(linkColor.opacity(hovered ? 0.78 : 1))
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(linkColor.opacity(hovered ? 0.78 : 1))
                    .underline(hovered, pattern: .dot, color: linkColor.opacity(0.85))
            }
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onContinuousHover { phase in
            switch phase {
            case .active:
                hovered = true
                NSCursor.pointingHand.set()
            case .ended:
                hovered = false
            }
        }
        .hoverHint(url.isFileURL ? url.path : url.absoluteString)
        .contextMenu {
            if url.isFileURL {
                Button("Open") { onTap(url) }
                Button("Open with default app") {
                    NSWorkspace.shared.open(url)
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                Divider()
                Button("Copy path") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(url.path, forType: .string)
                }
            } else {
                Button("Open in browser") { onTap(url) }
                Button("Open in external browser") {
                    NSWorkspace.shared.open(url)
                }
                Divider()
                Button("Copy link") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(url.absoluteString, forType: .string)
                }
            }
        }
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
    enum Block {
        case paragraph(Paragraph)
        case heading(level: Int, Line)
        case bulletList(items: [Paragraph])
        case numberedList(items: [Paragraph])
        case codeBlock(language: String, code: String)
        case table(headers: [Line], rows: [[Line]])
    }

    struct Paragraph {
        let lines: [Line]
    }

    struct Line {
        let atoms: [Atom]
    }

    enum Atom {
        case word(String)        // plain token + trailing whitespace
        case bold(String)        // **strong** token + trailing whitespace
        case italic(String)      // *em* / _em_ token + trailing whitespace
        case code(String)
        case link(label: String, url: URL, isBareUrl: Bool)
    }

    /// Block-level parser. Walks the source line by line and groups
    /// contiguous lines into structural blocks. Inline parsing (links,
    /// code, bold, italic) runs once per produced line.
    static func parseBlocks(_ text: String) -> [Block] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var blocks: [Block] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Fenced code block: ``` [language]
            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3))
                    .trimmingCharacters(in: .whitespaces)
                var collected: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    collected.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(language: language,
                                        code: collected.joined(separator: "\n")))
                continue
            }

            // ATX heading
            if let level = headingLevel(for: trimmed) {
                let body = String(trimmed.dropFirst(level))
                    .trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: level,
                                       Line(atoms: parseAtoms(in: body))))
                i += 1
                continue
            }

            // Pipe table: header row + alignment row + 0..N data rows
            if let (headers, rows, consumed) = parseTable(at: i, lines: lines) {
                blocks.append(.table(headers: headers, rows: rows))
                i += consumed
                continue
            }

            // Bullet list (-, *, +)
            if isBulletPrefix(trimmed) {
                var items: [Paragraph] = []
                while i < lines.count {
                    let raw = lines[i]
                    let t = raw.trimmingCharacters(in: .whitespaces)
                    guard isBulletPrefix(t) else { break }
                    let body = String(t.dropFirst(2))
                    items.append(Paragraph(lines: [Line(atoms: parseAtoms(in: body))]))
                    i += 1
                }
                blocks.append(.bulletList(items: items))
                continue
            }

            // Numbered list
            if numberedRange(in: trimmed) != nil {
                var items: [Paragraph] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard let r = numberedRange(in: t) else { break }
                    let body = String(t[r.upperBound...])
                    items.append(Paragraph(lines: [Line(atoms: parseAtoms(in: body))]))
                    i += 1
                }
                blocks.append(.numberedList(items: items))
                continue
            }

            // Paragraph: gather contiguous non-blank lines until the next
            // structural break.
            var paragraphLines: [Line] = [Line(atoms: parseAtoms(in: line))]
            i += 1
            while i < lines.count {
                let next = lines[i]
                let nt = next.trimmingCharacters(in: .whitespaces)
                if nt.isEmpty
                    || headingLevel(for: nt) != nil
                    || nt.hasPrefix("```")
                    || isBulletPrefix(nt)
                    || numberedRange(in: nt) != nil
                    || isTableHeaderCandidate(nt, nextTrimmed: i + 1 < lines.count ? lines[i + 1].trimmingCharacters(in: .whitespaces) : nil) {
                    break
                }
                paragraphLines.append(Line(atoms: parseAtoms(in: next)))
                i += 1
            }
            let nonEmpty = paragraphLines.filter { !$0.atoms.isEmpty }
            if !nonEmpty.isEmpty {
                blocks.append(.paragraph(Paragraph(lines: nonEmpty)))
            }
        }
        return blocks
    }

    // MARK: - Block helpers

    private static func headingLevel(for trimmed: String) -> Int? {
        guard trimmed.hasPrefix("#") else { return nil }
        var hashes = 0
        for ch in trimmed {
            if ch == "#" { hashes += 1 } else { break }
        }
        guard (1...6).contains(hashes),
              trimmed.count > hashes,
              trimmed[trimmed.index(trimmed.startIndex, offsetBy: hashes)] == " "
        else { return nil }
        return hashes
    }

    private static func isBulletPrefix(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ")
    }

    private static func numberedRange(in trimmed: String) -> Range<String.Index>? {
        trimmed.range(of: #"^\d+[.)]\s"#, options: .regularExpression)
    }

    /// Quick check used while gathering paragraph lines so we don't
    /// swallow the start of a table into a preceding paragraph.
    private static func isTableHeaderCandidate(_ trimmed: String, nextTrimmed: String?) -> Bool {
        guard trimmed.hasPrefix("|"), trimmed.contains("|"),
              let next = nextTrimmed else { return false }
        return isTableAlignmentRow(next)
    }

    /// Returns the parsed headers/rows of a pipe table starting at
    /// `start`, or `nil` if the lines at that position are not a table.
    private static func parseTable(at start: Int, lines: [String]) -> (headers: [Line], rows: [[Line]], consumed: Int)? {
        guard start + 1 < lines.count else { return nil }
        let header = lines[start].trimmingCharacters(in: .whitespaces)
        let alignment = lines[start + 1].trimmingCharacters(in: .whitespaces)
        guard header.contains("|"), isTableAlignmentRow(alignment) else { return nil }
        let headerCells = splitTableRow(header)
        guard !headerCells.isEmpty else { return nil }

        var rows: [[Line]] = []
        var i = start + 2
        while i < lines.count {
            let raw = lines[i].trimmingCharacters(in: .whitespaces)
            if raw.isEmpty || !raw.contains("|") { break }
            // Stop if we hit a non-pipe-leading line that is clearly another block.
            let cells = splitTableRow(raw)
            if cells.isEmpty { break }
            rows.append(cells.map { Line(atoms: parseAtoms(in: $0)) })
            i += 1
        }
        let headerLines = headerCells.map { Line(atoms: parseAtoms(in: $0)) }
        return (headerLines, rows, i - start)
    }

    private static func isTableAlignmentRow(_ trimmed: String) -> Bool {
        guard trimmed.contains("|"), trimmed.contains("-") else { return false }
        let cells = splitTableRow(trimmed)
        guard !cells.isEmpty else { return false }
        let pattern = #"^:?-{1,}:?$"#
        for cell in cells {
            let t = cell.trimmingCharacters(in: .whitespaces)
            if t.range(of: pattern, options: .regularExpression) == nil { return false }
        }
        return true
    }

    /// Split a pipe-table row into its cells, stripping the optional
    /// leading and trailing pipes so " | a | b | " yields ["a", "b"].
    private static func splitTableRow(_ trimmed: String) -> [String] {
        var s = trimmed
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    // MARK: - Inline parsing

    /// Tokenise one line into atoms. Plain prose is split into word atoms
    /// (each carries its trailing space) so the FlowLayout can wrap mid
    /// paragraph; links, code chips and bold/italic spans become their
    /// own atoms so they keep per-element styling and hover/tap handling.
    static func parseAtoms(in input: String) -> [Atom] {
        var atoms: [Atom] = []
        var pending = ""
        var i = input.startIndex

        func flushWords() {
            guard !pending.isEmpty else { return }
            atoms.append(contentsOf: splitIntoWords(pending, style: .plain))
            pending = ""
        }

        while i < input.endIndex {
            let ch = input[i]

            // Bold: **text**
            if ch == "*",
               input.index(after: i) < input.endIndex,
               input[input.index(after: i)] == "*" {
                let openEnd = input.index(i, offsetBy: 2)
                if let closeStart = findRange(of: "**", in: input, from: openEnd) {
                    flushWords()
                    let body = String(input[openEnd..<closeStart])
                    atoms.append(contentsOf: splitIntoWords(body, style: .bold))
                    i = input.index(closeStart, offsetBy: 2)
                    continue
                }
            }

            // Italic: *text* (single asterisk, not part of a **)
            if ch == "*" {
                let openEnd = input.index(after: i)
                if openEnd < input.endIndex, input[openEnd] != "*",
                   let closeStart = findSingleAsterisk(in: input, from: openEnd) {
                    flushWords()
                    let body = String(input[openEnd..<closeStart])
                    atoms.append(contentsOf: splitIntoWords(body, style: .italic))
                    i = input.index(after: closeStart)
                    continue
                }
            }

            // Italic: _text_
            if ch == "_" {
                let openEnd = input.index(after: i)
                if openEnd < input.endIndex,
                   let closeStart = input[openEnd...].firstIndex(of: "_") {
                    let body = String(input[openEnd..<closeStart])
                    if !body.contains(" ") || body.trimmingCharacters(in: .whitespaces) == body {
                        flushWords()
                        atoms.append(contentsOf: splitIntoWords(body, style: .italic))
                        i = input.index(after: closeStart)
                        continue
                    }
                }
            }

            // Markdown link: [label](url)
            if ch == "[" {
                if let close = input[i...].firstIndex(of: "]"),
                   input.index(after: close) < input.endIndex,
                   input[input.index(after: close)] == "(" {
                    let labelStart = input.index(after: i)
                    let urlOpen = input.index(after: close)
                    if let urlClose = input[urlOpen...].firstIndex(of: ")") {
                        let label = String(input[labelStart..<close])
                        let urlStr = String(input[input.index(after: urlOpen)..<urlClose])
                        // Codex Desktop writes local files as bare absolute
                        // paths inside markdown links (`[label](/abs/path.md)`).
                        // Promote those to file:// URLs so the renderer can
                        // tell them apart from web links and the tap routes
                        // to the in-app file viewer instead of the browser.
                        let url: URL? = urlStr.hasPrefix("/")
                            ? URL(fileURLWithPath: urlStr)
                            : URL(string: urlStr)
                        if let url {
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
            }

            // Bare URL: http(s)://... — promote to a link atom so the
            // user gets the same chip / hover / right-click treatment as
            // a markdown link, even when the model emitted a raw URL.
            if ch == "h" {
                let suffix = input[i...]
                let scheme: String?
                if suffix.hasPrefix("https://") {
                    scheme = "https://"
                } else if suffix.hasPrefix("http://") {
                    scheme = "http://"
                } else {
                    scheme = nil
                }
                let atBoundary = pending.isEmpty
                    || pending.last.map { $0.isWhitespace || "([{<".contains($0) } ?? true
                if let scheme, atBoundary {
                    var end = input.index(i, offsetBy: scheme.count)
                    while end < input.endIndex {
                        let c = input[end]
                        if c.isWhitespace || c == "\n" { break }
                        end = input.index(after: end)
                    }
                    let trailers: Set<Character> = [
                        ".", ",", ";", ":", "!", "?", "·",
                        ")", "]", "}", ">", "'", "\""
                    ]
                    let bodyStart = input.index(i, offsetBy: scheme.count)
                    while end > bodyStart {
                        let prev = input.index(before: end)
                        if trailers.contains(input[prev]) {
                            end = prev
                        } else {
                            break
                        }
                    }
                    if end > bodyStart {
                        let urlStr = String(input[i..<end])
                        if let url = URL(string: urlStr) {
                            flushWords()
                            atoms.append(.link(
                                label: urlStr,
                                url: url,
                                isBareUrl: true
                            ))
                            i = end
                            continue
                        }
                    }
                }
            }

            // Inline code: `code`
            if ch == "`" {
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

    private enum InlineStyle { case plain, bold, italic }

    /// Find the next occurrence of `needle` starting at `from`, scanning
    /// for either a multi-character delimiter (`**`) or a marker we want
    /// to anchor on a non-asterisk neighbour.
    private static func findRange(of needle: String, in source: String, from: String.Index) -> String.Index? {
        return source.range(of: needle, range: from..<source.endIndex)?.lowerBound
    }

    /// Locate the closing single-asterisk for an italic span, skipping
    /// any `**` pairs that appear inside the candidate region so we don't
    /// confuse italic with a half-open bold.
    private static func findSingleAsterisk(in source: String, from: String.Index) -> String.Index? {
        var i = from
        while i < source.endIndex {
            if source[i] == "*" {
                // Skip if this is actually `**` (start of a new bold).
                let next = source.index(after: i)
                if next < source.endIndex, source[next] == "*" {
                    i = source.index(after: next)
                    continue
                }
                return i
            }
            i = source.index(after: i)
        }
        return nil
    }

    /// Split prose into atoms, attaching trailing whitespace to each
    /// token so FlowLayout has a natural break point between them.
    private static func splitIntoWords(_ s: String, style: InlineStyle) -> [Atom] {
        var out: [Atom] = []
        var current = ""
        var inWhitespaceTail = false

        func emit(_ token: String) {
            switch style {
            case .plain:  out.append(.word(token))
            case .bold:   out.append(.bold(token))
            case .italic: out.append(.italic(token))
            }
        }

        for ch in s {
            if ch == " " || ch == "\t" {
                current.append(ch)
                inWhitespaceTail = true
            } else {
                if inWhitespaceTail, !current.isEmpty {
                    emit(current)
                    current = ""
                    inWhitespaceTail = false
                }
                current.append(ch)
            }
        }
        if !current.isEmpty {
            emit(current)
        }
        return out
    }

    /// Walk every block in the source and return the URLs of every link
    /// atom. Used by callers that want to surface the assistant's links
    /// outside the prose flow (e.g. the trailing "Website" card).
    static func extractLinkURLs(in text: String) -> [URL] {
        var urls: [URL] = []
        for block in parseBlocks(text) {
            visitLines(in: block) { line in
                for atom in line.atoms {
                    if case .link(_, let url, _) = atom {
                        urls.append(url)
                    }
                }
            }
        }
        return urls
    }

    private static func visitLines(in block: Block, body: (Line) -> Void) {
        switch block {
        case .paragraph(let p):
            p.lines.forEach(body)
        case .heading(_, let line):
            body(line)
        case .bulletList(let items), .numberedList(let items):
            for p in items { p.lines.forEach(body) }
        case .table(let headers, let rows):
            headers.forEach(body)
            for row in rows { row.forEach(body) }
        case .codeBlock:
            break
        }
    }
}
