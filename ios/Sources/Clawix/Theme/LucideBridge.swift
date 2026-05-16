import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import CoreText

/// Lucide icon registry. Renders glyphs from the official Lucide font
/// (`lucide.ttf`, bundled in Resources/Fonts) via `Text + Font.custom`.
///
/// We tried `lcandy2/LucideIcon` (SVG -> custom SF Symbol asset catalog
/// via swiftdraw): the catalog compiled cleanly but `UIImage(named:in:)`
/// always returned nil at runtime, so the icons rendered as empty views.
/// The font path is bulletproof: SwiftUI Text + Font.custom is the same
/// path Manrope and PlusJakartaSans already use in this app, so we are
/// not introducing a new code path.
///
/// Usage:
///
///     LucideIcon(.chevronDown, size: 13)
///         .foregroundColor(Color(white: 0.86))
///
/// `.foregroundColor` / `.foregroundStyle` work because this is a
/// `Text` underneath. `.font(.system(...))` set on the call site is
/// IGNORED — pass the size explicitly via the `size:` parameter.
struct LucideIcon: View {
    enum Kind {
        case chevronDown
        case chevronUp
        case chevronLeft
        case chevronRight
        case x
        case plus
        case minus
        case check
        case ellipsis
        case arrowUp
        case arrowDown
        case arrowLeft
        case arrowRight
        case arrowUpRight
        case squareArrowOutUpRight
        case arrowRightToLine
        case arrowDownToLine
        case undo2
        case rotateCw
        case rotateCcw
        case refreshCw
        case maximize2
        case minimize2
        case trash2
        case search
        case folder
        case archive
        case messageCircle
        case globe
        case paperclip
        case camera
        case image
        case images
        case imageOff
        case send
        case zap
        case zapOff
        case star
        case clock
        case list
        case listChecks
        case textAlignStart
        case key
        case link
        case laptop
        case scan
        case tornado
        case drama
        case fileQuestionMark
        case squareDashed
        case appWindow
        case workflow
        case download
        case share2
        case inbox
        case play
        case pause
        case square
        case circleStop
        case moon
        case audioWaveform
        case triangleAlert
        case circleAlert
        case shieldAlert
        case info
        case circleCheck
        case circleX
        case circleDot
        case eye
        case eyeOff
        case glasses

        var codepoint: String {
            switch self {
            case .chevronDown: return "\u{e06d}"
            case .chevronUp: return "\u{e070}"
            case .chevronLeft: return "\u{e06e}"
            case .chevronRight: return "\u{e06f}"
            case .x: return "\u{e1b2}"
            case .plus: return "\u{e13d}"
            case .minus: return "\u{e11c}"
            case .check: return "\u{e06c}"
            case .ellipsis: return "\u{e0b6}"
            case .arrowUp: return "\u{e04a}"
            case .arrowDown: return "\u{e042}"
            case .arrowLeft: return "\u{e048}"
            case .arrowRight: return "\u{e049}"
            case .arrowUpRight: return "\u{e04d}"
            case .squareArrowOutUpRight: return "\u{e5a4}"
            case .arrowRightToLine: return "\u{e459}"
            case .arrowDownToLine: return "\u{e455}"
            case .undo2: return "\u{e2a1}"
            case .rotateCw: return "\u{e149}"
            case .rotateCcw: return "\u{e148}"
            case .refreshCw: return "\u{e145}"
            case .maximize2: return "\u{e113}"
            case .minimize2: return "\u{e11b}"
            case .trash2: return "\u{e18e}"
            case .search: return "\u{e151}"
            case .folder: return "\u{e0d7}"
            case .archive: return "\u{e041}"
            case .messageCircle: return "\u{e116}"
            case .globe: return "\u{e0e8}"
            case .paperclip: return "\u{e12d}"
            case .camera: return "\u{e064}"
            case .image: return "\u{e0f6}"
            case .images: return "\u{e5c4}"
            case .imageOff: return "\u{e1c0}"
            case .send: return "\u{e152}"
            case .zap: return "\u{e1b4}"
            case .zapOff: return "\u{e1b5}"
            case .star: return "\u{e176}"
            case .clock: return "\u{e087}"
            case .list: return "\u{e106}"
            case .listChecks: return "\u{e1d0}"
            case .textAlignStart: return "\u{e185}"
            case .key: return "\u{e0fd}"
            case .link: return "\u{e102}"
            case .laptop: return "\u{e1cd}"
            case .scan: return "\u{e257}"
            case .tornado: return "\u{e218}"
            case .drama: return "\u{e521}"
            case .fileQuestionMark: return "\u{e322}"
            case .squareDashed: return "\u{e1cb}"
            case .appWindow: return "\u{e426}"
            case .workflow: return "\u{e425}"
            case .download: return "\u{e0b2}"
            case .share2: return "\u{e156}"
            case .inbox: return "\u{e0f7}"
            case .play: return "\u{e13c}"
            case .pause: return "\u{e12e}"
            case .square: return "\u{e167}"
            case .circleStop: return "\u{e083}"
            case .moon: return "\u{e11e}"
            case .audioWaveform: return "\u{e55b}"
            case .triangleAlert: return "\u{e193}"
            case .circleAlert: return "\u{e077}"
            case .shieldAlert: return "\u{e1fe}"
            case .info: return "\u{e0f9}"
            case .circleCheck: return "\u{e226}"
            case .circleX: return "\u{e084}"
            case .circleDot: return "\u{e345}"
            case .eye: return "\u{e0ba}"
            case .eyeOff: return "\u{e0bb}"
            case .glasses: return "\u{e20d}"
            }
        }
    }

    let kind: Kind
    var size: CGFloat

    init(_ kind: Kind, size: CGFloat = 16) {
        self.kind = kind
        self.size = size
    }

    var body: some View {
        Text(kind.codepoint)
            .font(.custom("lucide", size: size))
            // The font's glyph metrics include vertical padding; cap the
            // line height to the rendered size so the icon does not push
            // surrounding rows apart.
            .frame(width: size, height: size)
    }

    // Font registration: iOS loads `lucide.ttf` at process start via
    // `UIAppFonts` in Info.plist; macOS loads it via `BodyFont.register()`
    // which iterates every `.ttf` in `Bundle.module` (including
    // `Resources/Fonts/lucide.ttf`). No per-view registration needed.

    /// Maps an SF Symbol name to a Lucide kind. Used by the
    /// `auto(_:)` helper at sites where the icon name is computed at
    /// runtime (settings categories, plugin metadata, permission modes).
    static func sfMapped(_ symbol: String) -> Kind? {
        switch symbol {
        case "chevron.down":  return .chevronDown
        case "chevron.up":    return .chevronUp
        case "chevron.left":  return .chevronLeft
        case "chevron.right": return .chevronRight
        case "xmark":         return .x
        case "plus":          return .plus
        case "minus":         return .minus
        case "checkmark":     return .check
        case "ellipsis":      return .ellipsis

        case "arrow.up":      return .arrowUp
        case "arrow.down":    return .arrowDown
        case "arrow.left":    return .arrowLeft
        case "arrow.right":   return .arrowRight
        case "arrow.up.right": return .arrowUpRight
        case "arrow.up.right.square": return .squareArrowOutUpRight
        case "arrow.right.to.line": return .arrowRightToLine
        case "arrow.down.to.line":  return .arrowDownToLine
        case "arrow.down.circle":   return .arrowDown
        case "arrow.uturn.backward": return .undo2
        case "arrow.clockwise":      return .rotateCw
        case "arrow.counterclockwise": return .rotateCcw
        case "arrow.triangle.2.circlepath": return .refreshCw
        case "arrow.up.left.and.arrow.down.right": return .maximize2
        case "arrow.down.right.and.arrow.up.left": return .minimize2

        case "trash":            return .trash2
        case "magnifyingglass":  return .search
        case "folder", "folder.fill": return .folder
        case "archivebox":       return .archive
        case "bubble.left":      return .messageCircle
        case "globe", "globe.americas.fill": return .globe
        case "paperclip":        return .paperclip
        case "camera", "camera.fill": return .camera
        case "photo":            return .image
        case "photo.on.rectangle.angled": return .images
        case "photo.badge.exclamationmark": return .imageOff
        case "paperplane", "paperplane.fill": return .send
        case "bolt", "bolt.fill": return .zap
        case "bolt.slash", "bolt.slash.fill": return .zapOff
        case "star", "star.fill": return .star
        case "clock":            return .clock
        case "list.bullet":      return .list
        case "checklist":        return .listChecks
        case "text.alignleft":   return .textAlignStart
        case "key.viewfinder":   return .key
        case "link", "link.circle": return .link
        case "laptopcomputer":   return .laptop
        case "viewfinder":       return .scan
        case "tornado":          return .tornado
        case "theatermasks":     return .drama
        case "doc.questionmark": return .fileQuestionMark
        case "questionmark.square.dashed", "app.dashed": return .squareDashed
        case "app":              return .appWindow
        case "point.3.connected.trianglepath.dotted": return .workflow
        case "square.and.arrow.down": return .download
        case "square.and.arrow.up":   return .share2
        case "tray.and.arrow.down":   return .inbox
        case "play", "play.fill":     return .play
        case "pause", "pause.fill":   return .pause
        case "stop.fill":             return .square
        case "stop.circle", "stop.circle.fill": return .circleStop
        case "moon", "moon.zzz":      return .moon
        case "waveform":              return .audioWaveform
        case "exclamationmark.triangle",
             "exclamationmark.triangle.fill": return .triangleAlert
        case "exclamationmark.circle",
             "exclamationmark.circle.fill": return .circleAlert
        case "exclamationmark.shield",
             "exclamationmark.shield.fill": return .shieldAlert
        case "exclamationmark.applewatch": return .circleAlert
        case "info.circle", "info.circle.fill": return .info
        case "checkmark.circle", "checkmark.circle.fill": return .circleCheck
        case "xmark.circle", "xmark.circle.fill": return .circleX
        case "circle":            return .circleDot
        case "eye":               return .eye
        case "eye.slash":         return .eyeOff
        case "eyeglasses", "eyeglasses.slash": return .glasses
        default: return nil
        }
    }

    /// Resolves an SF Symbol-style name at runtime: renders a Lucide
    /// glyph for known mappings, falls back to `Image(systemName:)` for
    /// genuinely OS-level chrome (`command`, `return` for keyboard
    /// shortcut hints) or any name we have not mapped yet. Returns
    /// `AnyView` because the two branches produce different concrete
    /// view types.
    @ViewBuilder
    static func auto(_ systemName: String, size: CGFloat = 16) -> some View {
        if let kind = LucideIcon.sfMapped(systemName) {
            LucideIcon(kind, size: size)
        } else {
            Image(systemName: systemName)
                .font(.system(size: size))
        }
    }
}

extension Image {
    /// Compatibility shim used by call sites that pass an SF Symbol
    /// name string for parity with platforms that haven't been migrated
    /// to the `LucideIcon` enum yet. Routes everything through
    /// `Image(systemName:)` for now; if a richer Lucide-as-Image
    /// rendering is wanted later, swap this body for an `NSImage`-backed
    /// glyph render based on `LucideIcon.sfMapped(name)`. The function
    /// is intentionally `init` (not a static helper) so callers using
    /// `Image(lucideOrSystem: …).font(…)` chain modifiers as expected.
    init(lucideOrSystem name: String) {
        self.init(systemName: name)
    }
}
