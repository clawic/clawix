import AppKit
import SwiftUI
import ClawixCore

enum UserBubbleContent {
    enum ImageSource: Identifiable, Equatable {
        case file(URL)
        case attachment(WireAttachment)

        var id: String {
            switch self {
            case .file(let url): return "file:\(url.standardizedFileURL.path)"
            case .attachment(let attachment): return "attachment:\(attachment.id)"
            }
        }
    }

    struct Parsed {
        var images: [ImageSource]
        var files: [URL]
        var text: String
    }

    private static let imageExts: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "tif", "bmp", "webp"
    ]

    /// `NSRegularExpression` is moderately expensive to compile and the
    /// pattern never changes — compile once for the lifetime of the
    /// process so every visible user bubble doesn't re-pay that cost on
    /// each render.
    private static let mentionRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"@(/.+?)(?=\s+@/|\n|$)"#
    )

    private static let mentionedFileRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?m)^##\s+.*?:\s+(/.+)$"#
    )
    private static let cache = MarkdownBlockCache<Parsed>(countLimit: 256)

    static func parse(_ raw: String, attachments: [WireAttachment] = []) -> Parsed {
        let key = cacheKey(raw: raw, attachments: attachments)
        return cache.parse(key) { _ in
            parseUncached(raw, attachments: attachments)
        }
    }

    private static func parseUncached(_ raw: String, attachments: [WireAttachment]) -> Parsed {
        // Mentions in user messages come from `AppState.sendMessage`, which
        // builds them as `@<absolute-path>` joined by single spaces and
        // separated from the body by `\n\n`. Paths can contain spaces
        // (e.g. "My Project Folder"), so we can't stop at the first
        // whitespace. Stop on either ` @/` (next mention), `\n`, or end of
        // string. Lazy `.+?` ensures we don't swallow the body.
        let extracted = extractFilesMentionedWrapper(from: raw)
        let source = extracted.text
        guard let regex = mentionRegex else {
            return Parsed(
                images: extracted.imageURLs.map { .file($0) } + attachmentImages(attachments),
                files: extracted.fileURLs,
                text: source.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        let ns = source as NSString
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: ns.length))
        var imageURLs = extracted.imageURLs
        var files = extracted.fileURLs
        var ranges: [NSRange] = []
        for m in matches where m.numberOfRanges >= 2 {
            let path = ns.substring(with: m.range(at: 1))
                .trimmingCharacters(in: .whitespaces)
            guard path.hasPrefix("/") else { continue }
            let url = URL(fileURLWithPath: path)
            if imageExts.contains(url.pathExtension.lowercased()) {
                imageURLs.append(url)
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
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedImagePaths = Set(imageURLs.map { $0.standardizedFileURL.path })
        let extraAttachments = attachmentImages(attachments).filter { source in
            guard case .attachment(let attachment) = source else { return true }
            let filename = attachment.filename ?? ""
            return !normalizedImagePaths.contains { path in
                (path as NSString).lastPathComponent == filename
            }
        }
        return Parsed(
            images: imageURLs.map { .file($0) } + extraAttachments,
            files: files,
            text: text
        )
    }

    private static func cacheKey(raw: String, attachments: [WireAttachment]) -> String {
        guard !attachments.isEmpty else { return raw }
        let attachmentKey = attachments.map { attachment in
            [
                attachment.id,
                attachment.kind.rawValue,
                attachment.filename ?? "",
                String(attachment.dataBase64.count)
            ].joined(separator: "\u{1f}")
        }.joined(separator: "\u{1e}")
        return raw + "\u{1d}" + attachmentKey
    }

    private static func extractFilesMentionedWrapper(from raw: String) -> (text: String, imageURLs: [URL], fileURLs: [URL]) {
        let source = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let markers = [
            "## My request for Clawix:",
            "## My request for " + ["Co", "dex"].joined() + ":"
        ]
        guard let markerRange = markers.compactMap({ source.range(of: $0) }).first else {
            return (source, [], [])
        }

        let header = "# Files mentioned by the user:"
        let beforeHeader = source.range(of: header).map { String(source[..<$0.lowerBound]) } ?? ""
        let fileBlockStart = source.range(of: header)?.lowerBound ?? source.startIndex
        let fileBlock = String(source[fileBlockStart..<markerRange.lowerBound])
        let request = String(source[markerRange.upperBound...])
        let cleanText = [beforeHeader, request]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let regex = mentionedFileRegex else { return (cleanText, [], []) }
        let ns = fileBlock as NSString
        let matches = regex.matches(in: fileBlock, range: NSRange(location: 0, length: ns.length))
        var images: [URL] = []
        var files: [URL] = []
        for match in matches where match.numberOfRanges >= 2 {
            let path = ns.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard path.hasPrefix("/") else { continue }
            let url = URL(fileURLWithPath: path)
            if imageExts.contains(url.pathExtension.lowercased()) {
                images.append(url)
            } else {
                files.append(url)
            }
        }
        return (cleanText, images, files)
    }

    private static func attachmentImages(_ attachments: [WireAttachment]) -> [ImageSource] {
        attachments
            .filter { $0.kind == .image }
            .map { .attachment($0) }
    }
}

struct UserMentionPreviews: View {
    let parsed: UserBubbleContent.Parsed
    /// Tap on a mentioned image opens the lightbox. Routed through a
    /// closure (instead of reading `AppState` directly) so this view —
    /// and its `MessageRow` parent — can stay independent of
    /// `AppState`'s @Published storm during streaming, which would
    /// otherwise invalidate every visible bubble on every delta.
    let onOpenImage: (URL) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if !parsed.images.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(parsed.images.enumerated()), id: \.offset) { _, source in
                        UserImageThumbnail(source: source)
                            .onTapGesture {
                                if case .file(let url) = source {
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        onOpenImage(url)
                                    }
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

struct UserImageThumbnail: View {
    let source: UserBubbleContent.ImageSource
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
                LucideIcon(.image, size: 12.5)
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
        .help(helpText)
        .task(id: source.id) {
            let loaded = await Task.detached(priority: .userInitiated) { () -> (image: NSImage?, bytes: Int) in
                switch source {
                case .file(let url):
                    let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                    let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
                    return (NSImage(contentsOf: url), size)
                case .attachment(let attachment):
                    guard let data = Data(base64Encoded: attachment.dataBase64) else { return (nil, 0) }
                    return (NSImage(data: data), data.count)
                }
            }.value
            PerfSignpost.imageLoad.event("thumbnail.bytes", loaded.bytes)
            if loaded.image != nil {
                PerfSignpost.imageLoad.event("thumbnail.loaded")
            }
            self.image = loaded.image
        }
    }

    private var helpText: String {
        switch source {
        case .file(let url): return url.lastPathComponent
        case .attachment(let attachment): return attachment.filename ?? "Image"
        }
    }
}

struct UserFileMentionChip: View {
    let url: URL

    var body: some View {
        HStack(spacing: 6) {
            FileChipIcon(size: 11)
                .foregroundColor(Color(white: 0.78))
            Text(verbatim: url.lastPathComponent)
                .font(BodyFont.system(size: 14, wght: 500))
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

struct UserMessageTextBubble: View {
    let paragraphs: [String]
    let findQuery: String
    let exposeAccessibility: Bool
    let accessibilityText: String
    let onExpand: () -> Void

    @State private var isExpanded = false
    @State private var measuredHeight: CGFloat = 0
    @State private var collapsedHovered = false

    private static let maxCollapsedContentHeight: CGFloat = 575
    private static let verticalPadding: CGFloat = 11
    private static let bubbleSolid = Color(white: 0.12)

    var body: some View {
        let exceedsCap = measuredHeight > Self.maxCollapsedContentHeight + 1
        let collapsed = exceedsCap && !isExpanded
        let cappedContentHeight = min(measuredHeight, Self.maxCollapsedContentHeight)
        let displayHeight: CGFloat? = {
            guard measuredHeight > 0 else { return nil }
            return collapsed
                ? cappedContentHeight + 2 * Self.verticalPadding
                : measuredHeight + 2 * Self.verticalPadding
        }()

        ZStack(alignment: .bottom) {
            textContent
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: UserBubbleContentHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, Self.verticalPadding)
                .frame(height: displayHeight, alignment: .top)
                .clipped()

            if collapsed {
                showMoreOverlay
                    .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onPreferenceChange(UserBubbleContentHeightKey.self) { newValue in
            guard abs(newValue - measuredHeight) > 0.5 else { return }
            measuredHeight = newValue
        }
        .onChange(of: paragraphs) { _, _ in
            isExpanded = false
        }
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(!exposeAccessibility)
        .accessibilityLabel(Text(verbatim: accessibilityText))
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, p in
                Group {
                    if substringMatches(p, query: findQuery) {
                        Text(highlightedAttributed(p, query: findQuery))
                    } else {
                        Text(verbatim: p)
                    }
                }
                .font(BodyFont.system(size: 13.5, wght: 500))
                .foregroundColor(Palette.textPrimary)
                .lineSpacing(5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var showMoreOverlay: some View {
        Button(action: expand) {
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    Text(verbatim: String(
                        localized: "Show more",
                        bundle: AppLocale.bundle,
                        locale: AppLocale.current
                    ))
                    .font(BodyFont.system(size: 12, wght: 600))
                    LucideIcon(.chevronDown, size: 11)
                }
                .foregroundColor(Color(white: collapsedHovered ? 0.95 : 0.78))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, Self.verticalPadding)
            .padding(.top, 56)
            .contentShape(Rectangle())
            .background(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Self.bubbleSolid.opacity(0), location: 0),
                        .init(color: Self.bubbleSolid.opacity(0.85), location: 0.55),
                        .init(color: Self.bubbleSolid, location: 1)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { collapsedHovered = hovering }
        }
    }

    private func expand() {
        withAnimation(.easeOut(duration: 0.28)) {
            isExpanded = true
        }
        onExpand()
    }
}

struct UserBubbleContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
