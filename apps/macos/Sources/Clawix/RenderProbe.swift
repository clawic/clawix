import Foundation

// Diagnostic only. Counts how many times a SwiftUI body is evaluated and
// dumps the totals to /tmp/clawix-renders.log every 200 ms.
//
// Usage: add `RenderProbe.tick("ViewName")` at the very top of `var body`.
// Reset by deleting the file on disk.
enum RenderProbe {
    private static let queue = DispatchQueue(label: "RenderProbe")
    nonisolated(unsafe) private static var counts: [String: Int] = [:]
    nonisolated(unsafe) private static var lastFlush = Date.distantPast
    nonisolated(unsafe) private static var didStart = false
    private static let path = "/tmp/clawix-renders.log"

    static func tick(_ name: String) {
        queue.async {
            counts[name, default: 0] += 1
            startIfNeeded()
        }
    }

    private static func startIfNeeded() {
        guard !didStart else { return }
        didStart = true
        try? "".write(toFile: path, atomically: true, encoding: .utf8)
        // Timer.scheduledTimer needs a real run loop. The probe queue is
        // a serial DispatchQueue with no run loop attached, so schedule
        // the periodic flush on the main run loop instead.
        DispatchQueue.main.async {
            Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
                queue.async { flush() }
            }
        }
    }

    private static func flush() {
        guard !counts.isEmpty else { return }
        let stamp = String(format: "%.3f", Date().timeIntervalSince1970)
        let snapshot = counts.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let line = "[\(stamp)] \(snapshot)\n"
        if let data = line.data(using: .utf8),
           let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        }
    }
}
