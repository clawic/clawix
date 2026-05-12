import SwiftUI

struct TerminalSplitRightIcon: View {
    var size: CGFloat = 14

    var body: some View {
        TerminalSplitRightShape()
            .stroke(style: StrokeStyle(lineWidth: max(1.3, size * 0.11), lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

private struct TerminalSplitRightShape: Shape {
    func path(in rect: CGRect) -> Path {
        let line = rect.midX
        let arrowY = rect.midY
        var path = Path(roundedRect: rect.insetBy(dx: rect.width * 0.12, dy: rect.height * 0.16), cornerRadius: rect.width * 0.15, style: .continuous)
        path.move(to: CGPoint(x: line, y: rect.minY + rect.height * 0.22))
        path.addLine(to: CGPoint(x: line, y: rect.maxY - rect.height * 0.22))
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.30, y: arrowY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.22, y: arrowY))
        path.move(to: CGPoint(x: rect.maxX - rect.width * 0.34, y: arrowY - rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.22, y: arrowY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.34, y: arrowY + rect.height * 0.12))
        return path
    }
}
