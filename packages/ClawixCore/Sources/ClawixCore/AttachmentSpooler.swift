import Foundation

/// Materialises inline image attachments coming off the bridge as
/// on-disk files. The Codex backend accepts image inputs as `localImage`
/// items keyed by absolute path, so every attachment that arrives over
/// the WS bridge has to be written to a file before we can hand it to a
/// `turn/start` call.
///
/// Files live under
/// `NSTemporaryDirectory()/clawix-attachments/<thread-or-chat-id>/<attachment-id>.<ext>`
/// so they are easy to spot, easy to delete, and grouped together if
/// debugging is needed. We never delete them eagerly: a thread may be
/// resumed minutes later and the rollout still references the path. The
/// system reaps `NSTemporaryDirectory()` on its own schedule, which is
/// good enough for a chat companion.
public enum AttachmentSpooler {
    /// Writes the attachments to disk and returns the absolute paths in
    /// the same order the inputs were provided. Decoding/IO failures are
    /// silently skipped: a missing image is preferable to bringing the
    /// whole turn down on a single corrupt blob.
    @discardableResult
    public static func write(
        attachments: [WireAttachment],
        scope: String,
        log: ((String) -> Void)? = nil
    ) -> [String] {
        guard !attachments.isEmpty else { return [] }
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clawix-attachments", isDirectory: true)
            .appendingPathComponent(scope, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            log?("attachment dir failed \(error)")
            return []
        }
        var paths: [String] = []
        for attachment in attachments {
            guard let data = Data(base64Encoded: attachment.dataBase64) else {
                log?("attachment decode failed id=\(attachment.id)")
                continue
            }
            let ext = preferredExtension(filename: attachment.filename, mimeType: attachment.mimeType)
            let url = root.appendingPathComponent("\(attachment.id).\(ext)")
            do {
                try data.write(to: url, options: .atomic)
                paths.append(url.path)
            } catch {
                log?("attachment write failed \(error)")
            }
        }
        return paths
    }

    private static func preferredExtension(filename: String?, mimeType: String) -> String {
        if let filename, let dotRange = filename.range(of: ".", options: .backwards) {
            let candidate = String(filename[dotRange.upperBound...]).lowercased()
            if !candidate.isEmpty, candidate.count <= 5 { return candidate }
        }
        switch mimeType.lowercased() {
        case "image/png":  return "png"
        case "image/heic": return "heic"
        case "image/heif": return "heif"
        case "image/webp": return "webp"
        case "image/gif":  return "gif"
        default:           return "jpg"
        }
    }
}
