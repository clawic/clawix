import SwiftUI

// iOS 26 Liquid Glass surfaces. The whole iPhone companion is built
// on top of `glassEffect(in:)` for capsules / circles / rounded rects
// so chrome reads as real refractive glass over the transcript, not
// as a flat translucent panel. Use `GlassEffectContainer` whenever
// you place multiple glass shapes next to each other so they morph
// together when they animate (top-bar clusters in particular).

extension View {
    /// Wraps `self` in a glass capsule. Default Liquid Glass tint;
    /// pass `.regular.tint(...)` if a CTA needs a brand-colored glass.
    func glassCapsule() -> some View {
        glassEffect(.regular, in: Capsule(style: .continuous))
    }

    /// Wraps `self` in a glass rounded rect with a continuous squircle.
    func glassRounded(radius: CGFloat) -> some View {
        glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Wraps `self` in a glass circle.
    func glassCircle() -> some View {
        glassEffect(.regular, in: Circle())
    }
}

// Round icon-only button used at the corners of the top bar.
//
// History: we used to render this with `.glassEffect(.regular, in: Circle())`
// applied AFTER `.buttonStyle(.plain)`, but on iOS 26 that combination
// silently swallows the tap on a real device — the visual shows up
// fine, the highlight runs, but the Button's action never fires.
// Putting the glass background INSIDE the label (so it sits underneath
// the Button's gesture-listening frame, not on top of it) and pinning
// the hit-test area with an explicit `.contentShape(Circle())` makes
// the tap reliable across the whole top bar.
struct GlassIconButton: View {
    private enum Glyph {
        case system(name: String, size: CGFloat, weight: Font.Weight)
        case custom(AnyView)
    }

    private let glyph: Glyph
    private let size: CGFloat
    private let tint: Color?
    private let action: () -> Void

    init(
        systemName: String,
        size: CGFloat = 44,
        iconSize: CGFloat = 17,
        iconWeight: Font.Weight = .semibold,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.glyph = .system(name: systemName, size: iconSize, weight: iconWeight)
        self.size = size
        self.tint = tint
        self.action = action
    }

    init<Icon: View>(
        size: CGFloat = 44,
        tint: Color? = nil,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) {
        self.glyph = .custom(AnyView(icon()))
        self.size = size
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: {
            Haptics.tap()
            action()
        }) {
            ZStack {
                glassBackground
                glyphView
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var glassBackground: some View {
        if let tint {
            Circle()
                .fill(.clear)
                .glassEffect(.regular.tint(tint), in: Circle())
        } else {
            Circle()
                .fill(.clear)
                .glassEffect(.regular, in: Circle())
        }
    }

    @ViewBuilder
    private var glyphView: some View {
        switch glyph {
        case .system(let name, let iconSize, let weight):
            Image(systemName: name)
                .font(BodyFont.system(size: iconSize, weight: weight))
                .foregroundStyle(Palette.textPrimary)
        case .custom(let view):
            view
                .foregroundStyle(Palette.textPrimary)
        }
    }
}
