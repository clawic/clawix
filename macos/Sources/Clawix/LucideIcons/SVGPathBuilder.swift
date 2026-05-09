import SwiftUI
import CoreGraphics

/// Builds a SwiftUI `Path` from an SVG `d` attribute string.
///
/// Supports the line and curve commands used by the initial Lucide
/// glyph catalog: `M m L l H h V v C c S s Q q T t Z z`.
///
/// We picked a runtime parser over hand-translating each path because
/// hand-conversion of cubic Béziers produced visually broken silhouettes
/// in a previous attempt. The parser is small (one file, no deps) and
/// every glyph reuses the same battle-tested code.
enum SVGPathBuilder {
    private static let cacheLock = NSLock()
    private static var pathCache: [String: Path] = [:]

    static func build(_ d: String) -> Path {
        cacheLock.lock()
        if let cached = pathCache[d] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        var b = Builder()
        b.parse(d)
        let path = b.path

        cacheLock.lock()
        pathCache[d] = path
        cacheLock.unlock()

        return path
    }

    struct Builder {
        var path = Path()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastCubicControl: CGPoint? = nil
        var lastQuadControl: CGPoint? = nil

        mutating func parse(_ d: String) {
            var s = SVGPathScanner(d)
            var cmd: Character = " "
            while !s.atEnd {
                s.skipWSComma()
                if s.atEnd { break }
                if s.peekIsLetter() {
                    cmd = s.consumeLetter()!
                } else {
                    if cmd == "M" { cmd = "L" }
                    else if cmd == "m" { cmd = "l" }
                }
                let rel = cmd.isLowercase
                switch Character(cmd.lowercased()) {
                case "m": consumeMove(rel: rel, scanner: &s); cmd = rel ? "l" : "L"
                case "l": consumeLine(rel: rel, scanner: &s)
                case "h": consumeHLine(rel: rel, scanner: &s)
                case "v": consumeVLine(rel: rel, scanner: &s)
                case "c": consumeCubic(rel: rel, scanner: &s)
                case "s": consumeSmoothCubic(rel: rel, scanner: &s)
                case "q": consumeQuad(rel: rel, scanner: &s)
                case "t": consumeSmoothQuad(rel: rel, scanner: &s)
                case "z":
                    path.closeSubpath()
                    current = subpathStart
                    lastCubicControl = nil
                    lastQuadControl = nil
                default:
                    return
                }
            }
        }

        private mutating func consumeMove(rel: Bool, scanner s: inout SVGPathScanner) {
            guard let x = s.nextNumber(), let y = s.nextNumber() else { return }
            let p = rel ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            path.move(to: p)
            current = p
            subpathStart = p
            lastCubicControl = nil
            lastQuadControl = nil
        }

        private mutating func consumeLine(rel: Bool, scanner s: inout SVGPathScanner) {
            guard let x = s.nextNumber(), let y = s.nextNumber() else { return }
            let p = rel ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            path.addLine(to: p)
            current = p
            lastCubicControl = nil
            lastQuadControl = nil
        }

        private mutating func consumeHLine(rel: Bool, scanner s: inout SVGPathScanner) {
            guard let x = s.nextNumber() else { return }
            let p = rel ? CGPoint(x: current.x + x, y: current.y) : CGPoint(x: x, y: current.y)
            path.addLine(to: p)
            current = p
            lastCubicControl = nil
            lastQuadControl = nil
        }

        private mutating func consumeVLine(rel: Bool, scanner s: inout SVGPathScanner) {
            guard let y = s.nextNumber() else { return }
            let p = rel ? CGPoint(x: current.x, y: current.y + y) : CGPoint(x: current.x, y: y)
            path.addLine(to: p)
            current = p
            lastCubicControl = nil
            lastQuadControl = nil
        }

        private mutating func consumeCubic(rel: Bool, scanner s: inout SVGPathScanner) {
            guard let x1 = s.nextNumber(), let y1 = s.nextNumber(),
                  let x2 = s.nextNumber(), let y2 = s.nextNumber(),
                  let x  = s.nextNumber(), let y  = s.nextNumber()
            else { return }
            let c1 = rel ? CGPoint(x: current.x + x1, y: current.y + y1) : CGPoint(x: x1, y: y1)
            let c2 = rel ? CGPoint(x: current.x + x2, y: current.y + y2) : CGPoint(x: x2, y: y2)
            let p  = rel ? CGPoint(x: current.x + x,  y: current.y + y)  : CGPoint(x: x,  y: y)
            path.addCurve(to: p, control1: c1, control2: c2)
            current = p
            lastCubicControl = c2
            lastQuadControl = nil
        }

        private mutating func consumeSmoothCubic(rel: Bool, scanner s: inout SVGPathScanner) {
            guard let x2 = s.nextNumber(), let y2 = s.nextNumber(),
                  let x  = s.nextNumber(), let y  = s.nextNumber()
            else { return }
            let c1 = lastCubicControl
                .map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) }
                ?? current
            let c2 = rel ? CGPoint(x: current.x + x2, y: current.y + y2) : CGPoint(x: x2, y: y2)
            let p  = rel ? CGPoint(x: current.x + x,  y: current.y + y)  : CGPoint(x: x,  y: y)
            path.addCurve(to: p, control1: c1, control2: c2)
            current = p
            lastCubicControl = c2
            lastQuadControl = nil
        }

        private mutating func consumeQuad(rel: Bool, scanner s: inout SVGPathScanner) {
            guard let x1 = s.nextNumber(), let y1 = s.nextNumber(),
                  let x  = s.nextNumber(), let y  = s.nextNumber()
            else { return }
            let c = rel ? CGPoint(x: current.x + x1, y: current.y + y1) : CGPoint(x: x1, y: y1)
            let p = rel ? CGPoint(x: current.x + x,  y: current.y + y)  : CGPoint(x: x,  y: y)
            path.addQuadCurve(to: p, control: c)
            current = p
            lastQuadControl = c
            lastCubicControl = nil
        }

        private mutating func consumeSmoothQuad(rel: Bool, scanner s: inout SVGPathScanner) {
            guard let x = s.nextNumber(), let y = s.nextNumber() else { return }
            let c = lastQuadControl
                .map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) }
                ?? current
            let p = rel ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            path.addQuadCurve(to: p, control: c)
            current = p
            lastQuadControl = c
            lastCubicControl = nil
        }
    }

}
