import SwiftUI

/// Custom copy glyph used in place of SF Symbols `doc.on.doc` in the
/// per-message action row under assistant replies. Two squircle sheets
/// offset diagonally; the back one is clipped against the front so the
/// stroke reads as overlapping paper. Matches the macOS
/// `CopyIconViewSquircle` so both targets share the same visual.
struct CopyIconView: View {
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
