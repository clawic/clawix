import AppKit
import SwiftUI
import ClawixCore

enum TimestampFormatters {
    private static let lock = NSLock()
    private static var lastLocaleId: String = ""
    private static let time = DateFormatter()
    private static let weekday = DateFormatter()
    private static let dateSameYear = DateFormatter()
    private static let dateOtherYear = DateFormatter()

    static func resolved() -> (
        time: DateFormatter,
        weekday: DateFormatter,
        dateSameYear: DateFormatter,
        dateOtherYear: DateFormatter
    ) {
        lock.lock(); defer { lock.unlock() }
        let locale = AppLocale.current
        let id = locale.identifier
        if id != lastLocaleId {
            time.locale = locale
            time.dateStyle = .none
            time.timeStyle = .short

            weekday.locale = locale
            weekday.dateFormat = "EEEE"

            dateSameYear.locale = locale
            dateSameYear.setLocalizedDateFormatFromTemplate("MMMdjmm")

            dateOtherYear.locale = locale
            dateOtherYear.setLocalizedDateFormatFromTemplate("MMMdyjmm")

            lastLocaleId = id
        }
        return (time, weekday, dateSameYear, dateOtherYear)
    }
}

struct ChatMarkdownPrewarmKey: Hashable {
    let chatId: UUID
    let visibleMessageCount: Int
    let firstMessageId: UUID?
    let lastMessageId: UUID?
    let lastTimelineCount: Int
}

enum ChatMarkdownPrewarmer {
    static func prewarm(messages: [ChatMessage], timelineEntryLimit: Int) async {
        let texts = markdownTexts(messages: messages, timelineEntryLimit: timelineEntryLimit)
        guard !texts.isEmpty else { return }
        PerfSignpost.renderMarkdown.event("prewarm.texts", texts.count)
        await Task.detached(priority: .utility) {
            for text in texts {
                MarkdownParseCache.prewarm(text)
            }
        }.value
    }

    private static func markdownTexts(messages: [ChatMessage], timelineEntryLimit: Int) -> [String] {
        var result: [String] = []
        result.reserveCapacity(messages.count * 2)
        for message in messages where message.role == .assistant {
            if !message.content.isEmpty {
                result.append(message.content)
            }
            let timeline = message.timeline.suffix(timelineEntryLimit)
            for entry in timeline {
                switch entry {
                case .reasoning(_, let text), .message(_, let text):
                    if !text.isEmpty {
                        result.append(text)
                    }
                case .tools:
                    break
                }
            }
        }
        return result
    }
}

struct MessageRow: View, Equatable {
    let chatId: UUID
    let message: ChatMessage
    var isLastUserMessage: Bool = false
    var isLastAssistantMessage: Bool = false
    var responseStreaming: Bool = false
    /// Empty unless the in-page find bar is open. Threaded down from
    /// `ChatView` instead of read off `AppState` here so an unrelated
    /// `@Published` change on `AppState` (any streaming delta, hover
    /// state on the sidebar, etc.) does not invalidate every visible
    /// row's body. Combined with `.equatable()` on the row's call site,
    /// a delta on a single message only re-renders that one row.
    var findQuery: String = ""
    var onTimelineExpanded: ((UUID) -> Void)? = nil
    var onUserBubbleExpanded: ((UUID) -> Void)? = nil
    /// Closures bridge back to the `AppState` mutation surface from the
    /// row's parent (`ChatView`). They are intentionally NOT compared by
    /// `Equatable` so swapping them across rebuilds doesn't force a
    /// re-render of the bubble.
    var onEditUserMessage: (String) -> Void = { _ in }
    var onForkConversation: () -> Void = {}
    var onOpenImage: (URL) -> Void = { _ in }
    var onPushToPublishing: (String) -> Void = { _ in }
    var publishingReady: Bool = false
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
    @State private var visibleTimelineEntryLimit = Self.initialTimelineEntryLimit
    @State private var lastTimelineRevealAt: Date = .distantPast

    private var isUser: Bool { message.role == .user }
    private var exposeMessageAccessibility: Bool { NSWorkspace.shared.isVoiceOverEnabled }
    fileprivate static let initialTimelineEntryLimit = 8
    private static let timelineEntryPageSize = 8
    private static let timelineRevealThrottle: TimeInterval = 0.15

    static func == (lhs: MessageRow, rhs: MessageRow) -> Bool {
        lhs.chatId == rhs.chatId
            && lhs.message == rhs.message
            && lhs.isLastUserMessage == rhs.isLastUserMessage
            && lhs.isLastAssistantMessage == rhs.isLastAssistantMessage
            && lhs.responseStreaming == rhs.responseStreaming
            && lhs.findQuery == rhs.findQuery
            && lhs.publishingReady == rhs.publishingReady
    }

    var body: some View {
        let _ = PerfSignpost.uiChat.event("row.body")
        VStack(alignment: isUser ? .trailing : .leading, spacing: 24) {
            if isUser {
                if isEditing {
                    UserMessageEditor(
                        text: $editDraft,
                        onCancel: { isEditing = false },
                        onSubmit: {
                            let trimmed = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            onEditUserMessage(trimmed)
                            isEditing = false
                        }
                    )
                    .frame(maxWidth: CGFloat.infinity)
                } else {
                    let parsed = UserBubbleContent.parse(message.content, attachments: message.attachments)
                    if !parsed.images.isEmpty || !parsed.files.isEmpty {
                        UserMentionPreviews(parsed: parsed, onOpenImage: onOpenImage)
                    }
                    if let audioRef = message.audioRef {
                        UserAudioBubble(audioRef: audioRef)
                    }
                    if !parsed.text.isEmpty {
                        let paragraphs = parsed.text
                            .replacingOccurrences(of: "\r\n", with: "\n")
                            .components(separatedBy: "\n\n")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        UserMessageTextBubble(
                            paragraphs: paragraphs,
                            findQuery: findQuery,
                            exposeAccessibility: exposeMessageAccessibility,
                            accessibilityText: AccessibilityText.clipped(parsed.text),
                            onExpand: { onUserBubbleExpanded?(message.id) }
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
                    let timelineEntries = visibleTimelineEntries(isStreaming: isStreaming)
                    let _ = PerfSignpost.uiChat.event("timeline.entries.visible", timelineEntries.count)
                    if !isStreaming, hiddenTimelineEntryCount > 0 {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                revealMoreTimelineEntriesIfNeeded()
                            }
                    }
                    ForEach(timelineEntries) { entry in
                        timelineEntry(entry)
                            .transaction { transaction in
                                transaction.animation = nil
                            }
                    }
                }

                // After the turn ends and the chevron is collapsed, the
                // timeline is hidden and the bubble shows only the
                // canonical assistant body. The timeline already contains
                // every `.message` entry that streamed in, so don't
                // render `content` a second time while the timeline is on
                // screen — that would duplicate the prose.
                if !showTimeline, !message.content.isEmpty {
                    let segments = PlanSegmenter.segments(from: message.content)
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
                                streamingFinished: message.streamingFinished,
                                findQuery: findQuery
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityHidden(!exposeMessageAccessibility)
                        case .plan(let body, let completed):
                            PlanCardView(content: body, completed: completed)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityHidden(!exposeMessageAccessibility)
                        }
                    }
                }

                // One pill per file the agent edited during this turn,
                // mirroring the Codex Desktop "README.md / Document · MD"
                // attachment cards. Order matches first-touch, deduped.
                // Only surfaces once the turn fully ends so the cards
                // don't pop in beside the still-streaming reasoning.
                let changedFiles = ChangedFilePathCache.shared.paths(for: message)
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

                // The runtime shows a "Website · Open" preview card under the
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
        .onChange(of: timelineExpanded) { _, expanded in
            visibleTimelineEntryLimit = Self.initialTimelineEntryLimit
            lastTimelineRevealAt = .distantPast
            if expanded {
                prewarmVisibleTimelineMarkdown()
            }
        }
        .onChange(of: message.id) { _, _ in
            visibleTimelineEntryLimit = Self.initialTimelineEntryLimit
            lastTimelineRevealAt = .distantPast
        }
    }

    private var hiddenTimelineEntryCount: Int {
        max(0, message.timeline.count - visibleTimelineEntryLimit)
    }

    private func visibleTimelineEntries(isStreaming: Bool) -> [AssistantTimelineEntry] {
        if isStreaming || visibleTimelineEntryLimit >= message.timeline.count {
            return message.timeline
        }
        return Array(message.timeline.suffix(visibleTimelineEntryLimit))
    }

    private func revealMoreTimelineEntriesIfNeeded() {
        guard timelineExpanded, hiddenTimelineEntryCount > 0 else { return }
        let now = Date()
        guard now.timeIntervalSince(lastTimelineRevealAt) >= Self.timelineRevealThrottle else {
            return
        }
        lastTimelineRevealAt = now
        let nextLimit = min(message.timeline.count, visibleTimelineEntryLimit + Self.timelineEntryPageSize)
        guard nextLimit != visibleTimelineEntryLimit else { return }
        PerfSignpost.uiChat.event("timeline.entries.revealed", nextLimit)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            visibleTimelineEntryLimit = nextLimit
        }
        prewarmVisibleTimelineMarkdown(limit: nextLimit)
    }

    private func prewarmVisibleTimelineMarkdown(limit: Int? = nil) {
        let count = min(message.timeline.count, limit ?? visibleTimelineEntryLimit)
        let entries = count >= message.timeline.count
            ? message.timeline
            : Array(message.timeline.suffix(count))
        let texts = Self.markdownTexts(in: entries)
        guard !texts.isEmpty else { return }
        Task.detached(priority: .utility) {
            for text in texts {
                MarkdownParseCache.prewarm(text)
            }
        }
    }

    private static func markdownTexts(in entries: [AssistantTimelineEntry]) -> [String] {
        entries.compactMap { entry in
            switch entry {
            case .reasoning(_, let text), .message(_, let text):
                return text.isEmpty ? nil : text
            case .tools:
                return nil
            }
        }
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
                streamingFinished: message.streamingFinished,
                findQuery: findQuery
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(!exposeMessageAccessibility)
        case .message(let entryId, let text):
            messageEntryBody(entryId: entryId, text: text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(!exposeMessageAccessibility)
        case .tools(_, let items):
            ToolGroupView(items: items)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(!exposeMessageAccessibility)
        }
    }

    /// Render a `.message` timeline entry. Mirrors how the bubble used
    /// to render `message.content` (PlanSegmenter + AssistantMarkdownText)
    /// so a preamble that flowed through `nAgentMsgDelta` reads exactly
    /// the same as the final answer once collapsed. The streaming fade
    /// only attaches when this is the single, trailing `.message` entry
    /// AND the body is a contiguous text segment, because
    /// `streamCheckpoints` are character offsets over the full
    /// concatenated message body.
    @ViewBuilder
    private func messageEntryBody(entryId: UUID, text: String) -> some View {
        let segments = PlanSegmenter.segments(from: text)
        let isTrailingMessage: Bool = {
            guard case .message(let lastId, _) = message.timeline.last else { return false }
            return lastId == entryId
        }()
        let messageEntryCount = message.timeline.reduce(0) { acc, e in
            if case .message = e { return acc + 1 } else { return acc }
        }
        let onlyTextSegment: Bool = {
            guard segments.count == 1, case .text = segments[0] else { return false }
            return true
        }()
        let useCheckpoints =
            isTrailingMessage && messageEntryCount == 1 && onlyTextSegment
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let body):
                    AssistantMarkdownText(
                        text: body,
                        weight: message.isError ? .regular : .light,
                        color: message.isError
                            ? Color(red: 0.95, green: 0.45, blue: 0.45)
                            : Palette.textPrimary,
                        checkpoints: useCheckpoints ? message.streamCheckpoints : [],
                        streamingFinished: message.streamingFinished,
                        findQuery: findQuery
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                case .plan(let body, let completed):
                    PlanCardView(content: body, completed: completed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        let copyLabel = justCopied
            ? String(localized: "Copied", bundle: AppLocale.bundle, locale: AppLocale.current)
            : String(localized: "Copy", bundle: AppLocale.bundle, locale: AppLocale.current)
        let editLabel = String(localized: "Edit", bundle: AppLocale.bundle, locale: AppLocale.current)
        let forkLabel = String(localized: "Fork conversation", bundle: AppLocale.bundle, locale: AppLocale.current)

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
                                  label: forkLabel) {
                    onForkConversation()
                }
                if publishingReady {
                    MessageActionIcon(
                        kind: .system("megaphone"),
                        label: String(localized: "Push to publishing",
                                      bundle: AppLocale.bundle,
                                      locale: AppLocale.current)
                    ) {
                        onPushToPublishing(message.content)
                    }
                }
                timestampLabel
                    .opacity(isLastAssistantMessage ? (rowHovered ? 1 : 0) : 1)
                    .animation(.easeOut(duration: 0.15), value: rowHovered)
            }
        }
        .padding(.leading, isUser ? 0 : 2)
        .padding(.trailing, isUser ? 6 : 0)
        .padding(.top, isUser ? -22 : -18)
    }

    private var timestampLabel: some View {
        Text(verbatim: formattedTimestamp)
            .font(BodyFont.system(size: 11, wght: 500))
            .foregroundColor(Color(white: 0.45))
            .padding(.horizontal, 4)
    }

    private var formattedTimestamp: String {
        let cal = Calendar.current
        let fmts = TimestampFormatters.resolved()
        if cal.isDateInToday(message.timestamp) {
            return fmts.time.string(from: message.timestamp)
        }
        let startOfMsg = cal.startOfDay(for: message.timestamp)
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        let dayDiff = cal.dateComponents([.day], from: startOfMsg, to: startOfToday).day ?? 0
        if dayDiff >= 1 && dayDiff <= 6 {
            return "\(fmts.weekday.string(from: message.timestamp)), \(fmts.time.string(from: message.timestamp))"
        }
        let sameYear = cal.component(.year, from: message.timestamp) == cal.component(.year, from: now)
        let formatter = sameYear ? fmts.dateSameYear : fmts.dateOtherYear
        return formatter.string(from: message.timestamp)
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

struct MessageActionIcon: View {
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
        .accessibilityLabel(Text(verbatim: label))
        .hoverHint(label)
    }

    @ViewBuilder
    private var iconView: some View {
        switch kind {
        case .copy(let showCheck):
            if showCheck {
                CheckIcon(size: 14.3)
                    .foregroundColor(Color(white: hovered ? 0.94 : 0.78))
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            } else {
                CopyIconViewSquircle(color: Color(white: hovered ? 0.88 : 0.55), lineWidth: 0.85)
                    .frame(width: 14.3, height: 14.3)
                    .transition(.opacity)
            }
        case .pencil:
            PencilIconView(color: Color(white: hovered ? 0.88 : 0.55), lineWidth: 0.85)
                .frame(width: 16.5, height: 16.5)
        case .branchArrows:
            BranchArrowsIconView(color: Color(white: hovered ? 0.88 : 0.55), lineWidth: 0.85)
                .frame(width: 14.3, height: 14.3)
        case .system(let name):
            IconImage(name, size: 14.3)
                .foregroundColor(Color(white: hovered ? 0.82 : 0.45))
        }
    }
}

final class ChangedFilePathCache {
    static let shared = ChangedFilePathCache()

    private var values: [Key: [String]] = [:]
    private var order: [Key] = []
    private let limit = 256

    private init() {}

    func paths(for message: ChatMessage) -> [String] {
        let key = Key(message: message)
        if let cached = values[key] {
            return cached
        }

        var seen: Set<String> = []
        var result: [String] = []
        for entry in message.timeline {
            guard case .tools(_, let items) = entry else { continue }
            for item in items {
                guard case .fileChange(let paths) = item.kind else { continue }
                for path in paths where seen.insert(path).inserted {
                    result.append(path)
                }
            }
        }

        values[key] = result
        order.append(key)
        if order.count > limit {
            let overflow = order.count - limit
            for oldKey in order.prefix(overflow) {
                values.removeValue(forKey: oldKey)
            }
            order.removeFirst(overflow)
        }
        return result
    }

    private struct Key: Hashable {
        let messageId: UUID
        let timelineCount: Int
        let lastTimelineId: UUID?
        let workItemCount: Int

        init(message: ChatMessage) {
            messageId = message.id
            timelineCount = message.timeline.count
            lastTimelineId = message.timeline.last?.id
            workItemCount = message.workSummary?.items.count ?? 0
        }
    }
}
