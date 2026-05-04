import SwiftUI

// This iOS companion is deliberately dark-first: it is a remote
// control for the macOS Clawix app and inherits its identity.
// Background colors match the desktop palette so a user switching
// screens doesn't feel they are using a different product.
//
// Tokens here mirror `apps/macos/Sources/Clawix/ContentView.swift`
// `Palette` and `MenuStyle`. Values come straight from the desktop
// canon. When updating, update both sides.

enum Palette {
    static let background    = Color(white: 0.04)
    static let surface       = Color(white: 0.10)
    static let cardFill      = Color(white: 0.14)
    static let cardHover     = Color(white: 0.17)
    static let border        = Color(white: 0.20)
    static let borderSubtle  = Color(white: 0.15)
    static let popupStroke   = Color.white.opacity(0.10)
    static let popupStrokeWidth: CGFloat = 0.5
    static let selFill       = Color(white: 0.28)
    static let textPrimary   = Color.white
    static let textSecondary = Color(white: 0.55)
    static let textTertiary  = Color(white: 0.38)
}

enum MenuStyle {
    static let cornerRadius: CGFloat        = 12
    static let fill                         = Color(white: 0.135).opacity(0.92)
    static let shadowColor                  = Color.black.opacity(0.40)
    static let shadowRadius: CGFloat        = 18
    static let shadowOffsetY: CGFloat       = 10
    static let rowVerticalPadding: CGFloat  = 12
    static let rowHorizontalPadding: CGFloat = 16
    static let rowText                      = Color(white: 0.94)
    static let rowIcon                      = Color(white: 0.86)
    static let rowSubtle                    = Color(white: 0.55)
    static let dividerColor                 = Color.white.opacity(0.06)
    static let openAnimation                = Animation.easeOut(duration: 0.20)
}

// Mobile-specific spacing and radii. Mac values are dense (7-9pt
// vertical row padding); on iOS we breathe a bit more for thumb
// targets while keeping the typography compact.
enum Layout {
    static let screenHorizontalPadding: CGFloat = 16
    static let screenTopPadding: CGFloat        = 8
    static let cardCornerRadius: CGFloat        = 16
    static let chipCornerRadius: CGFloat        = 12
    static let buttonCornerRadius: CGFloat      = 14
    static let cardSpacing: CGFloat             = 12
    static let listRowVerticalPadding: CGFloat  = 14
    static let composerCornerRadius: CGFloat    = 22
}

enum Typography {
    static let titleFont       = Font.system(size: 20, weight: .semibold)
    static let bodyFont        = Font.system(size: 15)
    static let bodyEmphasized  = Font.system(size: 15, weight: .medium)
    static let secondaryFont   = Font.system(size: 13)
    static let captionFont     = Font.system(size: 12)
    static let monoFont        = Font.system(size: 14, design: .monospaced)
}
