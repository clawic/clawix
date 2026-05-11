import Foundation
import SwiftUI
import UIKit
import WebKit

/// iOS export helper. Same four formats as macOS (HTML, SVG, PNG, PDF)
/// but writes to a temp directory and returns the URL so the caller
/// can hand it to `UIActivityViewController` (share sheet). PNG and
/// PDF still come straight out of `WKWebView`.
@MainActor
enum EditorExport {
    enum Format: String, CaseIterable, Identifiable {
        case html, svg, png, pdf
        var id: String { rawValue }
        var label: String { rawValue.uppercased() }
    }

    static func tempURL(format: Format, suggestedName: String) -> URL {
        let base = suggestedName.isEmpty ? "Untitled" : suggestedName
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("\(base)-\(UUID().uuidString.prefix(6))")
            .appendingPathExtension(format.rawValue)
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
            guard let image = image, let data = image.pngData() else {
                completion(.failure(NSError(domain: "EditorExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "WKWebView returned no snapshot."])))
                return
            }
            do {
                try data.write(to: url, options: .atomic)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    static func writePDF(webView: WKWebView, to url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
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

/// Tiny SwiftUI wrapper around `UIActivityViewController` so the
/// editor's export buttons can hand off the temp file to the system
/// share sheet (Save to Files, AirDrop, etc.).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
