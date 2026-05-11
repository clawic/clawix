import SwiftUI
import AppKit
import ClawixEngine

/// Right-sidebar file preview that mirrors the Codex Desktop reference:
/// a breadcrumb row with `<folder> › <file>` and trailing actions, and a
/// markdown body rendered with `MarkdownDocumentView` for `.md` files
/// (plain monospace for everything else, placeholder for binaries /
/// missing files).
///
/// The breadcrumb's ellipsis exposes a per-file menu:
///   - "Copy path" copies the absolute filesystem path.
///   - "Disable / Enable rich view" (markdown only) flips between the
///     parsed-and-styled view and a raw view with line numbers + light
///     markdown syntax tinting.
///   - "Enable / Disable word wrap" (raw view only) toggles between
///     horizontal scroll for long lines and soft-wrapping inside the
///     visible width.
struct FileViewerPanel: View {
    let path: String

    @EnvironmentObject var appState: AppState
    @State private var loaded: LoadedBody = .loading
    @State private var rawText: String = ""
    @State private var hoverMore = false
    @State private var hoverOpenExt = false
    @State private var hoverCopy = false
    @State private var copied = false
    @State private var moreMenuOpen = false

    private enum LoadedBody: Equatable {
        case loading
        case image(URL)
        case markdown([MarkdownBlock])
        case plain(String)
        case unavailable(String)
    }

    private var fileURL: URL { URL(fileURLWithPath: path) }
    private var fileName: String { fileURL.lastPathComponent }
    private var folderName: String {
        if let project = appState.selectedProject?.name, !project.isEmpty {
            return project
        }
        let parent = fileURL.deletingLastPathComponent().lastPathComponent
        return parent.isEmpty ? "/" : parent
    }

    private var isMarkdown: Bool {
        if case .markdown = loaded { return true }
        return false
    }
    private var richViewDisabled: Bool {
        appState.richViewDisabledPaths.contains(path)
    }
    private var wordWrapEnabled: Bool {
        appState.wordWrapEnabledPaths.contains(path)
    }
    /// "Raw mode" is anything that ends up in the line-numbered monospace
    /// renderer, that is plain text files and markdown with rich-view
    /// disabled. The word-wrap toggle only makes sense for those.
    private var isRawMode: Bool {
        if case .plain = loaded { return true }
        return isMarkdown && richViewDisabled
    }

    var body: some View {
        RenderProbe.tick("FileViewerPanel")
        return VStack(spacing: 0) {
            breadcrumbRow
            divider
            content
        }
        .frame(maxHeight: .infinity)
        .overlayPreferenceValue(FileViewerMoreMenuAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if moreMenuOpen, let anchor {
                    let frame = proxy[anchor]
                    FileViewerMoreMenu(
                        isOpen: $moreMenuOpen,
                        showRichViewToggle: isMarkdown,
                        richViewDisabled: richViewDisabled,
                        showWordWrapToggle: isRawMode,
                        wordWrapEnabled: wordWrapEnabled,
                        onCopyPath: { copyPath() },
                        onToggleRichView: { toggleRichView() },
                        onToggleWordWrap: { toggleWordWrap() }
                    )
                    .anchoredPopupPlacement(
                        buttonFrame: frame,
                        proxy: proxy,
                        horizontal: .trailing()
                    )
                    .transition(.softNudge(y: 4))
                }
            }
            .allowsHitTesting(moreMenuOpen)
        }
        .animation(MenuStyle.openAnimation, value: moreMenuOpen)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Preview of \(fileName)"))
        .task(id: path) { reload() }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 0.5)
    }

    // MARK: - Breadcrumb row

    private var breadcrumbRow: some View {
        HStack(spacing: 6) {
            Text(folderName)
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(Color(white: 0.55))
                .lineLimit(1)
                .truncationMode(.middle)
            LucideIcon(.chevronRight, size: 10)
                .foregroundColor(Color(white: 0.35))
            Text(fileName)
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(Color(white: 0.85))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            iconButton(systemName: "ellipsis",
                       size: 12,
                       hoverState: $hoverMore,
                       label: "More") {
                moreMenuOpen.toggle()
            }
            .anchorPreference(key: FileViewerMoreMenuAnchorKey.self,
                              value: .bounds) { $0 }

            iconButton(hoverState: $hoverOpenExt, label: "Open externally") {
                NSWorkspace.shared.open(fileURL)
            } icon: {
                ExternalLinkIcon(size: 15)
            }

            iconButton(hoverState: $hoverCopy, label: "Copy contents") {
                copyContents()
            } icon: {
                if copied {
                    CheckIcon(size: 11)
                } else {
                    FolderStackIcon(size: 16)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
    }

    // MARK: - Body

    @ViewBuilder
    private var content: some View {
        switch loaded {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .image(let url):
            FileImagePreview(url: url)

        case .markdown(let blocks):
            if richViewDisabled {
                RawTextView(raw: rawText, syntax: .markdown, wordWrap: wordWrapEnabled)
            } else {
                ScrollView {
                    MarkdownDocumentView(blocks: blocks)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .thinScrollers()
            }

        case .plain(let raw):
            RawTextView(raw: raw, syntax: .plain, wordWrap: wordWrapEnabled)

        case .unavailable(let reason):
            VStack(spacing: 8) {
                FileChipIcon(size: 30)
                    .foregroundColor(Color(white: 0.40))
                Text(reason)
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Color(white: 0.55))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func iconButton(systemName: String,
                            size: CGFloat,
                            hoverState: Binding<Bool>,
                            label: String,
                            action: @escaping () -> Void) -> some View {
        iconButton(hoverState: hoverState, label: label, action: action) {
            LucideIcon.auto(systemName, size: 11)
                .font(BodyFont.system(size: size, weight: .regular))
        }
    }

    @ViewBuilder
    private func iconButton<Icon: View>(hoverState: Binding<Bool>,
                                        label: String,
                                        action: @escaping () -> Void,
                                        @ViewBuilder icon: () -> Icon) -> some View {
        Button(action: action) {
            icon()
                .foregroundColor(Color(white: hoverState.wrappedValue ? 0.85 : 0.55))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(hoverState.wrappedValue ? 0.06 : 0))
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hoverState.wrappedValue = $0 }
        .animation(.easeOut(duration: 0.12), value: hoverState.wrappedValue)
        .accessibilityLabel(label)
    }

    private func copyContents() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(rawText, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            copied = false
        }
    }

    private func copyPath() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(path, forType: .string)
    }

    private func toggleRichView() {
        if appState.richViewDisabledPaths.contains(path) {
            appState.richViewDisabledPaths.remove(path)
        } else {
            appState.richViewDisabledPaths.insert(path)
        }
    }

    private func toggleWordWrap() {
        if appState.wordWrapEnabledPaths.contains(path) {
            appState.wordWrapEnabledPaths.remove(path)
        } else {
            appState.wordWrapEnabledPaths.insert(path)
        }
    }

    // MARK: - Loading

    private func reload() {
        loaded = .loading
        let url = fileURL
        Task.detached(priority: .userInitiated) {
            let result: (LoadedBody, String) = Self.load(url: url)
            await MainActor.run {
                self.loaded = result.0
                self.rawText = result.1
            }
        }
    }

    private nonisolated static func load(url: URL) -> (LoadedBody, String) {
        if isImageExtension(url.pathExtension),
           FileManager.default.fileExists(atPath: url.path) {
            return (.image(url), "")
        }

        // Delegate to the shared resolver so dummy / fixture mode (which
        // sets `CLAWIX_FILE_FIXTURE_DIR`) returns the same synthesized
        // content the iPhone gets over the bridge.
        let result = BridgeFileReader.load(path: url.path)
        if let error = result.error {
            return (.unavailable(localizedReason(error)), "")
        }
        guard let raw = result.content else {
            return (.unavailable(localizedReason("File not found")), "")
        }
        if result.isMarkdown {
            return (.markdown(MarkdownParser.parse(raw)), raw)
        }
        return (.plain(raw), raw)
    }

    /// The shared reader returns canonical English reasons; map them
    /// back to the bundle-localized strings so the macOS UI stays
    /// translated.
    private nonisolated static func localizedReason(_ english: String) -> String {
        switch english {
        case "File not found":
            return String(localized: "File not found",
                          bundle: AppLocale.bundle,
                          locale: AppLocale.current)
        case "Couldn't read file":
            return String(localized: "Couldn't read file",
                          bundle: AppLocale.bundle,
                          locale: AppLocale.current)
        case "Preview not available for binary files":
            return String(localized: "Preview not available for binary files",
                          bundle: AppLocale.bundle,
                          locale: AppLocale.current)
        case "Couldn't decode file as text":
            return String(localized: "Couldn't decode file as text",
                          bundle: AppLocale.bundle,
                          locale: AppLocale.current)
        default:
            return english
        }
    }

    private nonisolated static func isImageExtension(_ ext: String) -> Bool {
        switch ext.lowercased() {
        case "png", "jpg", "jpeg", "gif", "heic", "heif", "tif", "tiff", "bmp", "webp":
            return true
        default:
            return false
        }
    }
}

private struct FileImagePreview: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(18)
                }
                .thinScrollers()
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: url.path) {
            image = await Task.detached(priority: .userInitiated) {
                NSImage(contentsOf: url)
            }.value
        }
    }
}

// MARK: - More menu anchor

private struct FileViewerMoreMenuAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

// MARK: - More menu

private struct FileViewerMoreMenu: View {
    @Binding var isOpen: Bool
    let showRichViewToggle: Bool
    let richViewDisabled: Bool
    let showWordWrapToggle: Bool
    let wordWrapEnabled: Bool
    let onCopyPath: () -> Void
    let onToggleRichView: () -> Void
    let onToggleWordWrap: () -> Void

    @State private var hovered: String?

    private static let menuWidth: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(id: "copyPath", title: "Copy path") {
                CopyIconViewSquircle(color: MenuStyle.rowIcon, lineWidth: 1.0)
                    .frame(width: 13, height: 13)
            } action: {
                onCopyPath()
                isOpen = false
            }

            if showRichViewToggle {
                row(id: "toggleRichView",
                    title: richViewDisabled ? "Enable rich view" : "Disable rich view") {
                    LucideIcon.auto(richViewDisabled ? "photo" : "curlybraces", size: 13)
                        .foregroundColor(MenuStyle.rowIcon)
                } action: {
                    onToggleRichView()
                    isOpen = false
                }
            }

            if showWordWrapToggle {
                row(id: "toggleWordWrap",
                    title: wordWrapEnabled ? "Disable word wrap" : "Enable word wrap") {
                    WordWrapToggleIcon(
                        progress: wordWrapEnabled ? 0 : 1,
                        rightBarOpacity: 1,
                        color: MenuStyle.rowIcon,
                        lineWidth: 1.0
                    )
                    .frame(width: 13, height: 13)
                } action: {
                    onToggleWordWrap()
                    isOpen = false
                }
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: Self.menuWidth, alignment: .leading)
        .menuStandardBackground()
        .background(MenuOutsideClickWatcher(isPresented: $isOpen))
    }

    @ViewBuilder
    private func row<Icon: View>(id: String,
                                 title: LocalizedStringKey,
                                 @ViewBuilder icon: () -> Icon,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                icon()
                    .frame(width: 18, alignment: .center)
                Text(title)
                    .font(BodyFont.system(size: 13))
                    .foregroundColor(MenuStyle.rowText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding + 4)
            .padding(.vertical, MenuStyle.rowVerticalPadding + 1)
            .background(MenuRowHover(active: hovered == id))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hovered = id }
            else if hovered == id { hovered = nil }
        }
    }
}

// MARK: - Raw text view (line numbers + light syntax)

/// Monospace renderer with a line-number gutter and very light syntax
/// tinting. For markdown the heading prefix and the bullet markers
/// borrow the same accent; everything else stays in the body colour.
/// The plain variant just renders every line in the body colour.
private struct RawTextView: View {
    enum Syntax { case markdown, plain }

    let raw: String
    let syntax: Syntax
    let wordWrap: Bool

    private static let body  = Color(white: 0.92)
    private static let muted = Color(white: 0.40)
    private static let accent = Color(red: 0.96, green: 0.55, blue: 0.55)

    private var lines: [String] {
        // Trailing newline produces an empty last entry that adds a
        // visually distracting "phantom" gutter row, so drop it.
        var arr = raw.components(separatedBy: "\n")
        if let last = arr.last, last.isEmpty, arr.count > 1 { arr.removeLast() }
        return arr
    }

    private var gutterWidth: CGFloat {
        let digits = max(2, String(lines.count).count)
        return CGFloat(digits) * 8 + 8
    }

    var body: some View {
        // SwiftUI's `ScrollView` centers content when its intrinsic size is
        // smaller than the visible bounds, so a short markdown file in raw
        // mode would float in the middle of the panel. Pinning the content
        // to topLeading inside a frame that fills at least the viewport
        // keeps short files anchored at the top, while long files still
        // grow past the bounds and scroll normally.
        GeometryReader { proxy in
            if wordWrap {
                ScrollView(.vertical) {
                    content
                        .frame(
                            maxWidth: .infinity,
                            minHeight: proxy.size.height,
                            alignment: .topLeading
                        )
                }
                .thinScrollers()
            } else {
                ScrollView([.vertical, .horizontal]) {
                    content
                        .frame(
                            minWidth: proxy.size.width,
                            minHeight: proxy.size.height,
                            alignment: .topLeading
                        )
                }
                .thinScrollers()
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                HStack(alignment: .top, spacing: 14) {
                    Text(verbatim: "\(idx + 1)")
                        .font(BodyFont.system(size: 12.5, design: .monospaced))
                        .foregroundColor(Self.muted)
                        .frame(width: gutterWidth, alignment: .trailing)
                    lineText(line)
                        .font(BodyFont.system(size: 12.5, design: .monospaced))
                        .modifier(NoWrapIfNeeded(wrap: wordWrap))
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.trailing, 16)
    }

    @ViewBuilder
    private func lineText(_ line: String) -> some View {
        if line.isEmpty {
            // Preserve the row height so the gutter stays evenly spaced.
            Text(" ").foregroundColor(Self.body)
        } else if syntax == .markdown {
            Text(markdownAttributed(line))
        } else {
            Text(line).foregroundColor(Self.body)
        }
    }

    /// Light-touch markdown tokenizer: heading lines (`# ` … `###### `)
    /// and unordered bullet markers (`-`, `*`, `+`) borrow the accent
    /// colour, fenced code lines (```) too. Inline code / bold / links
    /// are intentionally left alone, since the goal of raw view is to
    /// show the source, not re-render it.
    private func markdownAttributed(_ line: String) -> AttributedString {
        var attr = AttributedString(line)
        attr.foregroundColor = Self.body

        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        let leading = line.count - trimmed.count

        if trimmed.hasPrefix("#") {
            // 1..6 hashes followed by a space → heading line, accent
            // the entire visible content.
            var hashes = 0
            for ch in trimmed {
                if ch == "#" { hashes += 1 } else { break }
                if hashes > 6 { break }
            }
            if hashes >= 1 && hashes <= 6 {
                let after = trimmed.index(trimmed.startIndex, offsetBy: hashes)
                if after == trimmed.endIndex || trimmed[after] == " " {
                    attr.foregroundColor = Self.accent
                    return attr
                }
            }
        }

        if trimmed.hasPrefix("```") {
            attr.foregroundColor = Self.accent
            return attr
        }

        if let first = trimmed.first, "-*+".contains(first) {
            let afterIdx = trimmed.index(after: trimmed.startIndex)
            if afterIdx < trimmed.endIndex && trimmed[afterIdx] == " " {
                let markerStart = line.index(line.startIndex, offsetBy: leading)
                let markerEnd   = line.index(markerStart, offsetBy: 1)
                if let r = Range(markerStart..<markerEnd, in: attr) {
                    attr[r].foregroundColor = Self.accent
                }
                return attr
            }
        }

        return attr
    }
}

/// SwiftUI does not expose a "do not wrap" flag on `Text`, so we lean
/// on `fixedSize` to opt long lines out of the parent's constrained
/// width. When wrap is on we drop the modifier entirely so the line
/// re-flows inside the visible bounds.
private struct NoWrapIfNeeded: ViewModifier {
    let wrap: Bool
    func body(content: Content) -> some View {
        if wrap {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            content.fixedSize(horizontal: true, vertical: false)
        }
    }
}
