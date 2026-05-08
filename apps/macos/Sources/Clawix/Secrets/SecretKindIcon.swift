import SwiftUI
import SecretsModels

/// Hand-drawn icons per secret kind. The shapes are intentionally line-art
/// at the same stroke weight as the rest of the sidebar icons
/// (`FolderOpenIcon`, `ArchiveIcon`, …) so they read as a coherent set
/// rather than a Material grab-bag.
struct SecretKindIcon: View {
    let kind: SecretKind
    var size: CGFloat = 18
    var lineWidth: CGFloat = 1.3
    var color: Color = Color(white: 0.86)

    var body: some View {
        Canvas { context, sz in
            switch kind {
            case .apiKey:
                drawKey(context: context, sz: sz)
            case .passwordLogin:
                drawPasswordDots(context: context, sz: sz)
            case .oauthToken:
                drawCirclesLink(context: context, sz: sz)
            case .sshIdentity:
                drawTerminalKey(context: context, sz: sz)
            case .databaseUrl:
                drawDatabase(context: context, sz: sz)
            case .envBundle:
                drawCurlyBraces(context: context, sz: sz)
            case .structuredCredentials:
                drawCard(context: context, sz: sz)
            case .certificate:
                drawCertificate(context: context, sz: sz)
            case .webhookSecret:
                drawWebhook(context: context, sz: sz)
            case .secureNote:
                drawNote(context: context, sz: sz)
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - Drawings

    private func drawKey(context: GraphicsContext, sz: CGSize) {
        let w = sz.width, h = sz.height
        var path = Path()
        let circleD = h * 0.50
        let circleX = w * 0.06
        let circleY = (h - circleD) / 2
        path.addEllipse(in: CGRect(x: circleX, y: circleY, width: circleD, height: circleD))
        let shaftStart = CGPoint(x: circleX + circleD, y: h / 2)
        let shaftEnd = CGPoint(x: w * 0.96, y: h / 2)
        path.move(to: shaftStart)
        path.addLine(to: shaftEnd)
        path.move(to: CGPoint(x: w * 0.78, y: h / 2))
        path.addLine(to: CGPoint(x: w * 0.78, y: h / 2 + h * 0.18))
        path.move(to: CGPoint(x: w * 0.88, y: h / 2))
        path.addLine(to: CGPoint(x: w * 0.88, y: h / 2 + h * 0.12))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }

    private func drawPasswordDots(context: GraphicsContext, sz: CGSize) {
        let w = sz.width, h = sz.height
        let dotSize = h * 0.20
        let y = h / 2 - dotSize / 2
        var path = Path()
        for i in 0..<4 {
            let x = w * (0.10 + Double(i) * 0.22)
            path.addEllipse(in: CGRect(x: x, y: y, width: dotSize, height: dotSize))
        }
        context.fill(path, with: .color(color))
    }

    private func drawCirclesLink(context: GraphicsContext, sz: CGSize) {
        let w = sz.width, h = sz.height
        let r = h * 0.28
        var path = Path()
        path.addEllipse(in: CGRect(x: w * 0.08, y: h / 2 - r, width: r * 2, height: r * 2))
        path.addEllipse(in: CGRect(x: w * 0.50, y: h / 2 - r, width: r * 2, height: r * 2))
        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    private func drawTerminalKey(context: GraphicsContext, sz: CGSize) {
        let w = sz.width, h = sz.height
        let outer = Path(roundedRect: CGRect(x: w * 0.06, y: h * 0.18, width: w * 0.88, height: h * 0.64), cornerSize: CGSize(width: 3, height: 3), style: .continuous)
        context.stroke(outer, with: .color(color), lineWidth: lineWidth)
        var prompt = Path()
        prompt.move(to: CGPoint(x: w * 0.18, y: h * 0.40))
        prompt.addLine(to: CGPoint(x: w * 0.30, y: h * 0.50))
        prompt.addLine(to: CGPoint(x: w * 0.18, y: h * 0.60))
        prompt.move(to: CGPoint(x: w * 0.36, y: h * 0.62))
        prompt.addLine(to: CGPoint(x: w * 0.62, y: h * 0.62))
        context.stroke(prompt, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }

    private func drawDatabase(context: GraphicsContext, sz: CGSize) {
        let w = sz.width, h = sz.height
        let centerX = w / 2
        let radiusX = w * 0.36
        let radiusY = h * 0.08
        var path = Path()
        for i in 0..<3 {
            let cy = h * 0.20 + CGFloat(i) * h * 0.27
            path.addEllipse(in: CGRect(x: centerX - radiusX, y: cy - radiusY, width: radiusX * 2, height: radiusY * 2))
        }
        path.move(to: CGPoint(x: centerX - radiusX, y: h * 0.20))
        path.addLine(to: CGPoint(x: centerX - radiusX, y: h * 0.74))
        path.move(to: CGPoint(x: centerX + radiusX, y: h * 0.20))
        path.addLine(to: CGPoint(x: centerX + radiusX, y: h * 0.74))
        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    private func drawCurlyBraces(context: GraphicsContext, sz: CGSize) {
        let w = sz.width, h = sz.height
        var path = Path()
        // Left brace.
        path.move(to: CGPoint(x: w * 0.32, y: h * 0.18))
        path.addCurve(to: CGPoint(x: w * 0.18, y: h * 0.50), control1: CGPoint(x: w * 0.22, y: h * 0.18), control2: CGPoint(x: w * 0.18, y: h * 0.40))
        path.addCurve(to: CGPoint(x: w * 0.32, y: h * 0.82), control1: CGPoint(x: w * 0.18, y: h * 0.60), control2: CGPoint(x: w * 0.22, y: h * 0.82))
        // Right brace.
        path.move(to: CGPoint(x: w * 0.68, y: h * 0.18))
        path.addCurve(to: CGPoint(x: w * 0.82, y: h * 0.50), control1: CGPoint(x: w * 0.78, y: h * 0.18), control2: CGPoint(x: w * 0.82, y: h * 0.40))
        path.addCurve(to: CGPoint(x: w * 0.68, y: h * 0.82), control1: CGPoint(x: w * 0.82, y: h * 0.60), control2: CGPoint(x: w * 0.78, y: h * 0.82))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }

    private func drawCard(context: GraphicsContext, sz: CGSize) {
        let w = sz.width, h = sz.height
        let outer = Path(roundedRect: CGRect(x: w * 0.06, y: h * 0.22, width: w * 0.88, height: h * 0.56), cornerSize: CGSize(width: 3, height: 3), style: .continuous)
        context.stroke(outer, with: .color(color), lineWidth: lineWidth)
        var lines = Path()
        lines.move(to: CGPoint(x: w * 0.06, y: h * 0.36))
        lines.addLine(to: CGPoint(x: w * 0.94, y: h * 0.36))
        lines.move(to: CGPoint(x: w * 0.16, y: h * 0.55))
        lines.addLine(to: CGPoint(x: w * 0.55, y: h * 0.55))
        lines.move(to: CGPoint(x: w * 0.16, y: h * 0.66))
        lines.addLine(to: CGPoint(x: w * 0.40, y: h * 0.66))
        context.stroke(lines, with: .color(color), lineWidth: lineWidth)
    }

    private func drawCertificate(context: GraphicsContext, sz: CGSize) {
        let w = sz.width, h = sz.height
        let outer = Path(roundedRect: CGRect(x: w * 0.10, y: h * 0.10, width: w * 0.80, height: h * 0.70), cornerSize: CGSize(width: 2, height: 2), style: .continuous)
        context.stroke(outer, with: .color(color), lineWidth: lineWidth)
        var lines = Path()
        lines.move(to: CGPoint(x: w * 0.20, y: h * 0.30))
        lines.addLine(to: CGPoint(x: w * 0.80, y: h * 0.30))
        lines.move(to: CGPoint(x: w * 0.20, y: h * 0.45))
        lines.addLine(to: CGPoint(x: w * 0.60, y: h * 0.45))
        lines.move(to: CGPoint(x: w * 0.45, y: h * 0.80))
        lines.addLine(to: CGPoint(x: w * 0.45, y: h * 0.95))
        lines.addLine(to: CGPoint(x: w * 0.55, y: h * 0.85))
        lines.move(to: CGPoint(x: w * 0.55, y: h * 0.80))
        lines.addLine(to: CGPoint(x: w * 0.55, y: h * 0.95))
        context.stroke(lines, with: .color(color), lineWidth: lineWidth)
    }

    private func drawWebhook(context: GraphicsContext, sz: CGSize) {
        let w = sz.width, h = sz.height
        var path = Path()
        path.addArc(center: CGPoint(x: w * 0.30, y: h * 0.45), radius: h * 0.20, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        path.addArc(center: CGPoint(x: w * 0.70, y: h * 0.55), radius: h * 0.18, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        path.move(to: CGPoint(x: w * 0.30, y: h * 0.65))
        path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.85))
        path.move(to: CGPoint(x: w * 0.70, y: h * 0.75))
        path.addLine(to: CGPoint(x: w * 0.55, y: h * 0.95))
        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    private func drawNote(context: GraphicsContext, sz: CGSize) {
        let w = sz.width, h = sz.height
        let outer = Path(roundedRect: CGRect(x: w * 0.18, y: h * 0.10, width: w * 0.64, height: h * 0.80), cornerSize: CGSize(width: 3, height: 3), style: .continuous)
        context.stroke(outer, with: .color(color), lineWidth: lineWidth)
        var lines = Path()
        for i in 0..<3 {
            let y = h * (0.30 + Double(i) * 0.18)
            lines.move(to: CGPoint(x: w * 0.28, y: y))
            lines.addLine(to: CGPoint(x: w * 0.72, y: y))
        }
        context.stroke(lines, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }
}
