import SwiftUI

// ChatGPT-iOS-inspired identity, rebuilt for iOS 26 Liquid Glass.
// The desktop Clawix stays on its dense dark-gray surfaces; the
// iPhone companion intentionally diverges because iOS 26 reads
// better with refractive glass capsules over a pure black canvas
// than with stacked opaque grays.

enum Palette {
    static let background    = Color.black
    static let surface       = Color(white: 0.10)
    static let cardFill      = Color.white.opacity(0.06)
    static let cardHover     = Color.white.opacity(0.10)
    static let border        = Color.white.opacity(0.10)
    static let borderSubtle  = Color.white.opacity(0.06)
    static let popupStroke   = Color.white.opacity(0.10)
    static let popupStrokeWidth: CGFloat = 0.5
    static let selFill       = Color(white: 0.28)
    static let textPrimary   = Color.white
    static let textSecondary = Color(white: 0.65)
    static let textTertiary  = Color(white: 0.45)

    // ChatGPT-style user message bubble: light, almost white, with
    // dark text. The contrast against the assistant's bare-text
    // response is what gives the conversation its rhythm.
    static let userBubbleFill = Color(white: 0.92)
    static let userBubbleText = Color(white: 0.05)

    // Soft-blue used at the right edge of a chat row whose last
    // assistant turn finished while the user wasn't looking. Same
    // hue as the desktop's `Palette.pastelBlue` so the unread cue
    // reads as one cross-platform language.
    static let unreadDot = Color(red: 0.45, green: 0.65, blue: 1.0)
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

// Tuned for iOS 26 Liquid Glass: pill heights are ~50pt so the
// refraction has room to read, the composer reaches ~64pt for a
// chunky tappable surface, and the top bar reserves enough room
// for both. Bigger than the original mac-port values on purpose.
enum AppLayout {
    static let screenHorizontalPadding: CGFloat = 16
    static let screenTopPadding: CGFloat        = 8
    static let cardCornerRadius: CGFloat        = 20
    static let chipCornerRadius: CGFloat        = 12
    static let buttonCornerRadius: CGFloat      = 16
    static let cardSpacing: CGFloat             = 12
    static let listRowVerticalPadding: CGFloat  = 14
    static let composerCornerRadius: CGFloat    = 32
    static let userBubbleRadius: CGFloat        = 24
    static let topBarPillHeight: CGFloat        = 50
    static let topBarReservedHeight: CGFloat    = 64
    static let composerReservedHeight: CGFloat  = 110
}

enum Typography {
    static let titleFont       = BodyFont.system(size: 22, weight: .semibold)
    static let bodyFont        = BodyFont.system(size: 16)
    static let bodyEmphasized  = BodyFont.system(size: 16, weight: .medium)
    static let chatBodyFont    = BodyFont.system(size: 16.5)
    static let secondaryFont   = BodyFont.system(size: 14)
    static let captionFont     = BodyFont.system(size: 12)
    static let monoFont        = BodyFont.system(size: 14, design: .monospaced)
}
