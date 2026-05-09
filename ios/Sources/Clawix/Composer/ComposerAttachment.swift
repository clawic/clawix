import Foundation
import ClawixCore
#if canImport(UIKit)
import UIKit
#endif

// One image picked, captured, or pulled from the photo library while
// composing a turn. The view layer keeps a `UIImage` for the chip
// preview and re-encodes JPEG bytes once at send time so the wire
// payload stays small.

#if canImport(UIKit)
struct ComposerAttachment: Identifiable, Equatable {
    let id: String
    let preview: UIImage

    init(id: String = UUID().uuidString, preview: UIImage) {
        self.id = id
        self.preview = preview
    }

    /// Lossy JPEG bytes ready to ship. We aim at quality 0.85 which
    /// keeps a 12MP photo under ~1.5 MB on average — comfortable for
    /// inline JSON over the LAN bridge without sacrificing legibility
    /// for screenshots and code printouts the model needs to read.
    func wireAttachment() -> WireAttachment? {
        let scaled = ComposerAttachment.scaledForUpload(preview)
        guard let data = scaled.jpegData(compressionQuality: 0.85) else { return nil }
        return WireAttachment(
            id: id,
            mimeType: "image/jpeg",
            filename: "\(id).jpg",
            dataBase64: data.base64EncodedString()
        )
    }

    /// Caps the longest edge at 2048pt so a 48MP iPhone photo doesn't
    /// turn into a 6MB base64 blob over loopback. Codex resizes images
    /// before sending to the model anyway, so anything above this is
    /// wasted bridge bandwidth.
    private static func scaledForUpload(_ image: UIImage) -> UIImage {
        let maxEdge: CGFloat = 2048
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxEdge else { return image }
        let scale = maxEdge / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    static func == (lhs: ComposerAttachment, rhs: ComposerAttachment) -> Bool {
        lhs.id == rhs.id
    }
}
#endif
