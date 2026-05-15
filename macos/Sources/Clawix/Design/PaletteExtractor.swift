import AppKit
import CoreImage
import Foundation

/// Image-based palette extractor used by the "Extract style from
/// reference" action. Downsamples the source image, buckets pixels in
/// a coarse RGB grid and surfaces the dominant colors plus
/// best-fit semantic roles (`bg`, `surface`, `fg`, `accent`,
/// `accent-2`).
///
/// v1 accepts local image files only. Remote references and document
/// formats are rejected with an explicit unsupported-source error.
enum PaletteExtractor {
    struct Result {
        var palette: [String]          // dominant hex strings, ordered by mass
        var bg: String
        var surface: String
        var fg: String
        var fgMuted: String
        var accent: String
        var accent2: String
        var border: String

        /// Apply this palette onto a base StyleManifest. Keeps brand,
        /// imagery and overrides untouched; only tokens.color and the
        /// imagery generation suffix are rewritten.
        func apply(onto base: StyleManifest) -> StyleManifest {
            var manifest = base
            var color = manifest.tokens.color
            color.bg = bg
            color.surface = surface
            color.surface2 = surface
            color.fg = fg
            color.fgMuted = fgMuted
            color.accent = accent
            color.accent2 = accent2
            color.border = border
            manifest.tokens.color = color
            var imagery = manifest.imagery ?? StyleImagery()
            imagery.generationPromptSuffix = "palette \(accent), \(accent2), \(bg); palette derived from a reference"
            manifest.imagery = imagery
            return manifest
        }
    }

    enum ExtractError: LocalizedError {
        case cannotLoadImage(URL)
        case unsupportedSource(String)

        var errorDescription: String? {
            switch self {
            case .cannotLoadImage(let url): return "Could not read pixels from \(url.lastPathComponent)."
            case .unsupportedSource(let kind): return "Palette extraction supports local image files, not '\(kind)' references."
            }
        }
    }

    static func extract(from imageURL: URL) throws -> Result {
        guard let image = NSImage(contentsOf: imageURL) else {
            throw ExtractError.cannotLoadImage(imageURL)
        }
        return try extract(from: image)
    }

    static func extract(from image: NSImage) throws -> Result {
        guard let pixels = sample(image: image, sampleEdge: 64) else {
            throw ExtractError.cannotLoadImage(URL(fileURLWithPath: "(memory)"))
        }
        return classify(pixels: pixels)
    }

    // MARK: - Sampling

    private struct RGB {
        var r: Double
        var g: Double
        var b: Double

        var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
        var saturation: Double {
            let maxC = max(r, max(g, b))
            let minC = min(r, min(g, b))
            return maxC == 0 ? 0 : (maxC - minC) / maxC
        }
        var hex: String { hexString(r: r, g: g, b: b) }
    }

    private static func sample(image: NSImage, sampleEdge: Int) -> [(RGB, Int)]? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        let width = Int(rep.pixelsWide)
        let height = Int(rep.pixelsHigh)
        guard width > 0, height > 0 else { return nil }
        let bucketsPerChannel = 6 // 6 × 6 × 6 = 216 buckets
        var counts: [Int: Int] = [:]
        var sums: [Int: (r: Double, g: Double, b: Double)] = [:]
        let stride = max(1, Int(round(Double(min(width, height)) / Double(sampleEdge))))
        var x = 0
        while x < width {
            var y = 0
            while y < height {
                if let color = rep.colorAt(x: x, y: y) {
                    let r = clamp01(Double(color.redComponent))
                    let g = clamp01(Double(color.greenComponent))
                    let b = clamp01(Double(color.blueComponent))
                    let bucket = bucketIndex(r, g, b, perChannel: bucketsPerChannel)
                    counts[bucket, default: 0] += 1
                    let prev = sums[bucket] ?? (0, 0, 0)
                    sums[bucket] = (prev.r + r, prev.g + g, prev.b + b)
                }
                y += stride
            }
            x += stride
        }
        if counts.isEmpty { return nil }
        return counts
            .sorted { $0.value > $1.value }
            .compactMap { (bucket, count) -> (RGB, Int)? in
                guard let sum = sums[bucket] else { return nil }
                let n = Double(count)
                return (RGB(r: sum.r / n, g: sum.g / n, b: sum.b / n), count)
            }
    }

    private static func bucketIndex(_ r: Double, _ g: Double, _ b: Double, perChannel: Int) -> Int {
        let rIdx = min(perChannel - 1, Int(r * Double(perChannel)))
        let gIdx = min(perChannel - 1, Int(g * Double(perChannel)))
        let bIdx = min(perChannel - 1, Int(b * Double(perChannel)))
        return (rIdx * perChannel + gIdx) * perChannel + bIdx
    }

    // MARK: - Classification

    private static func classify(pixels: [(RGB, Int)]) -> Result {
        let palette = pixels.prefix(8).map { $0.0.hex }
        let sortedByLuminance = pixels.map(\.0).sorted { $0.luminance < $1.luminance }
        let darkest = sortedByLuminance.first ?? RGB(r: 0.08, g: 0.10, b: 0.12)
        let lightest = sortedByLuminance.last ?? RGB(r: 0.97, g: 0.97, b: 0.96)
        let midtones = sortedByLuminance.dropFirst(sortedByLuminance.count / 4)
            .dropLast(sortedByLuminance.count / 4)
        let neutralMid = midtones.min(by: { $0.saturation < $1.saturation }) ?? midtones.first ?? darkest

        // Accent = most saturated color whose luminance is between 0.15 and 0.85.
        let candidates = pixels.map(\.0)
            .filter { $0.luminance > 0.15 && $0.luminance < 0.9 }
            .sorted { $0.saturation > $1.saturation }
        let accent = candidates.first ?? RGB(r: 0.45, g: 0.65, b: 1.0)
        let secondaryCandidates = candidates.dropFirst().filter { abs($0.luminance - accent.luminance) > 0.05 }
        let accent2 = secondaryCandidates.first ?? candidates.dropFirst().first ?? accent

        // Whether the dominant palette feels light or dark decides which
        // role gets which extreme. Average luminance > 0.55 → light theme.
        let avgLuminance = pixels.reduce(0.0) { $0 + $1.0.luminance * Double($1.1) }
            / max(1.0, Double(pixels.reduce(0) { $0 + $1.1 }))
        let isLight = avgLuminance > 0.55

        let bg = isLight ? lightest : darkest
        let surface = isLight ? mix(lightest, with: RGB(r: 1, g: 1, b: 1), t: 0.6) : mix(darkest, with: neutralMid, t: 0.25)
        let fg = isLight ? darkest : lightest
        let fgMuted = isLight ? mix(darkest, with: neutralMid, t: 0.45) : mix(lightest, with: neutralMid, t: 0.45)
        let border = isLight ? mix(neutralMid, with: lightest, t: 0.5) : mix(neutralMid, with: darkest, t: 0.45)

        return Result(
            palette: palette,
            bg: bg.hex,
            surface: surface.hex,
            fg: fg.hex,
            fgMuted: fgMuted.hex,
            accent: accent.hex,
            accent2: accent2.hex,
            border: border.hex
        )
    }

    private static func mix(_ a: RGB, with b: RGB, t: Double) -> RGB {
        RGB(r: lerp(a.r, b.r, t), g: lerp(a.g, b.g, t), b: lerp(a.b, b.b, t))
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    private static func clamp01(_ value: Double) -> Double {
        max(0, min(1, value))
    }

    private static func hexString(r: Double, g: Double, b: Double) -> String {
        let ri = Int((clamp01(r) * 255).rounded())
        let gi = Int((clamp01(g) * 255).rounded())
        let bi = Int((clamp01(b) * 255).rounded())
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }
}
