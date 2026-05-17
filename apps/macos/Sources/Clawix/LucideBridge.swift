import SwiftUI
import LucideIcon

// Lucide-side glue layer for SF Symbol-named call sites.
//
// `Image(lucide: .chevron_down)` is the canonical way to render a Lucide
// icon: it goes through the asset catalog the package ships, so the
// existing SwiftUI Image modifiers (`.font`, `.foregroundStyle`,
// `.symbolRenderingMode`, `.imageScale`, etc.) all work like a normal
// SF Symbol.
//
// This file adds two small conveniences:
//   1. `LucideIcon.sfMapped(_:)` — String -> LucideIcon lookup for sites
//      where the icon name is computed at runtime (settings categories,
//      plugin metadata, permission modes) and was historically stored as
//      an SF Symbol literal.
//   2. `Image(lucideOrSystem:)` — drop-in replacement for the dynamic
//      `Image(systemName: variable)` pattern. Falls through to a real
//      SF Symbol when the name has no Lucide equivalent (e.g. genuine
//      OS-level glyphs like `command` and `return` for keyboard
//      shortcut hints).
//
// The mapping table is intentionally exhaustive for every SF Symbol the
// project used before the Lucide migration. New mappings are added here,
// not at call sites.

extension LucideIcon {
    static func sfMapped(_ symbol: String) -> LucideIcon? {
        switch symbol {
        case "chevron.down":  return .chevron_down
        case "chevron.up":    return .chevron_up
        case "chevron.left":  return .chevron_left
        case "chevron.right": return .chevron_right
        case "xmark":         return .x
        case "plus":          return .plus
        case "minus":         return .minus
        case "checkmark":     return .check
        case "ellipsis":      return .ellipsis

        case "arrow.up":      return .arrow_up
        case "arrow.down":    return .arrow_down
        case "arrow.left":    return .arrow_left
        case "arrow.right":   return .arrow_right
        case "arrow.up.right": return .arrow_up_right
        case "arrow.up.right.square": return .square_arrow_out_up_right
        case "arrow.right.to.line": return .arrow_right_to_line
        case "arrow.down.to.line":  return .arrow_down_to_line
        case "arrow.down.circle":   return .arrow_down
        case "arrow.uturn.backward": return .undo_2
        case "arrow.clockwise":      return .rotate_cw
        case "arrow.counterclockwise": return .rotate_ccw
        case "arrow.triangle.2.circlepath": return .refresh_cw
        case "arrow.up.left.and.arrow.down.right": return .maximize_2
        case "arrow.down.right.and.arrow.up.left": return .minimize_2

        case "trash":            return .trash_2
        case "magnifyingglass":  return .search
        case "folder", "folder.fill": return .folder
        case "archivebox":       return .archive
        case "bubble.left":      return .message_circle
        case "globe", "globe.americas.fill": return .globe
        case "paperclip":        return .paperclip
        case "camera", "camera.fill": return .camera
        case "photo":            return .image
        case "photo.on.rectangle.angled": return .images
        case "photo.badge.exclamationmark": return .image_off
        case "paperplane", "paperplane.fill": return .send
        case "bolt", "bolt.fill": return .zap
        case "bolt.slash", "bolt.slash.fill": return .zap_off
        case "star", "star.fill": return .star
        case "clock":            return .clock
        case "list.bullet":      return .list
        case "checklist":        return .list_checks
        case "text.alignleft":   return .text_align_start
        case "key.viewfinder":   return .key
        case "link", "link.circle": return .link
        case "laptopcomputer":   return .laptop
        case "viewfinder":       return .scan
        case "tornado":          return .tornado
        case "theatermasks":     return .drama
        case "doc.questionmark": return .file_question_mark
        case "questionmark.square.dashed", "app.dashed": return .square_dashed
        case "app":              return .app_window
        case "point.3.connected.trianglepath.dotted": return .workflow
        case "square.and.arrow.down": return .download
        case "square.and.arrow.up":   return .share_2
        case "tray.and.arrow.down":   return .inbox
        case "play", "play.fill":     return .play
        case "pause", "pause.fill":   return .pause
        case "stop.fill":             return .square
        case "stop.circle", "stop.circle.fill": return .circle_stop
        case "moon", "moon.zzz":      return .moon
        case "waveform":              return .audio_waveform
        case "exclamationmark.triangle",
             "exclamationmark.triangle.fill": return .triangle_alert
        case "exclamationmark.circle",
             "exclamationmark.circle.fill": return .circle_alert
        case "exclamationmark.shield",
             "exclamationmark.shield.fill": return .shield_alert
        case "exclamationmark.applewatch": return .circle_alert
        case "info.circle", "info.circle.fill": return .info
        case "checkmark.circle", "checkmark.circle.fill": return .circle_check
        case "xmark.circle", "xmark.circle.fill": return .circle_x
        case "circle":            return .circle_dot
        case "eye":               return .eye
        case "eye.slash":         return .eye_off
        case "eyeglasses", "eyeglasses.slash": return .glasses
        default: return nil
        }
    }
}

extension Image {
    /// Drop-in replacement for `Image(systemName: name)` where `name` is
    /// computed at runtime. Renders a Lucide custom SF Symbol when the
    /// name has a known Lucide equivalent; falls back to the system
    /// symbol otherwise (e.g. `command` and `return` for keyboard
    /// shortcut hints, where the platform glyph is the right answer).
    init(lucideOrSystem name: String) {
        if let icon = LucideIcon.sfMapped(name) {
            self.init(lucide: icon)
        } else {
            self.init(systemName: name)
        }
    }
}
