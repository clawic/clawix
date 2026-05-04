import SwiftUI

// Top + bottom fade for vertical lists that may overflow. The
// gradient bleeds the scroll content into the background color so
// rows don't terminate against a hard horizontal cut.
//
// Use as `.overlay { FadeEdge(color: Palette.background) }` on top of
// any ScrollView / List. The 56pt height matches the desktop's chat
// list fade and stays comfortable on a 6.1" iPhone screen.

struct FadeEdge: View {
    var color: Color = Palette.background
    var height: CGFloat = 56

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                gradient: Gradient(colors: [color, color.opacity(0)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: height)
            Spacer()
            LinearGradient(
                gradient: Gradient(colors: [color.opacity(0), color]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: height)
        }
        .allowsHitTesting(false)
    }
}

extension View {
    func fadeEdge(color: Color = Palette.background, height: CGFloat = 56) -> some View {
        overlay(FadeEdge(color: color, height: height))
    }
}
