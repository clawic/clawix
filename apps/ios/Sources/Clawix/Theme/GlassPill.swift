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
    let systemName: String
    var size: CGFloat = 44
    var iconSize: CGFloat = 17
    var iconWeight: Font.Weight = .semibold
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.clear)
                    .glassEffect(.regular, in: Circle())
                Image(systemName: systemName)
                    .font(.system(size: iconSize, weight: iconWeight))
                    .foregroundStyle(Palette.textPrimary)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
