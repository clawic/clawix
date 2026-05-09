import AppKit
import SwiftUI

/// Clawix brand logo: outer iOS-style continuous-corner squircle with the
/// visor cut out and two squircle eyes filled back in. Draws as a single
/// `evenodd`-filled path in a 100x100 design space; scaled to whatever
/// frame the caller asks for.
struct ClawixLogoIcon: View {
    var size: CGFloat = 18

    var body: some View {
        ClawixLogoShape()
            .fill(.primary, style: FillStyle(eoFill: true))
            .frame(width: size, height: size)
    }
}

/// Template `NSImage` for use in places that need an AppKit image with
/// system tinting (menu bar, dock badges). `MenuBarExtra` only renders
/// SwiftUI shapes inconsistently in its label slot, so the icon has to
/// be flattened into an `NSImage` with `isTemplate = true` so AppKit
/// applies the menu bar's foreground color automatically.
enum ClawixLogoTemplateImage {
    @MainActor
    static func make(size: CGFloat = 18) -> NSImage {
        let renderer = ImageRenderer(
            content: ClawixLogoShape()
                .fill(Color.black, style: FillStyle(eoFill: true))
                .frame(width: size, height: size)
        )
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: size, height: size))
        image.isTemplate = true
        return image
    }
}

struct ClawixLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 100
        let dx = (rect.width  - 100 * s) / 2
        let dy = (rect.height - 100 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var path = Path()

        // Outer body — true iOS continuous-corner squircle (E = 38).
        // Three cubic beziers per corner with the magic numbers Apple
        // uses for app icon masks.
        path.move(to: p(38, 0))
        path.addLine(to: p(62, 0))
        path.addCurve(to: p(87.27, 2.61),  control1: p(75.42, 0),     control2: p(82.13, 0))
        path.addCurve(to: p(97.39, 12.73), control1: p(91.73, 4.91),  control2: p(95.09, 8.27))
        path.addCurve(to: p(100, 38),      control1: p(100, 17.87),   control2: p(100, 24.58))
        path.addLine(to: p(100, 62))
        path.addCurve(to: p(97.39, 87.27), control1: p(100, 75.42),   control2: p(100, 82.13))
        path.addCurve(to: p(87.27, 97.39), control1: p(95.09, 91.73), control2: p(91.73, 95.09))
        path.addCurve(to: p(62, 100),      control1: p(82.13, 100),   control2: p(75.42, 100))
        path.addLine(to: p(38, 100))
        path.addCurve(to: p(12.73, 97.39), control1: p(24.58, 100),   control2: p(17.87, 100))
        path.addCurve(to: p(2.61, 87.27),  control1: p(8.27, 95.09),  control2: p(4.91, 91.73))
        path.addCurve(to: p(0, 62),        control1: p(0, 82.13),     control2: p(0, 75.42))
        path.addLine(to: p(0, 38))
        path.addCurve(to: p(2.61, 12.73),  control1: p(0, 24.58),     control2: p(0, 17.87))
        path.addCurve(to: p(12.73, 2.61),  control1: p(4.91, 8.27),   control2: p(8.27, 4.91))
        path.addCurve(to: p(38, 0),        control1: p(17.87, 0),     control2: p(24.58, 0))
        path.closeSubpath()

        // Visor (cut out via evenodd) — same squircle treatment, E = 22.
        path.move(to: p(31, 25))
        path.addLine(to: p(69, 25))
        path.addCurve(to: p(83.54, 26.51), control1: p(76.77, 25),    control2: p(80.65, 25))
        path.addCurve(to: p(89.49, 32.46), control1: p(86.17, 27.85), control2: p(88.15, 29.83))
        path.addCurve(to: p(91, 47),       control1: p(91, 35.35),    control2: p(91, 39.23))
        path.addLine(to: p(91, 53))
        path.addCurve(to: p(89.49, 67.54), control1: p(91, 60.77),    control2: p(91, 64.65))
        path.addCurve(to: p(83.54, 73.49), control1: p(88.15, 70.17), control2: p(86.17, 72.15))
        path.addCurve(to: p(69, 75),       control1: p(80.65, 75),    control2: p(76.77, 75))
        path.addLine(to: p(31, 75))
        path.addCurve(to: p(16.46, 73.49), control1: p(23.23, 75),    control2: p(19.35, 75))
        path.addCurve(to: p(10.51, 67.54), control1: p(13.83, 72.15), control2: p(11.85, 70.17))
        path.addCurve(to: p(9, 53),        control1: p(9, 64.65),     control2: p(9, 60.77))
        path.addLine(to: p(9, 47))
        path.addCurve(to: p(10.51, 32.46), control1: p(9, 39.23),     control2: p(9, 35.35))
        path.addCurve(to: p(16.46, 26.51), control1: p(11.85, 29.83), control2: p(13.83, 27.85))
        path.addCurve(to: p(31, 25),       control1: p(19.35, 25),    control2: p(23.23, 25))
        path.closeSubpath()

        // Left eye (filled back in inside the visor cutout via evenodd).
        path.move(to: p(30, 43))
        path.addLine(to: p(32, 43))
        path.addCurve(to: p(38, 49), control1: p(36.5, 43), control2: p(38, 44.5))
        path.addLine(to: p(38, 52))
        path.addCurve(to: p(32, 58), control1: p(38, 56.5), control2: p(36.5, 58))
        path.addLine(to: p(30, 58))
        path.addCurve(to: p(24, 52), control1: p(25.5, 58), control2: p(24, 56.5))
        path.addLine(to: p(24, 49))
        path.addCurve(to: p(30, 43), control1: p(24, 44.5), control2: p(25.5, 43))
        path.closeSubpath()

        // Right eye.
        path.move(to: p(68, 43))
        path.addLine(to: p(70, 43))
        path.addCurve(to: p(76, 49), control1: p(74.5, 43), control2: p(76, 44.5))
        path.addLine(to: p(76, 52))
        path.addCurve(to: p(70, 58), control1: p(76, 56.5), control2: p(74.5, 58))
        path.addLine(to: p(68, 58))
        path.addCurve(to: p(62, 52), control1: p(63.5, 58), control2: p(62, 56.5))
        path.addLine(to: p(62, 49))
        path.addCurve(to: p(68, 43), control1: p(62, 44.5), control2: p(63.5, 43))
        path.closeSubpath()

        return path
    }
}
