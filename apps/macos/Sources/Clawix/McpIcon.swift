import SwiftUI

/// Custom MCP icon: four corner rings linked by a single diagonal from
/// the top-right ring to the bottom-left ring. Drawn with `Path` in a
/// 28-point grid so it tints with `.foregroundColor` and stays balanced
/// against the other custom glyphs in the work summary (terminal, globe).
struct McpIcon: View {
    var size: CGFloat = 14

    var body: some View {
        McpIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.0 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
            .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - size * 0.2 }
    }
}

private struct McpIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2
        let dy = (rect.height - 28 * s) / 2
        let cx = dx + 14 * s
        let cy = dy + 14 * s

        // Geometry locked to the most-compact variant agreed with the
        // user (round 6 attempt 5): rings tightly packed with a hairline
        // gap, single diagonal connecting the top-right and bottom-left
        // rings via their inner-tangent point.
        let d: CGFloat = 7.5 * s
        let r: CGFloat = 4.5 * s
        let off: CGFloat = r * 0.7071067811865476

        var path = Path()

        let centers: [(CGFloat, CGFloat)] = [(-d, -d), (d, -d), (-d, d), (d, d)]
        for (cdx, cdy) in centers {
            let rx = cx + cdx, ry = cy + cdy
            path.addEllipse(in: CGRect(x: rx - r, y: ry - r, width: 2 * r, height: 2 * r))
        }

        path.move(to: CGPoint(x: cx + d - off, y: cy - d + off))
        path.addLine(to: CGPoint(x: cx - d + off, y: cy + d - off))

        return path
    }
}

/// Display name for an MCP server identifier as it appears in the
/// "Used X" rows. Known servers map to a canonical capitalization;
/// unknown ones get their first letter uppercased so "revenuecat"
/// reads as "Revenuecat" instead of being shown verbatim.
func prettyMcpServer(_ server: String) -> String {
    if server.isEmpty { return "" }
    switch server.lowercased() {
    case "node_repl", "node-repl", "noderepl": return "Node Repl"
    default: break
    }
    return server.prefix(1).uppercased() + server.dropFirst()
}
