import Foundation

/// Diagnostic-only file logger for the QuickAsk module. NSLog goes
/// through os_log which redacts Swift-interpolated strings as
/// `<private>`, making it impossible to read controller/hotkey state
/// from `log show`. This appends to a known path so we can inspect the
/// hotkey/show flow directly. Remove once the "panel sometimes does
/// not open" bug is understood.
enum QuickAskDiag {

    private static let path = "/tmp/clawix-quickask.log"
    private static let queue = DispatchQueue(label: "clawix.quickask.diag")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func log(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path),
               let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}
