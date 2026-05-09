import SwiftUI

/// Custom MCP icon: three interlocking hooks rendered with squircle
/// curves on a 24-pt grid, after the official Model Context Protocol
/// chain-link logo (https://commons.wikimedia.org/wiki/File:Model_Context_Protocol_logo.svg).
/// Each hook is drawn as two parallel diagonal stems joined by a single
/// cubic-bezier 180° loop. The S-chain of paths 1+2 share an inner
/// anchor (path 1 end ≈ path 2 start) so their three free ends fall on
/// the NW-SE diagonal; path 3 weaves through both loops with its own
/// apex flipped down-left. Tints with `.foregroundColor` and stays
/// crisp at 11–16 pt point sizes.
struct McpIcon: View {
    var size: CGFloat = 14
    var lineWidth: CGFloat? = nil

    var body: some View {
        let s = size / 24
        let lw = lineWidth ?? 1.4 * s
        McpIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: lw,
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
            .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - size * 0.2 }
    }
}

private struct McpIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var path = Path()

        // Hook 1 (upper, apex up-right). Translated NE from the symmetric
        // baseline so the S-chain with hook 2 stays balanced.
        path.move(to: p(3.09, 7.29))
        path.addLine(to: p(5.92, 4.46))
        path.addCurve(to: p(12.70, 11.24),
                      control1: p(9.31, 1.07),
                      control2: p(16.09, 7.85))
        path.addLine(to: p(9.87, 14.07))

        // Hook 2 (lower-right, apex up-right). Translated NE the same
        // amount as hook 1 so its start meets hook 1 end at the chain
        // anchor (~9.92, 14.03) along the NW-SE diagonal.
        path.move(to: p(9.98, 13.99))
        path.addLine(to: p(12.81, 11.16))
        path.addCurve(to: p(19.59, 17.94),
                      control1: p(16.20, 7.77),
                      control2: p(22.98, 14.55))
        path.addLine(to: p(16.76, 20.77))

        // Hook 3 (lower-left, apex down-left). Translated SW so it
        // visually weaves through the loops of hooks 1 and 2 with a
        // chain gap of ~3 units in either chain anchor.
        path.move(to: p(7.25, 9.92))
        path.addLine(to: p(4.42, 12.75))
        path.addCurve(to: p(11.20, 19.53),
                      control1: p(1.03, 16.14),
                      control2: p(7.81, 22.92))
        path.addLine(to: p(14.03, 16.70))

        return path
    }
}

/// Display name for an MCP server identifier as it appears in the
/// "Used X" rows. Known servers map to a canonical capitalization;
/// unknown ones get their first letter uppercased so "revenuecat"
/// reads as "Revenuecat" instead of being shown verbatim.
func prettyMcpServer(_ server: String) -> String {
    if server.isEmpty { return "" }
    switch normalizedMcpServer(server) {
    case "node_repl", "node-repl", "noderepl": return "Node Repl"
    case "computer_use", "computer-use", "computeruse": return "Computer Use"
    default: break
    }
    return server.prefix(1).uppercased() + server.dropFirst()
}

func isComputerUseMcpServer(_ server: String) -> Bool {
    switch normalizedMcpServer(server) {
    case "computer_use", "computer-use", "computeruse":
        return true
    default:
        return false
    }
}

private func normalizedMcpServer(_ server: String) -> String {
    var value = server
        .lowercased()
        .split(separator: "@", maxSplits: 1)
        .first
        .map(String.init) ?? server.lowercased()
    if value.hasPrefix("mcp__") {
        value.removeFirst(5)
    }
    if value.hasSuffix("__") {
        value.removeLast(2)
    }
    return value
}
