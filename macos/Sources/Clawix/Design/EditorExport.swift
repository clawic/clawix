import AppKit
import WebKit
import Foundation

/// Lightweight helper that takes the editor's currently rendered HTML
/// (or the snapshot of its WKWebView) and writes one of four output
/// formats to disk: HTML, SVG, PNG, PDF.
///
/// Phase 4 ships these four since they can be produced 100% in
/// Swift / AppKit without external deps. The Playwright-backed
/// full-fidelity PDF and the OpenXML PPTX path land later when the
/// daemon picks up the renderer pipeline from ClawJS.
@MainActor
enum EditorExport {
    enum Format: String, CaseIterable, Identifiable {
        case html, svg, png, pdf
        var id: String { rawValue }
        var label: String { rawValue.uppercased() }
    }

    static func defaultSavePanel(for format: Format, suggestedName: String) -> NSSavePanel {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(suggestedName).\(format.rawValue)"
        panel.allowedContentTypes = []
        return panel
    }

    static func writeHTML(_ html: String, to url: URL) throws {
        try html.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    static func writeSVG(html: String, width: Double, height: Double, to url: URL) throws {
        let body = extract(tag: "body", from: html) ?? html
        let style = extract(tag: "style", from: html) ?? ""
        let svg = """
<svg xmlns="http://www.w3.org/2000/svg" width="\(Int(width))" height="\(Int(height))" viewBox="0 0 \(Int(width)) \(Int(height))">
  <foreignObject x="0" y="0" width="\(Int(width))" height="\(Int(height))">
    <div xmlns="http://www.w3.org/1999/xhtml">
      <style>\(style)</style>
      \(body)
    </div>
  </foreignObject>
</svg>
"""
        try svg.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    static func writePNG(webView: WKWebView, to url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        let config = WKSnapshotConfiguration()
        webView.takeSnapshot(with: config) { image, error in
            if let error = error {
                completion(.failure(error)); return
            }
            guard let image = image else {
                completion(.failure(NSError(domain: "EditorExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "WKWebView returned no snapshot."])))
                return
            }
            do {
                guard let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else {
                    throw NSError(domain: "EditorExport", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not convert snapshot to PNG."])
                }
                try png.write(to: url, options: .atomic)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    static func writePDF(webView: WKWebView, to url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        if #available(macOS 11.0, *) {
            let configuration = WKPDFConfiguration()
            webView.createPDF(configuration: configuration) { result in
                switch result {
                case .success(let data):
                    do {
                        try data.write(to: url, options: .atomic)
                        completion(.success(()))
                    } catch {
                        completion(.failure(error))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        } else {
            completion(.failure(NSError(domain: "EditorExport", code: 3, userInfo: [NSLocalizedDescriptionKey: "PDF export requires macOS 11+."])))
        }
    }

    private static func extract(tag: String, from html: String) -> String? {
        let pattern = "<\(tag)[^>]*>([\\s\\S]*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range) else { return nil }
        guard let group = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[group])
    }
}
