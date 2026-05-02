import SwiftUI

// MARK: - Hover hint
//
// Custom hover-tooltip system used across the app for icon-only or otherwise
// abstract controls. Replaces SwiftUI's `.help(...)` (which renders the OS
// native NSTooltip and cannot be styled to match the rest of the app chrome).
//
// Behaviour:
// - Appears only after the cursor has been parked on the control for
//   `HoverHintConfig.delay` (1.5s by default), like macOS NSTooltips.
// - Single-line, capsule, dark fill, thin opaque border, soft shadow.
// - Always squircle (`.continuous`), per the project standard.
// - Renders as an overlay on the control itself (no global anchor wiring), so
//   any view can opt in with a single `.hoverHint("...")` call.

enum HoverHintPlacement {
    case above
    case below
    case leading   // chip floats to the left of the control
    case trailing  // chip floats to the right of the control
}

enum HoverHintConfig {
    static let delay: TimeInterval        = 1.5
    static let gap: CGFloat               = 8
    static let cornerRadius: CGFloat      = 7
    static let fontSize: CGFloat          = 11
    static let textColor                  = Color(white: 0.98)
    static let fill                       = Color(white: 0.18)
    static let stroke                     = Color.white.opacity(0.22)
    static let strokeWidth: CGFloat       = 0.6
    static let shadow                     = Color.black.opacity(0.30)
    static let shadowRadius: CGFloat      = 8
    static let shadowOffsetY: CGFloat     = 3
    static let appearAnimation            = Animation.easeOut(duration: 0.14)
    static let disappearAnimation         = Animation.easeOut(duration: 0.10)
}

struct HoverHintBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: HoverHintConfig.fontSize))
            .foregroundColor(HoverHintConfig.textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: HoverHintConfig.cornerRadius, style: .continuous)
                    .fill(HoverHintConfig.fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: HoverHintConfig.cornerRadius, style: .continuous)
                            .stroke(HoverHintConfig.stroke, lineWidth: HoverHintConfig.strokeWidth)
                    )
                    .shadow(color: HoverHintConfig.shadow,
                            radius: HoverHintConfig.shadowRadius,
                            x: 0, y: HoverHintConfig.shadowOffsetY)
            )
            .fixedSize()
    }
}

private struct HoverHintModifier: ViewModifier {
    let text: String
    let placement: HoverHintPlacement

    @State private var visible = false
    @State private var pending: DispatchWorkItem?
    @State private var bubbleSize: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                pending?.cancel()
                pending = nil
                if hovering {
                    let item = DispatchWorkItem {
                        withAnimation(HoverHintConfig.appearAnimation) {
                            visible = true
                        }
                    }
                    pending = item
                    DispatchQueue.main.asyncAfter(deadline: .now() + HoverHintConfig.delay,
                                                  execute: item)
                } else {
                    withAnimation(HoverHintConfig.disappearAnimation) {
                        visible = false
                    }
                }
            }
            .overlay(alignment: overlayAlignment) {
                if visible {
                    HoverHintBubble(text: text)
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .preference(key: HoverHintSizeKey.self, value: geo.size)
                            }
                        )
                        .onPreferenceChange(HoverHintSizeKey.self) { bubbleSize = $0 }
                        .offset(x: offsetX, y: offsetY)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .zIndex(999)
                }
            }
    }

    private var overlayAlignment: Alignment {
        switch placement {
        case .above:    return .top
        case .below:    return .bottom
        case .leading:  return .leading
        case .trailing: return .trailing
        }
    }

    private var offsetY: CGFloat {
        switch placement {
        case .above:    return -(bubbleSize.height + HoverHintConfig.gap)
        case .below:    return bubbleSize.height + HoverHintConfig.gap
        default:        return 0
        }
    }

    private var offsetX: CGFloat {
        switch placement {
        case .leading:  return -(bubbleSize.width + HoverHintConfig.gap)
        case .trailing: return bubbleSize.width + HoverHintConfig.gap
        default:        return 0
        }
    }
}

private struct HoverHintSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

extension View {
    /// Show a styled hover tooltip above (or below) the control after a
    /// 1.5s hover delay. Use for icon-only buttons or controls whose meaning
    /// is not self-evident.
    ///
    /// Default is `.above` so the hint never sits on top of the click target
    /// or the content the user is reading next to the control.
    ///
    /// Replaces SwiftUI's native `.help(...)` modifier so the chrome matches
    /// the rest of the app.
    func hoverHint(_ text: String, placement: HoverHintPlacement = .above) -> some View {
        modifier(HoverHintModifier(text: text, placement: placement))
    }
}
