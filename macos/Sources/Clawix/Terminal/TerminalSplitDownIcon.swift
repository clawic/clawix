import SwiftUI

struct TerminalSplitDownIcon: View {
    var size: CGFloat = 14

    var body: some View {
        TerminalSplitDownShape()
            .stroke(style: StrokeStyle(lineWidth: max(1.3, size * 0.11), lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

private struct TerminalSplitDownShape: Shape {
    func path(in rect: CGRect) -> Path {
        let line = rect.midY
        let arrowX = rect.midX
        var path = Path(roundedRect: rect.insetBy(dx: rect.width * 0.12, dy: rect.height * 0.16), cornerRadius: rect.width * 0.15, style: .continuous)
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.20, y: line))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.20, y: line))
        path.move(to: CGPoint(x: arrowX, y: rect.minY + rect.height * 0.28))
        path.addLine(to: CGPoint(x: arrowX, y: rect.maxY - rect.height * 0.22))
        path.move(to: CGPoint(x: arrowX - rect.width * 0.12, y: rect.maxY - rect.height * 0.34))
        path.addLine(to: CGPoint(x: arrowX, y: rect.maxY - rect.height * 0.22))
        path.addLine(to: CGPoint(x: arrowX + rect.width * 0.12, y: rect.maxY - rect.height * 0.34))
        return path
    }
}
