import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
/// Renders a SwiftUI view (typically one of the custom Clawix glyphs) to
/// a template-mode `UIImage` so it can ride inside a native `Menu` row.
/// `UIMenu` strips arbitrary SwiftUI icons but keeps `Image(uiImage:)`
/// when its `renderingMode` is `.alwaysTemplate`, which is also what
/// makes the system tint the glyph the same way it tints SF Symbols.
@MainActor
enum MenuIconImage {
    /// Cached on first read so the menu doesn't re-rasterize the glyph
    /// every time the body recomputes. Rendered in white because
    /// `.alwaysTemplate` discards the source color and the system menu
    /// applies its own tint.
    static let pencil: UIImage? = render(size: 18) {
        PencilIconView(color: .white, lineWidth: 1.4)
    }
    static let archive: UIImage? = render(size: 18) {
        ArchiveIconView(color: .white, lineWidth: 1.4, size: 18)
    }

    static func render<V: View>(
        size: CGFloat,
        @ViewBuilder content: () -> V
    ) -> UIImage? {
        let renderer = ImageRenderer(content: content().frame(width: size, height: size))
        renderer.scale = UIScreen.main.scale
        renderer.isOpaque = false
        return renderer.uiImage?.withRenderingMode(.alwaysTemplate)
    }
}
#endif
