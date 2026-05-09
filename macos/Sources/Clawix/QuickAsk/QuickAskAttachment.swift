import Foundation

/// Item staged above the QuickAsk prompt input via the `+` menu, drag &
/// drop, paste, screenshot, camera, clipboard sniffer or selection
/// sniffer. On submit each attachment is forwarded to the backend via
/// the same path `ComposerAttachment` uses (image attachments become
/// inline `localImage` items; non-image files are prepended to the
/// prompt as `@<absolute-path>` mentions).
///
/// `kind` distinguishes the origin so the chip renders differently
/// (camera shot vs uploaded photo vs clipboard sniff) without having to
/// inspect the URL or the file metadata. Fase B–D add the producers;
/// Fase A only ships the type so consumers (chips bar, controller's
/// pending list) compile.
struct QuickAskAttachment: Identifiable, Equatable {
    enum Kind: String, Equatable {
        /// Picked from the `+` menu's "Load file" / "Load photo" entries.
        case file
        /// `screencapture` PNG dropped into Caches/Clawix-Captures.
        case screenshot
        /// In-line AVFoundation snap saved to a temp URL.
        case camera
        /// Drag-and-drop landed on the panel.
        case drop
        /// Pasted from the system clipboard.
        case paste
        /// Auto-detected from the system clipboard at panel open.
        case clipboard
        /// Auto-extracted text from the frontmost app at panel open.
        case selection
    }

    let id: UUID
    let url: URL
    let kind: Kind
    /// Optional preview text when the attachment is text-only (a
    /// `.selection` chip wraps a snippet, a `.clipboard` chip can wrap
    /// the copied string). Image / file kinds leave this nil and the
    /// chip falls back to `url.lastPathComponent`.
    let previewText: String?

    init(
        id: UUID = UUID(),
        url: URL,
        kind: Kind,
        previewText: String? = nil
    ) {
        self.id = id
        self.url = url
        self.kind = kind
        self.previewText = previewText
    }

    var filename: String { url.lastPathComponent }

    var isImage: Bool {
        let imageExts: Set<String> = [
            "png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "tif", "bmp", "webp"
        ]
        return imageExts.contains(url.pathExtension.lowercased())
    }

    var isPDF: Bool {
        url.pathExtension.lowercased() == "pdf"
    }
}
