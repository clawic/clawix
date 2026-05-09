import SwiftUI
import ClawixCore
#if canImport(UIKit)
import UIKit
#endif

/// Pulls the inline images out of an assistant `WireMessage` and renders
/// them as a single tile row above the prose. Two sources are merged:
///
/// 1. `WireWorkItem` rows of kind `imageGeneration` with a
///    `generatedImagePath` (work-item path: the model called Codex's
///    `imagegen` tool and Codex wrote a PNG into the session's
///    `generated_images/` folder).
/// 2. Markdown image links the model wrote inline pointing into that
///    same folder, e.g.
///    `![](/Users/.../codex/generated_images/<session>/ig_*.png)`.
///    Old conversations include this style because the model fell back
///    to writing the raw path after the user said the work-item-only
///    image hadn't shown up.
///
/// Bytes are fetched lazily through `BridgeStore.requestGeneratedImage`
/// — the daemon validates the path stays inside the sandbox and ships
/// the bytes back over the same WebSocket. Tap opens the existing
/// `ImageViewerView` fullscreen.

#if canImport(UIKit)

enum AssistantInlineImageSources {

    /// Path component every supported image lives under. Keeps the
    /// scope tight: paths the assistant happens to mention that aren't
    /// in `~/.codex/generated_images/` are ignored to avoid trying to
    /// fetch arbitrary user files (the daemon would refuse anyway, but
    /// surfacing a "denied" placeholder for arbitrary mentions would
    /// be noise).
    private static let marker = "/.codex/generated_images/"

    /// Regex that extracts `![alt](url)` pairs. Tolerant of url-encoded
    /// payloads and of `file://` prefixes the model sometimes emits.
    private static let inlineImageRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#)
    }()

    /// Ordered, deduplicated list of paths the assistant message
    /// references. Order matters because the user reads work-items
    /// first (they show up in the timeline) and then the markdown
    /// body; preserving order keeps the tiles aligned with the user's
    /// mental model of which image is which.
    ///
    /// Work-item paths are filtered to `status == .completed` to avoid
    /// the race window where the iPhone asks the daemon for bytes
    /// before Codex has finished writing the PNG (the daemon would
    /// reply "Image not found" and the cache would stick on `.failed`
    /// even after the file appeared). Markdown paths are always
    /// included because the model only writes the link once the file
    /// is on disk.
    static func paths(from message: WireMessage) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []

        let workItems = collectWorkItems(message)
        for item in workItems
        where item.kind == "imageGeneration" && item.status == .completed {
            guard let path = item.generatedImagePath?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty,
                  path.contains(marker)
            else { continue }
            if seen.insert(path).inserted { out.append(path) }
        }

        for path in markdownPaths(in: message.content) {
            if seen.insert(path).inserted { out.append(path) }
        }
        return out
    }

    /// Returns the message body with the inline image markdown removed.
    /// `![](path-into-sandbox)` matches collapse to a paragraph break
    /// instead of disappearing outright so the prose either side stays
    /// in its own paragraph (the user complained about "aquí. Aquí la
    /// tienes:" being concatenated when the model split the sentence
    /// across the image).
    ///
    /// `isStreaming == true` also hides any unfinished `![` or `[`
    /// link the model is mid-typing. Without that the user sees the
    /// raw markdown grow character by character (`![im` → `![imag` →
    /// `![imagen](/Use…`) until the closing paren lands.
    static func strip(_ source: String, isStreaming: Bool = false) -> String {
        guard let regex = inlineImageRegex else { return source }
        let ns = source as NSString
        var replacements: [(NSRange, String)] = []
        let matches = regex.matches(
            in: source,
            range: NSRange(location: 0, length: ns.length)
        )
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3 else { continue }
            let urlRange = match.range(at: 2)
            let url = ns.substring(with: urlRange)
            let normalized = normalize(path: url)
            guard normalized.contains(marker) else { continue }
            // Replace with a paragraph break so prose either side of
            // the image keeps its own line. The collapsing pass below
            // strips redundant blank lines, so back-to-back `![]`
            // matches don't accumulate.
            replacements.append((match.range, "\n\n"))
        }
        var result = source
        let nsResult = NSMutableString(string: result)
        for (range, repl) in replacements {
            nsResult.replaceCharacters(in: range, with: repl)
        }
        result = nsResult as String

        if isStreaming {
            result = trimUnfinishedTrailingLink(result)
        }

        // Collapse extra blank lines so paragraphs read cleanly,
        // preserving exactly one blank line as the paragraph
        // separator.
        return result
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces).isEmpty ? "" : $0 }
            .reduce(into: [String]()) { acc, line in
                if line.isEmpty, acc.last == "" { return }
                acc.append(line)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// While the assistant is still streaming, look for a trailing
    /// markdown link/image opener that hasn't been closed yet (`![…`
    /// or `[…` without a balancing `)`) and drop it from the visible
    /// body. The user wants the link to materialise in one go when
    /// the closing paren lands, not character-by-character.
    private static func trimUnfinishedTrailingLink(_ source: String) -> String {
        // Scan backwards: if we hit a `)` first we're past any open
        // link; if we hit a `[` (with optional `!` prefix) first and
        // there is no `)` to its right, that opener is unfinished and
        // everything from it onwards should disappear.
        var idx = source.endIndex
        var sawOpenParen = false
        while idx > source.startIndex {
            idx = source.index(before: idx)
            let ch = source[idx]
            if ch == ")" {
                return source
            }
            if ch == "(" {
                sawOpenParen = true
                continue
            }
            if ch == "[" {
                // Only treat as a link opener when followed (somewhere
                // later) by `(` — otherwise it's a literal `[` the
                // model wrote.
                if !sawOpenParen { return source }
                let cutStart: String.Index
                if idx > source.startIndex {
                    let prev = source.index(before: idx)
                    if source[prev] == "!" {
                        cutStart = prev
                    } else {
                        cutStart = idx
                    }
                } else {
                    cutStart = idx
                }
                return String(source[..<cutStart])
            }
            if ch == "\n" {
                // Newline closes the search window: a link can't span
                // a blank line, so anything before the newline is
                // already a complete paragraph.
                return source
            }
        }
        return source
    }

    private static func collectWorkItems(_ message: WireMessage) -> [WireWorkItem] {
        var items: [WireWorkItem] = []
        if let summary = message.workSummary {
            items.append(contentsOf: summary.items)
        }
        for entry in message.timeline {
            if case .tools(_, let toolItems) = entry {
                items.append(contentsOf: toolItems)
            }
        }
        return items
    }

    private static func markdownPaths(in source: String) -> [String] {
        guard let regex = inlineImageRegex else { return [] }
        let ns = source as NSString
        let matches = regex.matches(
            in: source,
            range: NSRange(location: 0, length: ns.length)
        )
        return matches.compactMap { match -> String? in
            guard match.numberOfRanges >= 3 else { return nil }
            let raw = ns.substring(with: match.range(at: 2))
            let normalized = normalize(path: raw)
            return normalized.contains(marker) ? normalized : nil
        }
    }

    private static func normalize(path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.isFileURL {
            return url.path
        }
        if trimmed.hasPrefix("file://") {
            return String(trimmed.dropFirst("file://".count))
        }
        // Some models percent-encode the path; decode best-effort.
        return trimmed.removingPercentEncoding ?? trimmed
    }
}

/// Renders the tile row described above. Receives the resolved paths
/// list (so callers can dedupe / filter once at the call site) and
/// drives the bridge fetch + cache through `BridgeStore`. Empty list
/// → empty view; a fail state shows a small placeholder pill so the
/// user knows the agent did produce an image but the bridge couldn't
/// serve it (file gone, sandbox denied, etc).
struct AssistantInlineImagesView: View {
    let paths: [String]
    @Bindable var store: BridgeStore
    let onOpen: (Int, [UIImage]) -> Void

    var body: some View {
        if paths.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(paths.enumerated()), id: \.element) { _, path in
                    tile(for: path)
                }
            }
        }
    }

    @ViewBuilder
    private func tile(for path: String) -> some View {
        let state = stateOrFetch(path)
        switch state {
        case .loading:
            shimmerPlaceholder
        case .loaded(let image):
            tileImage(image, path: path)
        case .failed(let reason):
            failurePill(reason: reason, path: path)
        }
    }

    private func stateOrFetch(_ path: String) -> BridgeStore.GeneratedImageState {
        if let existing = store.generatedImagesByPath[path] {
            return existing
        }
        // Schedule the fetch on the next runloop tick so we don't
        // mutate observable state inside `body`. The view re-renders
        // when the fetch completes via the @Bindable subscription.
        Task { @MainActor in
            _ = store.requestGeneratedImage(path: path)
        }
        return .loading
    }

    private var shimmerPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .overlay(alignment: .center) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white.opacity(0.55))
            }
    }

    private func tileImage(_ image: UIImage, path: String) -> some View {
        let pathsList = paths
        let images: [UIImage] = pathsList.compactMap {
            if case .loaded(let img) = store.generatedImagesByPath[$0] {
                return img
            }
            return nil
        }
        let index = images.firstIndex(of: image) ?? 0
        return Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onTapGesture {
                Haptics.tap()
                onOpen(index, images)
            }
    }

    private func failurePill(reason: String, path: String) -> some View {
        HStack(spacing: 8) {
            LucideIcon(.imageOff, size: 22.5)
                .foregroundStyle(.white.opacity(0.55))
            Text(reason)
                .font(BodyFont.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.65))
            Spacer(minLength: 0)
            Button {
                Haptics.tap()
                store.generatedImagesByPath[path] = nil
                _ = store.requestGeneratedImage(path: path)
            } label: {
                Text("Retry")
                    .font(BodyFont.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }
}

#endif
