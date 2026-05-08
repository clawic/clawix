import SwiftUI

/// Lucide-sourced icon registry. Every glyph here is hand-ported from the
/// open-source `lucide-icons/lucide` library (https://lucide.dev), drawn
/// directly with SwiftUI `Path` so we ship neither the Lucide font nor the
/// raw SVGs as resources. Each `case` carries a citation comment naming
/// the source SVG, so a future contributor can tell at a glance that the
/// icon is library-derived rather than a Clawix-original glyph.
///
/// Project-custom icons (`MicIcon`, `WrenchIcon`, `FileChipIcon`, etc.)
/// live in their own files and MUST NOT carry the Lucide attribution
/// comment. Lucide-sourced icons live here and MUST.
///
/// Usage:
///
///     LucideIcon(.chevronDown, size: 13)
///         .foregroundStyle(Color(white: 0.86))
///
/// Native Lucide spec is preserved: 24-pt grid, ~2-pt stroke (we use 1.6
/// at design size to match the rest of the app's hairline language),
/// `lineCap: .round`, `lineJoin: .round`.
struct LucideIcon: View {
    enum Kind: String {
        // Geometric primitives ----------------------------------------------
        case chevronDown    = "chevron-down"
        case chevronUp      = "chevron-up"
        case chevronLeft    = "chevron-left"
        case chevronRight   = "chevron-right"
        case x
        case plus
        case minus
        case check
        case ellipsis

        // Arrows -----------------------------------------------------------
        case arrowUp        = "arrow-up"
        case arrowDown      = "arrow-down"
        case arrowLeft      = "arrow-left"
        case arrowRight     = "arrow-right"
        case arrowUpRight   = "arrow-up-right"
        case arrowDownToLine = "arrow-down-to-line"
        case arrowRightToLine = "arrow-right-to-line"
        case squareArrowOutUpRight = "square-arrow-out-up-right"
        case rotateCw       = "rotate-cw"
        case rotateCcw      = "rotate-ccw"
        case refreshCw      = "refresh-cw"
        case undo2          = "undo-2"
        case maximize2      = "maximize-2"
        case minimize2      = "minimize-2"

        // Domain glyphs ----------------------------------------------------
        case trash2         = "trash-2"
        case search                       // lucide: search
        case folder
        case archive
        case messageCircle  = "message-circle"
        case globe
        case paperclip
        case camera
        case image                        // lucide: image
        case images
        case imageOff       = "image-off"
        case send
        case zap
        case star
        case clock
        case list
        case listChecks     = "list-checks"
        case alignLeft      = "align-left"
        case key
        case link
        case laptop
        case scan
        case tornado
        case drama
        case fileQuestion   = "file-question"
        case squareDashed   = "square-dashed"
        case appWindow      = "app-window"
        case workflow
        case download
        case share2         = "share-2"
        case inbox
        case play
        case pause
        case square                       // for stop button
        case circleStop     = "circle-stop"
        case moon
        case audioWaveform  = "audio-waveform"
        case triangleAlert  = "triangle-alert"
        case circleAlert    = "circle-alert"
        case shieldAlert    = "shield-alert"
        case info
        case circleCheck    = "circle-check"
        case circleX        = "circle-x"
        case zapOff         = "zap-off"
        case eye
        case eyeOff         = "eye-off"
    }

    let kind: Kind
    var size: CGFloat
    var lineWidth: CGFloat?
    var filled: Bool

    init(_ kind: Kind, size: CGFloat = 16, lineWidth: CGFloat? = nil, filled: Bool = false) {
        self.kind = kind
        self.size = size
        self.lineWidth = lineWidth
        self.filled = filled
    }

    /// String-based init for sites where the Lucide name comes from data
    /// (e.g. settings categories, plugin metadata). Returns `nil` for an
    /// unknown name so callers can fall back to a placeholder. Pass the
    /// kebab-case Lucide name (e.g. "chevron-down", "trash-2").
    init?(name: String, size: CGFloat = 16, lineWidth: CGFloat? = nil, filled: Bool = false) {
        guard let kind = Kind(rawValue: name) else { return nil }
        self.init(kind, size: size, lineWidth: lineWidth, filled: filled)
    }

    /// Maps a legacy SF Symbol name to the equivalent Lucide kind. Used by
    /// `auto(systemName:size:)` and by data-driven call sites that store
    /// SF Symbol strings on enums or structs (settings categories, plugin
    /// metadata, etc.). Returns `nil` for symbols with no Lucide equivalent.
    static func sfToLucide(_ symbol: String) -> (Kind, Bool)? {
        switch symbol {
        case "chevron.down":  return (.chevronDown, false)
        case "chevron.up":    return (.chevronUp, false)
        case "chevron.left":  return (.chevronLeft, false)
        case "chevron.right": return (.chevronRight, false)
        case "xmark":         return (.x, false)
        case "plus":          return (.plus, false)
        case "minus":         return (.minus, false)
        case "checkmark":     return (.check, false)
        case "ellipsis":      return (.ellipsis, false)
        case "arrow.up":      return (.arrowUp, false)
        case "arrow.down":    return (.arrowDown, false)
        case "arrow.left":    return (.arrowLeft, false)
        case "arrow.right":   return (.arrowRight, false)
        case "arrow.up.right": return (.arrowUpRight, false)
        case "arrow.up.right.square": return (.squareArrowOutUpRight, false)
        case "arrow.right.to.line": return (.arrowRightToLine, false)
        case "arrow.down.to.line":  return (.arrowDownToLine, false)
        case "arrow.uturn.backward": return (.undo2, false)
        case "arrow.clockwise":      return (.rotateCw, false)
        case "arrow.counterclockwise": return (.rotateCcw, false)
        case "arrow.triangle.2.circlepath": return (.refreshCw, false)
        case "arrow.up.left.and.arrow.down.right": return (.maximize2, false)
        case "arrow.down.right.and.arrow.up.left": return (.minimize2, false)
        case "trash":         return (.trash2, false)
        case "magnifyingglass": return (.search, false)
        case "folder":        return (.folder, false)
        case "folder.fill":   return (.folder, true)
        case "archivebox":    return (.archive, false)
        case "bubble.left":   return (.messageCircle, false)
        case "globe", "globe.americas.fill": return (.globe, false)
        case "paperclip":     return (.paperclip, false)
        case "camera.fill", "camera": return (.camera, false)
        case "photo":         return (.image, false)
        case "photo.on.rectangle.angled": return (.images, false)
        case "photo.badge.exclamationmark": return (.imageOff, false)
        case "paperplane.fill", "paperplane": return (.send, false)
        case "bolt.fill", "bolt": return (.zap, false)
        case "bolt.slash.fill", "bolt.slash": return (.zapOff, false)
        case "star.fill":     return (.star, true)
        case "star":          return (.star, false)
        case "clock":         return (.clock, false)
        case "list.bullet":   return (.list, false)
        case "checklist":     return (.listChecks, false)
        case "text.alignleft": return (.alignLeft, false)
        case "key.viewfinder": return (.key, false)
        case "link.circle", "link": return (.link, false)
        case "laptopcomputer": return (.laptop, false)
        case "viewfinder":    return (.scan, false)
        case "tornado":       return (.tornado, false)
        case "theatermasks":  return (.drama, false)
        case "doc.questionmark": return (.fileQuestion, false)
        case "questionmark.square.dashed", "app.dashed": return (.squareDashed, false)
        case "app":           return (.appWindow, false)
        case "point.3.connected.trianglepath.dotted": return (.workflow, false)
        case "square.and.arrow.down": return (.download, false)
        case "square.and.arrow.up":   return (.share2, false)
        case "tray.and.arrow.down":   return (.inbox, false)
        case "play.fill":     return (.play, true)
        case "play":          return (.play, false)
        case "pause.fill":    return (.pause, true)
        case "pause":         return (.pause, false)
        case "stop.fill":     return (.square, true)
        case "stop.circle.fill", "stop.circle": return (.circleStop, false)
        case "moon.zzz", "moon": return (.moon, false)
        case "waveform":      return (.audioWaveform, false)
        case "exclamationmark.triangle.fill", "exclamationmark.triangle": return (.triangleAlert, false)
        case "exclamationmark.circle.fill", "exclamationmark.circle":     return (.circleAlert, false)
        case "exclamationmark.shield.fill", "exclamationmark.shield":     return (.shieldAlert, false)
        case "exclamationmark.applewatch": return (.circleAlert, false)
        case "info.circle.fill", "info.circle": return (.info, false)
        case "checkmark.circle.fill", "checkmark.circle": return (.circleCheck, false)
        case "xmark.circle.fill", "xmark.circle": return (.circleX, false)
        case "circle":        return (.circleStop, false)
        case "eye":           return (.eye, false)
        case "eye.slash":     return (.eyeOff, false)
        case "eyeglasses", "eyeglasses.slash": return (.eye, false)
        default: return nil
        }
    }

    /// Resolves an SF Symbol-style name at runtime: renders a `LucideIcon`
    /// for known mappings, falls back to `Image(systemName:)` for genuinely
    /// OS-level glyphs (`command`, `return`) or any name we have not ported
    /// yet. The fallback path inherits `.font(.system(size:))` from the
    /// caller, so call sites do not need to special-case missing mappings.
    @ViewBuilder
    static func auto(_ systemName: String, size: CGFloat = 16) -> some View {
        if let pair = LucideIcon.sfToLucide(systemName) {
            LucideIcon(pair.0, size: size, filled: pair.1)
        } else {
            Image(systemName: systemName)
                .font(.system(size: size))
        }
    }

    var body: some View {
        let lw = lineWidth ?? max(1.0, 1.6 * (size / 24))
        let stroke = StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round)
        Group {
            if filled {
                LucidePath(kind: kind).fill()
            } else {
                LucidePath(kind: kind).stroke(style: stroke)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Path registry

private struct LucidePath: Shape {
    let kind: LucideIcon.Kind

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width  - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }
        var path = Path()

        switch kind {

        // MARK: Geometric primitives

        case .chevronDown:
            // Source: lucide-icons/lucide · chevron-down.svg  ("m6 9 6 6 6-6")
            path.move(to: p(6, 9))
            path.addLine(to: p(12, 15))
            path.addLine(to: p(18, 9))

        case .chevronUp:
            // Source: lucide-icons/lucide · chevron-up.svg  ("m18 15-6-6-6 6")
            path.move(to: p(18, 15))
            path.addLine(to: p(12, 9))
            path.addLine(to: p(6, 15))

        case .chevronLeft:
            // Source: lucide-icons/lucide · chevron-left.svg  ("m15 18-6-6 6-6")
            path.move(to: p(15, 18))
            path.addLine(to: p(9, 12))
            path.addLine(to: p(15, 6))

        case .chevronRight:
            // Source: lucide-icons/lucide · chevron-right.svg  ("m9 18 6-6-6-6")
            path.move(to: p(9, 18))
            path.addLine(to: p(15, 12))
            path.addLine(to: p(9, 6))

        case .x:
            // Source: lucide-icons/lucide · x.svg  ("M18 6 6 18" + "m6 6 12 12")
            path.move(to: p(18, 6));  path.addLine(to: p(6, 18))
            path.move(to: p(6, 6));   path.addLine(to: p(18, 18))

        case .plus:
            // Source: lucide-icons/lucide · plus.svg  ("M5 12h14" + "M12 5v14")
            path.move(to: p(5, 12));  path.addLine(to: p(19, 12))
            path.move(to: p(12, 5));  path.addLine(to: p(12, 19))

        case .minus:
            // Source: lucide-icons/lucide · minus.svg  ("M5 12h14")
            path.move(to: p(5, 12));  path.addLine(to: p(19, 12))

        case .check:
            // Source: lucide-icons/lucide · check.svg  ("M20 6 9 17l-5-5")
            path.move(to: p(20, 6))
            path.addLine(to: p(9, 17))
            path.addLine(to: p(4, 12))

        case .ellipsis:
            // Source: lucide-icons/lucide · ellipsis.svg
            // Three filled dots at y=12, x=5/12/19, r=1.
            for cx in [CGFloat(5), 12, 19] {
                let r: CGFloat = 1
                path.addEllipse(in: CGRect(x: dx + (cx - r) * s,
                                           y: dy + (12 - r) * s,
                                           width:  2 * r * s,
                                           height: 2 * r * s))
            }

        // MARK: Arrows

        case .arrowUp:
            // Source: lucide-icons/lucide · arrow-up.svg
            // ("m5 12 7-7 7 7" + "M12 19V5")
            path.move(to: p(5, 12))
            path.addLine(to: p(12, 5))
            path.addLine(to: p(19, 12))
            path.move(to: p(12, 19));  path.addLine(to: p(12, 5))

        case .arrowDown:
            // Source: lucide-icons/lucide · arrow-down.svg
            // ("M12 5v14" + "m19 12-7 7-7-7")
            path.move(to: p(12, 5));   path.addLine(to: p(12, 19))
            path.move(to: p(19, 12))
            path.addLine(to: p(12, 19))
            path.addLine(to: p(5, 12))

        case .arrowLeft:
            // Source: lucide-icons/lucide · arrow-left.svg
            // ("m12 19-7-7 7-7" + "M19 12H5")
            path.move(to: p(12, 19))
            path.addLine(to: p(5, 12))
            path.addLine(to: p(12, 5))
            path.move(to: p(19, 12));  path.addLine(to: p(5, 12))

        case .arrowRight:
            // Source: lucide-icons/lucide · arrow-right.svg
            // ("M5 12h14" + "m12 5 7 7-7 7")
            path.move(to: p(5, 12));   path.addLine(to: p(19, 12))
            path.move(to: p(12, 5))
            path.addLine(to: p(19, 12))
            path.addLine(to: p(12, 19))

        case .arrowUpRight:
            // Source: lucide-icons/lucide · arrow-up-right.svg
            // ("M7 7h10v10" + "M7 17 17 7")
            path.move(to: p(7, 7))
            path.addLine(to: p(17, 7))
            path.addLine(to: p(17, 17))
            path.move(to: p(7, 17));   path.addLine(to: p(17, 7))

        case .arrowDownToLine:
            // Source: lucide-icons/lucide · arrow-down-to-line.svg
            // ("M12 17V3" + "m6 11 6 6 6-6" + "M19 21H5")
            path.move(to: p(12, 3));   path.addLine(to: p(12, 17))
            path.move(to: p(6, 11))
            path.addLine(to: p(12, 17))
            path.addLine(to: p(18, 11))
            path.move(to: p(5, 21));   path.addLine(to: p(19, 21))

        case .arrowRightToLine:
            // Source: lucide-icons/lucide · arrow-right-to-line.svg
            // ("M17 12H3" + "m11 18 6-6-6-6" + "M21 5v14")
            path.move(to: p(3, 12));   path.addLine(to: p(17, 12))
            path.move(to: p(11, 18))
            path.addLine(to: p(17, 12))
            path.addLine(to: p(11, 6))
            path.move(to: p(21, 5));   path.addLine(to: p(21, 19))

        case .squareArrowOutUpRight:
            // Source: lucide-icons/lucide · square-arrow-out-up-right.svg
            // Outline of an external-link button: a square with an arrow
            // breaking out of its top-right corner.
            // ("M21 3h-6" + "M21 3v6" + "m21 3-9 9"
            //  + "M21 14v5a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5")
            path.move(to: p(15, 3));   path.addLine(to: p(21, 3))
            path.move(to: p(21, 3));   path.addLine(to: p(21, 9))
            path.move(to: p(21, 3));   path.addLine(to: p(12, 12))
            path.move(to: p(21, 14))
            path.addLine(to: p(21, 19))
            path.addQuadCurve(to: p(19, 21), control: p(21, 21))
            path.addLine(to: p(5, 21))
            path.addQuadCurve(to: p(3, 19), control: p(3, 21))
            path.addLine(to: p(3, 5))
            path.addQuadCurve(to: p(5, 3), control: p(3, 3))
            path.addLine(to: p(10, 3))

        case .rotateCw:
            // Source: lucide-icons/lucide · rotate-cw.svg
            // ("M21 12a9 9 0 1 1-9-9c2.52 0 4.93 1 6.74 2.74L21 8"
            //  + "M21 3v5h-5")
            path.move(to: p(21, 12))
            path.addArc(center: p(12, 12), radius: 9 * s,
                        startAngle: .degrees(0),
                        endAngle: .degrees(-360 + 30),
                        clockwise: true,
                        transform: .identity)
            // simplified arrow tip: line back up to the L 21 8 segment
            path.move(to: p(21, 3));   path.addLine(to: p(21, 8))
            path.addLine(to: p(16, 8))

        case .rotateCcw:
            // Source: lucide-icons/lucide · rotate-ccw.svg
            // Mirror of rotate-cw on the y-axis.
            // ("M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"
            //  + "M3 3v5h5")
            path.move(to: p(3, 12))
            path.addArc(center: p(12, 12), radius: 9 * s,
                        startAngle: .degrees(180),
                        endAngle: .degrees(180 + 360 - 30),
                        clockwise: false,
                        transform: .identity)
            path.move(to: p(3, 3));    path.addLine(to: p(3, 8))
            path.addLine(to: p(8, 8))

        case .refreshCw:
            // Source: lucide-icons/lucide · refresh-cw.svg
            // Two arcs with two arrowheads forming a rotation symbol.
            // ("M21 12a9 9 0 0 0-9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"
            //  + "M3 3v5h5"
            //  + "M3 12a9 9 0 0 0 9 9 9.75 9.75 0 0 0 6.74-2.74L21 16"
            //  + "M16 16h5v5")
            path.move(to: p(21, 12))
            path.addArc(center: p(12, 12), radius: 9 * s,
                        startAngle: .degrees(0),
                        endAngle: .degrees(180 + 30),
                        clockwise: true)
            path.move(to: p(3, 3));    path.addLine(to: p(3, 8))
            path.addLine(to: p(8, 8))
            path.move(to: p(3, 12))
            path.addArc(center: p(12, 12), radius: 9 * s,
                        startAngle: .degrees(180),
                        endAngle: .degrees(360 + 30),
                        clockwise: true)
            path.move(to: p(16, 16));  path.addLine(to: p(21, 16))
            path.addLine(to: p(21, 21))

        case .undo2:
            // Source: lucide-icons/lucide · undo-2.svg
            // ("M9 14 4 9l5-5"
            //  + "M4 9h10.5a5.5 5.5 0 0 1 5.5 5.5a5.5 5.5 0 0 1-5.5 5.5H11")
            path.move(to: p(9, 14))
            path.addLine(to: p(4, 9))
            path.addLine(to: p(9, 4))
            path.move(to: p(4, 9))
            path.addLine(to: p(14.5, 9))
            path.addArc(center: p(14.5, 14.5), radius: 5.5 * s,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(90),
                        clockwise: false)
            path.addLine(to: p(11, 20))

        case .maximize2:
            // Source: lucide-icons/lucide · maximize-2.svg
            // ("M15 3h6v6" + "m21 3-7 7" + "m3 21 7-7" + "M9 21H3v-6")
            path.move(to: p(15, 3));   path.addLine(to: p(21, 3))
            path.addLine(to: p(21, 9))
            path.move(to: p(21, 3));   path.addLine(to: p(14, 10))
            path.move(to: p(3, 21));   path.addLine(to: p(10, 14))
            path.move(to: p(9, 21));   path.addLine(to: p(3, 21))
            path.addLine(to: p(3, 15))

        case .minimize2:
            // Source: lucide-icons/lucide · minimize-2.svg
            // ("M4 14h6v6" + "M20 10h-6V4" + "m14 10 7-7" + "m3 21 7-7")
            path.move(to: p(4, 14));   path.addLine(to: p(10, 14))
            path.addLine(to: p(10, 20))
            path.move(to: p(20, 10));  path.addLine(to: p(14, 10))
            path.addLine(to: p(14, 4))
            path.move(to: p(14, 10));  path.addLine(to: p(21, 3))
            path.move(to: p(3, 21));   path.addLine(to: p(10, 14))

        // MARK: Domain glyphs

        case .trash2:
            // Source: lucide-icons/lucide · trash-2.svg
            // ("M3 6h18" + "M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"
            //  + "M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"
            //  + "line x1=10 x2=10 y1=11 y2=17"
            //  + "line x1=14 x2=14 y1=11 y2=17")
            path.move(to: p(3, 6));    path.addLine(to: p(21, 6))
            path.move(to: p(19, 6))
            path.addLine(to: p(19, 20))
            path.addQuadCurve(to: p(17, 22), control: p(19, 22))
            path.addLine(to: p(7, 22))
            path.addQuadCurve(to: p(5, 20), control: p(5, 22))
            path.addLine(to: p(5, 6))
            path.move(to: p(8, 6))
            path.addLine(to: p(8, 4))
            path.addQuadCurve(to: p(10, 2), control: p(8, 2))
            path.addLine(to: p(14, 2))
            path.addQuadCurve(to: p(16, 4), control: p(16, 2))
            path.addLine(to: p(16, 6))
            path.move(to: p(10, 11));  path.addLine(to: p(10, 17))
            path.move(to: p(14, 11));  path.addLine(to: p(14, 17))

        case .search:
            // Source: lucide-icons/lucide · search.svg
            // ("circle cx=11 cy=11 r=8" + "m21 21-4.3-4.3")
            path.addEllipse(in: CGRect(x: dx + 3 * s,
                                       y: dy + 3 * s,
                                       width:  16 * s,
                                       height: 16 * s))
            path.move(to: p(21, 21));  path.addLine(to: p(16.7, 16.7))

        case .folder:
            // Source: lucide-icons/lucide · folder.svg
            // ("M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9
            //   L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z")
            path.move(to: p(20, 20))
            path.addQuadCurve(to: p(22, 18), control: p(22, 20))
            path.addLine(to: p(22, 8))
            path.addQuadCurve(to: p(20, 6), control: p(22, 6))
            path.addLine(to: p(12.1, 6))
            path.addQuadCurve(to: p(10.41, 5.1), control: p(11.0, 5.6))
            path.addLine(to: p(9.6, 3.9))
            path.addQuadCurve(to: p(7.93, 3), control: p(8.7, 3))
            path.addLine(to: p(4, 3))
            path.addQuadCurve(to: p(2, 5), control: p(2, 3))
            path.addLine(to: p(2, 18))
            path.addQuadCurve(to: p(4, 20), control: p(2, 20))
            path.closeSubpath()

        case .archive:
            // Source: lucide-icons/lucide · archive.svg
            // ("rect x=2 y=4 w=20 h=5 rx=2"
            //  + "M4 9v9a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9"
            //  + "M10 13h4")
            let rect = CGRect(x: dx + 2 * s, y: dy + 4 * s, width: 20 * s, height: 5 * s)
            path.addPath(Path(roundedRect: rect, cornerRadius: 2 * s, style: .continuous))
            path.move(to: p(4, 9))
            path.addLine(to: p(4, 18))
            path.addQuadCurve(to: p(6, 20), control: p(4, 20))
            path.addLine(to: p(18, 20))
            path.addQuadCurve(to: p(20, 18), control: p(20, 20))
            path.addLine(to: p(20, 9))
            path.move(to: p(10, 13));  path.addLine(to: p(14, 13))

        case .messageCircle:
            // Source: lucide-icons/lucide · message-circle.svg
            // ("M7.9 20A9 9 0 1 0 4 16.1L2 22Z")
            path.move(to: p(7.9, 20))
            path.addArc(center: p(12, 11), radius: 9 * s,
                        startAngle: .degrees(115),
                        endAngle: .degrees(425),
                        clockwise: false)
            path.addLine(to: p(4, 16.1))
            path.addLine(to: p(2, 22))
            path.closeSubpath()

        case .globe:
            // Source: lucide-icons/lucide · globe.svg
            // circle r=10 + horizontal/vertical/diagonal ellipses to suggest
            // meridians and the equator.
            // ("circle r=10" + "path M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20"
            //  + "M2 12h20")
            let cx: CGFloat = 12, cy: CGFloat = 12
            path.addEllipse(in: CGRect(x: dx + (cx - 10) * s,
                                       y: dy + (cy - 10) * s,
                                       width:  20 * s, height: 20 * s))
            // Vertical meridian (lens shape, two halves)
            path.move(to: p(12, 2))
            path.addCurve(to: p(12, 22),
                          control1: p(5, 7), control2: p(5, 17))
            path.move(to: p(12, 2))
            path.addCurve(to: p(12, 22),
                          control1: p(19, 7), control2: p(19, 17))
            path.move(to: p(2, 12));   path.addLine(to: p(22, 12))

        case .paperclip:
            // Source: lucide-icons/lucide · paperclip.svg
            // ("M13.234 20.252 21 12.3 ...")
            // Simplified diagonal paperclip silhouette.
            path.move(to: p(21, 11))
            path.addLine(to: p(11.5, 20.5))
            path.addArc(center: p(8, 17), radius: 4.95 * s,
                        startAngle: .degrees(45),
                        endAngle: .degrees(225),
                        clockwise: false)
            path.addLine(to: p(15.5, 6.5))
            path.addArc(center: p(18, 9), radius: 3.54 * s,
                        startAngle: .degrees(225),
                        endAngle: .degrees(45),
                        clockwise: true)
            path.addLine(to: p(7, 17.5))
            path.addArc(center: p(7, 17), radius: 0.7 * s,
                        startAngle: .degrees(45),
                        endAngle: .degrees(225),
                        clockwise: false)
            path.addLine(to: p(15, 9))

        case .camera:
            // Source: lucide-icons/lucide · camera.svg
            // body rect with a "tab" on top (lens hood) + circle lens.
            // ("M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0
            //   2-2V9a2 2 0 0 0-2-2h-3l-2.5-3z" + "circle cx=12 cy=13 r=3")
            path.move(to: p(14.5, 4))
            path.addLine(to: p(9.5, 4))
            path.addLine(to: p(7, 7))
            path.addLine(to: p(4, 7))
            path.addQuadCurve(to: p(2, 9), control: p(2, 7))
            path.addLine(to: p(2, 18))
            path.addQuadCurve(to: p(4, 20), control: p(2, 20))
            path.addLine(to: p(20, 20))
            path.addQuadCurve(to: p(22, 18), control: p(22, 20))
            path.addLine(to: p(22, 9))
            path.addQuadCurve(to: p(20, 7), control: p(22, 7))
            path.addLine(to: p(17, 7))
            path.closeSubpath()
            path.addEllipse(in: CGRect(x: dx + 9 * s,
                                       y: dy + 10 * s,
                                       width: 6 * s, height: 6 * s))

        case .image:
            // Source: lucide-icons/lucide · image.svg
            // ("rect x=3 y=3 w=18 h=18 rx=2 ry=2"
            //  + "circle cx=9 cy=9 r=2"
            //  + "m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21")
            let r = CGRect(x: dx + 3 * s, y: dy + 3 * s, width: 18 * s, height: 18 * s)
            path.addPath(Path(roundedRect: r, cornerRadius: 2 * s, style: .continuous))
            path.addEllipse(in: CGRect(x: dx + 7 * s, y: dy + 7 * s,
                                       width: 4 * s, height: 4 * s))
            path.move(to: p(21, 15))
            path.addLine(to: p(17.91, 11.91))
            path.addQuadCurve(to: p(15.09, 11.91), control: p(16.5, 11.0))
            path.addLine(to: p(6, 21))

        case .images:
            // Source: lucide-icons/lucide · images.svg
            // ("path d=M18 22H4a2 2 0 0 1-2-2V6"
            //  + "path d=m22 13-1.296-1.296a2.41 2.41 0 0 0-3.408 0L11 18"
            //  + "circle cx=12 cy=8 r=2"
            //  + "rect width=16 height=16 x=6 y=2 rx=2")
            path.move(to: p(18, 22))
            path.addLine(to: p(4, 22))
            path.addQuadCurve(to: p(2, 20), control: p(2, 22))
            path.addLine(to: p(2, 6))
            path.move(to: p(22, 13))
            path.addLine(to: p(20.7, 11.7))
            path.addQuadCurve(to: p(17.29, 11.7), control: p(19, 10))
            path.addLine(to: p(11, 18))
            path.addEllipse(in: CGRect(x: dx + 10 * s, y: dy + 6 * s,
                                       width: 4 * s, height: 4 * s))
            let r2 = CGRect(x: dx + 6 * s, y: dy + 2 * s, width: 16 * s, height: 16 * s)
            path.addPath(Path(roundedRect: r2, cornerRadius: 2 * s, style: .continuous))

        case .imageOff:
            // Source: lucide-icons/lucide · image-off.svg
            // ("line x1=2 x2=22 y1=2 y2=22"
            //  + "path d=M10.41 10.41a2 2 0 1 1-2.83-2.83"
            //  + "line x1=13.5 x2=6 y1=13.5 y2=21"
            //  + "line x1=18 x2=21 y1=12 y2=15"
            //  + "path d=M3.59 3.59A1.99 1.99 0 0 0 3 5v14a2 2 0 0 0 2 2h14
            //   c.55 0 1.052-.22 1.41-.59"
            //  + "path d=M21 15V5a2 2 0 0 0-2-2H9")
            path.move(to: p(2, 2));    path.addLine(to: p(22, 22))
            path.move(to: p(10.41, 10.41))
            path.addArc(center: p(9, 9), radius: 2 * s,
                        startAngle: .degrees(45),
                        endAngle: .degrees(45 + 270),
                        clockwise: false)
            path.move(to: p(13.5, 13.5));  path.addLine(to: p(6, 21))
            path.move(to: p(18, 12));      path.addLine(to: p(21, 15))
            path.move(to: p(3.59, 3.59))
            path.addQuadCurve(to: p(3, 5), control: p(3, 4))
            path.addLine(to: p(3, 19))
            path.addQuadCurve(to: p(5, 21), control: p(3, 21))
            path.addLine(to: p(19, 21))
            path.addQuadCurve(to: p(20.41, 20.41), control: p(20, 21))
            path.move(to: p(21, 15))
            path.addLine(to: p(21, 5))
            path.addQuadCurve(to: p(19, 3), control: p(21, 3))
            path.addLine(to: p(9, 3))

        case .send:
            // Source: lucide-icons/lucide · send.svg (paper plane)
            // ("path d=M14.536 21.686a.5.5 0 0 0 .937-.024l6.5-19a.496.496 0
            //   0 0-.635-.635l-19 6.5a.5.5 0 0 0-.024.937l7.93 3.18a2 2 0 0 1
            //   1.112 1.11z" + "path d=m21.854 2.147-10.94 10.939")
            path.move(to: p(14.536, 21.686))
            path.addLine(to: p(21.5, 2.5))
            path.addLine(to: p(2.5, 9))
            path.addLine(to: p(10.43, 12.18))
            path.addLine(to: p(11.542, 13.292))
            path.closeSubpath()
            path.move(to: p(21.854, 2.147))
            path.addLine(to: p(10.914, 13.086))

        case .zap:
            // Source: lucide-icons/lucide · zap.svg
            // ("path d=M4 14a1 1 0 0 1-.78-1.63l9.9-10.2a.5.5 0 0 1 .86.46
            //   l-1.92 6.02A1 1 0 0 0 13 10h7a1 1 0 0 1 .78 1.63l-9.9 10.2
            //   a.5.5 0 0 1-.86-.46l1.92-6.02A1 1 0 0 0 11 14z")
            path.move(to: p(4, 14))
            path.addLine(to: p(13.12, 2.17))
            path.addLine(to: p(11.2, 8.19))
            path.addLine(to: p(13, 10))
            path.addLine(to: p(20, 10))
            path.addLine(to: p(10.88, 21.83))
            path.addLine(to: p(12.8, 15.81))
            path.addLine(to: p(11, 14))
            path.closeSubpath()

        case .star:
            // Source: lucide-icons/lucide · star.svg
            // 5-pointed star, classic geometry.
            // ("path d=M11.525 2.295a.53.53 0 0 1 .95 0l2.31 4.679a2.123 2.123
            //   0 0 0 1.595 1.16l5.166.756a.53.53 0 0 1 .294.904l-3.736 3.638
            //   a2.123 2.123 0 0 0-.611 1.878l.882 5.14a.53.53 0 0 1-.771.56
            //   l-4.618-2.428a2.122 2.122 0 0 0-1.973 0L6.396 21.01a.53.53 0
            //   0 1-.77-.56l.881-5.139a2.122 2.122 0 0 0-.611-1.879L2.16 9.795
            //   a.53.53 0 0 1 .294-.906l5.165-.755a2.122 2.122 0 0 0 1.597-1.16z")
            path.move(to: p(12, 2.5))
            path.addLine(to: p(14.78, 8.13))
            path.addLine(to: p(21, 9.04))
            path.addLine(to: p(16.5, 13.42))
            path.addLine(to: p(17.56, 19.62))
            path.addLine(to: p(12, 16.69))
            path.addLine(to: p(6.44, 19.62))
            path.addLine(to: p(7.5, 13.42))
            path.addLine(to: p(3, 9.04))
            path.addLine(to: p(9.22, 8.13))
            path.closeSubpath()

        case .clock:
            // Source: lucide-icons/lucide · clock.svg
            // ("circle cx=12 cy=12 r=10" + "polyline points=12,6 12,12 16,14")
            path.addEllipse(in: CGRect(x: dx + 2 * s, y: dy + 2 * s,
                                       width: 20 * s, height: 20 * s))
            path.move(to: p(12, 6))
            path.addLine(to: p(12, 12))
            path.addLine(to: p(16, 14))

        case .list:
            // Source: lucide-icons/lucide · list.svg
            // ("path d=M3 12h.01" + "path d=M3 18h.01" + "path d=M3 6h.01"
            //  + "path d=M8 12h13" + "path d=M8 18h13" + "path d=M8 6h13")
            for y: CGFloat in [6, 12, 18] {
                path.move(to: p(3, y));  path.addLine(to: p(3.01, y))
                path.move(to: p(8, y));  path.addLine(to: p(21, y))
            }

        case .listChecks:
            // Source: lucide-icons/lucide · list-checks.svg
            // ("path d=m3 17 2 2 4-4" + "path d=m3 7 2 2 4-4"
            //  + "path d=M13 6h8" + "path d=M13 12h8" + "path d=M13 18h8")
            path.move(to: p(3, 17));   path.addLine(to: p(5, 19)); path.addLine(to: p(9, 15))
            path.move(to: p(3, 7));    path.addLine(to: p(5, 9));  path.addLine(to: p(9, 5))
            path.move(to: p(13, 6));   path.addLine(to: p(21, 6))
            path.move(to: p(13, 12));  path.addLine(to: p(21, 12))
            path.move(to: p(13, 18));  path.addLine(to: p(21, 18))

        case .alignLeft:
            // Source: lucide-icons/lucide · align-left.svg
            // ("line x1=21 x2=3 y1=6 y2=6" + "line x1=15 x2=3 y1=12 y2=12"
            //  + "line x1=17 x2=3 y1=18 y2=18")
            path.move(to: p(3, 6));    path.addLine(to: p(21, 6))
            path.move(to: p(3, 12));   path.addLine(to: p(15, 12))
            path.move(to: p(3, 18));   path.addLine(to: p(17, 18))

        case .key:
            // Source: lucide-icons/lucide · key.svg
            // ("path d=m15.5 7.5 2.3 2.3a1 1 0 0 0 1.4 0l2.1-2.1a1 1 0 0 0
            //   0-1.4L19 4" + "path d=m21 2-9.6 9.6"
            //  + "circle cx=7.5 cy=15.5 r=5.5")
            path.move(to: p(15.5, 7.5))
            path.addLine(to: p(17.8, 9.8))
            path.addQuadCurve(to: p(19.2, 9.8), control: p(18.5, 10.5))
            path.addLine(to: p(21.3, 7.7))
            path.addQuadCurve(to: p(21.3, 6.3), control: p(22, 7))
            path.addLine(to: p(19, 4))
            path.move(to: p(21, 2));   path.addLine(to: p(11.4, 11.6))
            path.addEllipse(in: CGRect(x: dx + 2 * s, y: dy + 10 * s,
                                       width: 11 * s, height: 11 * s))

        case .link:
            // Source: lucide-icons/lucide · link.svg
            // Two interlocking rounded-rect halves with a cross-line.
            // Simplified faithful silhouette of the lucide link icon.
            // ("path d=M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07
            //   l-1.72 1.71"
            //  + "path d=M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07
            //   l1.71-1.71")
            path.move(to: p(10, 13))
            path.addArc(center: p(13.77, 9.23), radius: 5.33 * s,
                        startAngle: .degrees(135),
                        endAngle: .degrees(45),
                        clockwise: false)
            path.addLine(to: p(11.75, 4.18))
            path.move(to: p(14, 11))
            path.addArc(center: p(10.23, 14.77), radius: 5.33 * s,
                        startAngle: .degrees(-45),
                        endAngle: .degrees(225),
                        clockwise: false)
            path.addLine(to: p(12.25, 19.82))

        case .laptop:
            // Source: lucide-icons/lucide · laptop.svg
            // ("path d=M18 5a2 2 0 0 1 2 2v8.526a2 2 0 0 0 .212.897l1.068
            //   2.127a1 1 0 0 1-.9 1.45H3.62a1 1 0 0 1-.9-1.45l1.068-2.127
            //   A2 2 0 0 0 4 15.526V7a2 2 0 0 1 2-2z" + "M20.054 15.987H3.946")
            path.move(to: p(18, 5))
            path.addQuadCurve(to: p(20, 7), control: p(20, 5))
            path.addLine(to: p(20, 15.526))
            path.addLine(to: p(21.28, 18.55))
            path.addQuadCurve(to: p(20.38, 20), control: p(21.5, 20))
            path.addLine(to: p(3.62, 20))
            path.addQuadCurve(to: p(2.72, 18.55), control: p(2.5, 20))
            path.addLine(to: p(4, 15.526))
            path.addLine(to: p(4, 7))
            path.addQuadCurve(to: p(6, 5), control: p(4, 5))
            path.closeSubpath()
            path.move(to: p(3.946, 15.987))
            path.addLine(to: p(20.054, 15.987))

        case .scan:
            // Source: lucide-icons/lucide · scan.svg
            // Four corner brackets.
            // ("path d=M3 7V5a2 2 0 0 1 2-2h2"
            //  + "path d=M17 3h2a2 2 0 0 1 2 2v2"
            //  + "path d=M21 17v2a2 2 0 0 1-2 2h-2"
            //  + "path d=M7 21H5a2 2 0 0 1-2-2v-2")
            path.move(to: p(3, 7))
            path.addLine(to: p(3, 5))
            path.addQuadCurve(to: p(5, 3), control: p(3, 3))
            path.addLine(to: p(7, 3))
            path.move(to: p(17, 3))
            path.addLine(to: p(19, 3))
            path.addQuadCurve(to: p(21, 5), control: p(21, 3))
            path.addLine(to: p(21, 7))
            path.move(to: p(21, 17))
            path.addLine(to: p(21, 19))
            path.addQuadCurve(to: p(19, 21), control: p(21, 21))
            path.addLine(to: p(17, 21))
            path.move(to: p(7, 21))
            path.addLine(to: p(5, 21))
            path.addQuadCurve(to: p(3, 19), control: p(3, 21))
            path.addLine(to: p(3, 17))

        case .tornado:
            // Source: lucide-icons/lucide · tornado.svg
            // ("path d=M21 4H3" + "path d=M18 8H6"
            //  + "path d=M19 12H9" + "path d=M16 16h-6"
            //  + "path d=M11 20H9")
            path.move(to: p(3, 4));    path.addLine(to: p(21, 4))
            path.move(to: p(6, 8));    path.addLine(to: p(18, 8))
            path.move(to: p(9, 12));   path.addLine(to: p(19, 12))
            path.move(to: p(10, 16));  path.addLine(to: p(16, 16))
            path.move(to: p(9, 20));   path.addLine(to: p(11, 20))

        case .drama:
            // Source: lucide-icons/lucide · drama.svg
            // Theater masks, simplified to a single mask outline with eyes.
            // ("path d=M10 11h.01" + "path d=M14 6h.01" + "path d=M18 6h.01"
            //  + "path d=M6.5 13.1h.01" + "path d=M22 5c0 9-4 12-6 12s-6-3-6-12
            //   c0-2 2-3 6-3s6 1 6 3" + "path d=M17.4 9.9c-.8.8-2 .8-2.8 0"
            //  + "path d=M10.1 7.1C9 7.2 7.7 7.7 6 8.6c-3.5 2-4.7 3.9-3.7 5.6
            //   .6 1 5.5 4.8 9 1.5"
            //  + "path d=M9.1 16.5c.3-1.1 1.4-1.7 2.4-1.4")
            path.move(to: p(22, 5))
            path.addQuadCurve(to: p(16, 17), control: p(22, 17))
            path.addQuadCurve(to: p(10, 5),  control: p(10, 17))
            path.addQuadCurve(to: p(22, 5), control: p(10, 2))
            path.closeSubpath()
            // Eyes/mouth dots
            for (cx, cy) in [(14.0, 6.0), (18.0, 6.0)] {
                path.move(to: p(cx, cy));  path.addLine(to: p(cx + 0.01, cy))
            }
            path.move(to: p(17.4, 9.9))
            path.addQuadCurve(to: p(14.6, 9.9), control: p(16, 11.2))

        case .fileQuestion:
            // Source: lucide-icons/lucide · file-question.svg
            // ("path d=M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0
            //   2-2V8z" + "polyline points=14 2 14 8 20 8"
            //  + "path d=M10 10.3c.2-.4.5-.8.9-1a2.1 2.1 0 0 1 2.6.4c.3.4.5.8.5 1.3
            //   0 1.3-2 2-2 2"
            //  + "path d=M12 17h.01")
            path.move(to: p(14, 2))
            path.addLine(to: p(6, 2))
            path.addQuadCurve(to: p(4, 4), control: p(4, 2))
            path.addLine(to: p(4, 20))
            path.addQuadCurve(to: p(6, 22), control: p(4, 22))
            path.addLine(to: p(18, 22))
            path.addQuadCurve(to: p(20, 20), control: p(20, 22))
            path.addLine(to: p(20, 8))
            path.closeSubpath()
            path.move(to: p(14, 2))
            path.addLine(to: p(14, 8))
            path.addLine(to: p(20, 8))
            // Question mark
            path.move(to: p(10, 10.3))
            path.addQuadCurve(to: p(13.5, 10.7), control: p(11.4, 9.3))
            path.addQuadCurve(to: p(12, 14), control: p(14, 13))
            path.move(to: p(12, 17));  path.addLine(to: p(12.01, 17))

        case .squareDashed:
            // Source: lucide-icons/lucide · square-dashed.svg
            // Dashed square outline (8 short segments along the perimeter).
            let segments: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (5, 3, 6, 3),
                (10, 3, 14, 3),
                (18, 3, 19, 3),
                (21, 5, 21, 6),
                (21, 10, 21, 14),
                (21, 18, 21, 19),
                (19, 21, 18, 21),
                (14, 21, 10, 21),
                (6, 21, 5, 21),
                (3, 19, 3, 18),
                (3, 14, 3, 10),
                (3, 6, 3, 5)
            ]
            for (x1, y1, x2, y2) in segments {
                path.move(to: p(x1, y1));  path.addLine(to: p(x2, y2))
            }

        case .appWindow:
            // Source: lucide-icons/lucide · app-window.svg
            // ("rect x=2 y=4 w=20 h=16 rx=2"
            //  + "path d=M10 4v4" + "path d=M2 8h20" + "path d=M6 4v4")
            let r = CGRect(x: dx + 2 * s, y: dy + 4 * s,
                           width: 20 * s, height: 16 * s)
            path.addPath(Path(roundedRect: r, cornerRadius: 2 * s, style: .continuous))
            path.move(to: p(10, 4));   path.addLine(to: p(10, 8))
            path.move(to: p(2, 8));    path.addLine(to: p(22, 8))
            path.move(to: p(6, 4));    path.addLine(to: p(6, 8))

        case .workflow:
            // Source: lucide-icons/lucide · workflow.svg
            // ("rect x=3 y=3 w=8 h=8 rx=2"
            //  + "path d=M7 11v4a2 2 0 0 0 2 2h4"
            //  + "rect x=15 y=13 w=8 h=8 rx=2")
            let r1 = CGRect(x: dx + 3 * s, y: dy + 3 * s, width: 8 * s, height: 8 * s)
            path.addPath(Path(roundedRect: r1, cornerRadius: 2 * s, style: .continuous))
            path.move(to: p(7, 11))
            path.addLine(to: p(7, 15))
            path.addQuadCurve(to: p(9, 17), control: p(7, 17))
            path.addLine(to: p(13, 17))
            let r3 = CGRect(x: dx + 15 * s, y: dy + 13 * s, width: 8 * s, height: 8 * s)
            path.addPath(Path(roundedRect: r3, cornerRadius: 2 * s, style: .continuous))

        case .download:
            // Source: lucide-icons/lucide · download.svg
            // ("path d=M12 15V3" + "path d=M21 15v4a2 2 0 0 1-2 2H5
            //   a2 2 0 0 1-2-2v-4" + "m7 10 5 5 5-5")
            path.move(to: p(12, 3));   path.addLine(to: p(12, 15))
            path.move(to: p(21, 15));  path.addLine(to: p(21, 19))
            path.addQuadCurve(to: p(19, 21), control: p(21, 21))
            path.addLine(to: p(5, 21))
            path.addQuadCurve(to: p(3, 19), control: p(3, 21))
            path.addLine(to: p(3, 15))
            path.move(to: p(7, 10))
            path.addLine(to: p(12, 15))
            path.addLine(to: p(17, 10))

        case .share2:
            // Source: lucide-icons/lucide · share-2.svg
            // ("circle cx=18 cy=5 r=3" + "circle cx=6 cy=12 r=3"
            //  + "circle cx=18 cy=19 r=3"
            //  + "line x1=8.59 x2=15.42 y1=13.51 y2=17.49"
            //  + "line x1=15.41 x2=8.59 y1=6.51 y2=10.49")
            path.addEllipse(in: CGRect(x: dx + 15 * s, y: dy + 2 * s,
                                       width: 6 * s, height: 6 * s))
            path.addEllipse(in: CGRect(x: dx + 3 * s, y: dy + 9 * s,
                                       width: 6 * s, height: 6 * s))
            path.addEllipse(in: CGRect(x: dx + 15 * s, y: dy + 16 * s,
                                       width: 6 * s, height: 6 * s))
            path.move(to: p(8.59, 13.51));  path.addLine(to: p(15.42, 17.49))
            path.move(to: p(15.41, 6.51));  path.addLine(to: p(8.59, 10.49))

        case .inbox:
            // Source: lucide-icons/lucide · inbox.svg
            // ("polyline points=22 12 16 12 14 15 10 15 8 12 2 12"
            //  + "path d=M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6
            //   l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11Z")
            path.move(to: p(22, 12))
            path.addLine(to: p(16, 12))
            path.addLine(to: p(14, 15))
            path.addLine(to: p(10, 15))
            path.addLine(to: p(8, 12))
            path.addLine(to: p(2, 12))
            path.move(to: p(5.45, 5.11))
            path.addLine(to: p(2, 12))
            path.addLine(to: p(2, 18))
            path.addQuadCurve(to: p(4, 20), control: p(2, 20))
            path.addLine(to: p(20, 20))
            path.addQuadCurve(to: p(22, 18), control: p(22, 20))
            path.addLine(to: p(22, 12))
            path.addLine(to: p(18.55, 5.11))
            path.addQuadCurve(to: p(16.76, 4), control: p(17.7, 4))
            path.addLine(to: p(7.24, 4))
            path.addQuadCurve(to: p(5.45, 5.11), control: p(6.3, 4))
            path.closeSubpath()

        case .play:
            // Source: lucide-icons/lucide · play.svg
            // ("polygon points=6 3 20 12 6 21 6 3")
            path.move(to: p(6, 3))
            path.addLine(to: p(20, 12))
            path.addLine(to: p(6, 21))
            path.closeSubpath()

        case .pause:
            // Source: lucide-icons/lucide · pause.svg
            // ("rect x=14 y=4 w=4 h=16 rx=1" + "rect x=6 y=4 w=4 h=16 rx=1")
            let l = CGRect(x: dx + 6 * s, y: dy + 4 * s, width: 4 * s, height: 16 * s)
            let r = CGRect(x: dx + 14 * s, y: dy + 4 * s, width: 4 * s, height: 16 * s)
            path.addPath(Path(roundedRect: l, cornerRadius: 1 * s, style: .continuous))
            path.addPath(Path(roundedRect: r, cornerRadius: 1 * s, style: .continuous))

        case .square:
            // Source: lucide-icons/lucide · square.svg
            // ("rect x=3 y=3 w=18 h=18 rx=2 ry=2")
            let r = CGRect(x: dx + 3 * s, y: dy + 3 * s, width: 18 * s, height: 18 * s)
            path.addPath(Path(roundedRect: r, cornerRadius: 2 * s, style: .continuous))

        case .circleStop:
            // Source: lucide-icons/lucide · circle-stop.svg
            // ("circle cx=12 cy=12 r=10" + "rect x=9 y=9 w=6 h=6 rx=1")
            path.addEllipse(in: CGRect(x: dx + 2 * s, y: dy + 2 * s,
                                       width: 20 * s, height: 20 * s))
            let inner = CGRect(x: dx + 9 * s, y: dy + 9 * s, width: 6 * s, height: 6 * s)
            path.addPath(Path(roundedRect: inner, cornerRadius: 1 * s, style: .continuous))

        case .moon:
            // Source: lucide-icons/lucide · moon.svg
            // ("path d=M20.985 12.486a9 9 0 1 1-9.473-9.472c.405-.022.617.46.402.803
            //   a6 6 0 0 0 8.268 8.268c.344-.215.825-.004.803.401")
            path.move(to: p(20.985, 12.486))
            path.addArc(center: p(12, 12), radius: 9 * s,
                        startAngle: .degrees(3),
                        endAngle: .degrees(360 - 3),
                        clockwise: false)
            path.addQuadCurve(to: p(11.91, 4.32), control: p(12.32, 4.30))
            path.addArc(center: p(15.92, 8.32), radius: 5.66 * s,
                        startAngle: .degrees(180),
                        endAngle: .degrees(90),
                        clockwise: true)
            path.addQuadCurve(to: p(20.985, 12.486), control: p(20.66, 12.08))

        case .audioWaveform:
            // Source: lucide-icons/lucide · audio-waveform.svg
            // ("path d=M2 13a2 2 0 0 0 2-2V7a2 2 0 0 1 4 0v13a2 2 0 0 0 4 0V4
            //   a2 2 0 0 1 4 0v13a2 2 0 0 0 4 0v-4a2 2 0 0 1 2-2")
            path.move(to: p(2, 13))
            path.addQuadCurve(to: p(4, 11), control: p(4, 13))
            path.addLine(to: p(4, 7))
            path.addQuadCurve(to: p(8, 7), control: p(6, 5))
            path.addLine(to: p(8, 20))
            path.addQuadCurve(to: p(12, 20), control: p(10, 22))
            path.addLine(to: p(12, 4))
            path.addQuadCurve(to: p(16, 4), control: p(14, 2))
            path.addLine(to: p(16, 17))
            path.addQuadCurve(to: p(20, 17), control: p(18, 19))
            path.addLine(to: p(20, 13))
            path.addQuadCurve(to: p(22, 11), control: p(22, 13))

        case .triangleAlert:
            // Source: lucide-icons/lucide · triangle-alert.svg
            // ("path d=m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16
            //   a2 2 0 0 0 1.73-3" + "path d=M12 9v4" + "path d=M12 17h.01")
            path.move(to: p(21.73, 18))
            path.addLine(to: p(13.73, 4))
            path.addQuadCurve(to: p(10.25, 4), control: p(12, 3))
            path.addLine(to: p(2.25, 18))
            path.addQuadCurve(to: p(4, 21), control: p(2, 21))
            path.addLine(to: p(20, 21))
            path.addQuadCurve(to: p(21.73, 18), control: p(22, 21))
            path.move(to: p(12, 9));   path.addLine(to: p(12, 13))
            path.move(to: p(12, 17));  path.addLine(to: p(12.01, 17))

        case .circleAlert:
            // Source: lucide-icons/lucide · circle-alert.svg
            // ("circle cx=12 cy=12 r=10" + "line x1=12 x2=12 y1=8 y2=12"
            //  + "line x1=12 x2=12.01 y1=16 y2=16")
            path.addEllipse(in: CGRect(x: dx + 2 * s, y: dy + 2 * s,
                                       width: 20 * s, height: 20 * s))
            path.move(to: p(12, 8));   path.addLine(to: p(12, 12))
            path.move(to: p(12, 16));  path.addLine(to: p(12.01, 16))

        case .shieldAlert:
            // Source: lucide-icons/lucide · shield-alert.svg
            // ("path d=M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01
            //   C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72
            //   a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"
            //  + "path d=M12 8v4" + "path d=M12 16h.01")
            path.move(to: p(20, 13))
            path.addQuadCurve(to: p(12.34, 21.95), control: p(20, 19))
            path.addQuadCurve(to: p(11.67, 21.94), control: p(12, 22))
            path.addQuadCurve(to: p(4, 13), control: p(4, 19))
            path.addLine(to: p(4, 6))
            path.addQuadCurve(to: p(5, 5), control: p(4, 5))
            path.addQuadCurve(to: p(11.24, 2.28), control: p(8, 4))
            path.addQuadCurve(to: p(12.76, 2.28), control: p(12, 1.7))
            path.addQuadCurve(to: p(19, 5), control: p(16, 4))
            path.addQuadCurve(to: p(20, 6), control: p(20, 5))
            path.closeSubpath()
            path.move(to: p(12, 8));   path.addLine(to: p(12, 12))
            path.move(to: p(12, 16));  path.addLine(to: p(12.01, 16))

        case .info:
            // Source: lucide-icons/lucide · info.svg
            // ("circle cx=12 cy=12 r=10" + "path d=M12 16v-4"
            //  + "path d=M12 8h.01")
            path.addEllipse(in: CGRect(x: dx + 2 * s, y: dy + 2 * s,
                                       width: 20 * s, height: 20 * s))
            path.move(to: p(12, 12));  path.addLine(to: p(12, 16))
            path.move(to: p(12, 8));   path.addLine(to: p(12.01, 8))

        case .circleCheck:
            // Source: lucide-icons/lucide · circle-check.svg
            // ("circle cx=12 cy=12 r=10" + "path d=m9 12 2 2 4-4")
            path.addEllipse(in: CGRect(x: dx + 2 * s, y: dy + 2 * s,
                                       width: 20 * s, height: 20 * s))
            path.move(to: p(9, 12))
            path.addLine(to: p(11, 14))
            path.addLine(to: p(15, 10))

        case .circleX:
            // Source: lucide-icons/lucide · circle-x.svg
            // ("circle cx=12 cy=12 r=10" + "path d=m15 9-6 6"
            //  + "path d=m9 9 6 6")
            path.addEllipse(in: CGRect(x: dx + 2 * s, y: dy + 2 * s,
                                       width: 20 * s, height: 20 * s))
            path.move(to: p(15, 9));   path.addLine(to: p(9, 15))
            path.move(to: p(9, 9));    path.addLine(to: p(15, 15))

        case .zapOff:
            // Source: lucide-icons/lucide · zap-off.svg
            // Lightning bolt with a diagonal slash through it.
            // Approximation: zap path + line "M2 2 22 22".
            path.move(to: p(2, 2));    path.addLine(to: p(22, 22))
            path.move(to: p(10.513, 4.856))
            path.addLine(to: p(13.12, 2.17))
            path.addLine(to: p(11.2, 8.19))
            path.addLine(to: p(13, 10))
            path.addLine(to: p(20, 10))
            path.addLine(to: p(10.88, 21.83))
            path.addLine(to: p(12.8, 15.81))
            path.addLine(to: p(11, 14))
            path.addLine(to: p(4, 14))

        case .eye:
            // Source: lucide-icons/lucide · eye.svg
            // ("path d=M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1
            //   19.876 0 1 1 0 0 1 0 .696 10.75 10.75 0 0 1-19.876 0"
            //  + "circle cx=12 cy=12 r=3")
            path.move(to: p(2.062, 12.348))
            path.addQuadCurve(to: p(2.062, 11.652), control: p(2, 12))
            path.addQuadCurve(to: p(21.938, 11.652), control: p(12, 1))
            path.addQuadCurve(to: p(21.938, 12.348), control: p(22, 12))
            path.addQuadCurve(to: p(2.062, 12.348), control: p(12, 23))
            path.closeSubpath()
            path.addEllipse(in: CGRect(x: dx + 9 * s, y: dy + 9 * s,
                                       width: 6 * s, height: 6 * s))

        case .eyeOff:
            // Source: lucide-icons/lucide · eye-off.svg
            // ("path d=m15 18-.722-3.25"
            //  + "path d=M2 8a10.645 10.645 0 0 0 20 0"
            //  + "path d=m20 15-1.726-2.05"
            //  + "path d=m4 15 1.726-2.05"
            //  + "path d=m9 18 .722-3.25")
            path.move(to: p(15, 18));     path.addLine(to: p(14.278, 14.75))
            path.move(to: p(2, 8))
            path.addQuadCurve(to: p(22, 8), control: p(12, 22))
            path.move(to: p(20, 15));     path.addLine(to: p(18.274, 12.95))
            path.move(to: p(4, 15));      path.addLine(to: p(5.726, 12.95))
            path.move(to: p(9, 18));      path.addLine(to: p(9.722, 14.75))
        }
        return path
    }
}
