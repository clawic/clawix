import AppKit

/// Detects "fresh" content on the system clipboard so QuickAsk can
/// offer it as a removable chip at panel-open time. Freshness is
/// gated by both an absolute time window (recent changes) and a
/// changeCount delta (skip clipboards we already exposed in a
/// previous session, even if the user reopens the panel quickly).
@MainActor
enum QuickAskClipboardSniffer {

    enum Payload: Equatable {
        case text(String)
        case image(URL)
        case file(URL)
        case pdf(URL)
    }

    static let recencyWindow: TimeInterval = 30

    /// `UserDefaults` key holding the changeCount of the last
    /// clipboard we already turned into a chip. Lets us avoid
    /// re-suggesting the same payload every time the user reopens the
    /// panel without copying anything new.
    private static let lastSeenKey = "quickAsk.clipboardLastSeenChangeCount"
    private static let lastSeenAtKey = "quickAsk.clipboardLastSeenAt"

    static func capture() -> Payload? {
        let pb = NSPasteboard.general
        let currentCount = pb.changeCount

        let defaults = UserDefaults.standard
        let lastSeen = defaults.integer(forKey: lastSeenKey)
        let lastSeenAt = defaults.double(forKey: lastSeenAtKey)

        if currentCount == lastSeen { return nil }

        // Refuse stale clipboards: if the changeCount is fresh from
        // the system but we suspect the user copied >30s ago (we have
        // a stored timestamp from the last sniff and not enough time
        // has passed since the change), skip. We only know "now" so
        // we conservatively treat a missing timestamp as fresh.
        if lastSeenAt > 0 {
            let now = Date().timeIntervalSince1970
            if now - lastSeenAt > recencyWindow { return nil }
        }

        let payload = readPayload(from: pb)
        if payload != nil {
            defaults.set(currentCount, forKey: lastSeenKey)
            defaults.set(Date().timeIntervalSince1970, forKey: lastSeenAtKey)
        }
        return payload
    }

    /// Update the stored timestamp without consuming the payload, so
    /// the recency window starts ticking from the moment the user
    /// crossed back into Clawix. Called by the controller right
    /// after the hotkey fires but before `show()` runs.
    static func markSeenNow() {
        UserDefaults.standard.set(
            Date().timeIntervalSince1970,
            forKey: lastSeenAtKey
        )
    }

    private static func readPayload(from pb: NSPasteboard) -> Payload? {
        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL],
           let first = urls.first(where: { $0.isFileURL })
        {
            return first.pathExtension.lowercased() == "pdf"
                ? .pdf(first)
                : .file(first)
        }
        if let images = pb.readObjects(forClasses: [NSImage.self]) as? [NSImage],
           let image = images.first,
           let url = persistImage(image)
        {
            return .image(url)
        }
        if let pdf = pb.data(forType: NSPasteboard.PasteboardType("com.adobe.pdf")),
           let url = persistData(pdf, ext: "pdf")
        {
            return .pdf(url)
        }
        if let text = pb.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return .text(text)
        }
        return nil
    }

    private static func persistImage(_ image: NSImage) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return nil }
        return persistData(png, ext: "png")
    }

    private static func persistData(_ data: Data, ext: String) -> URL? {
        let dir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Clawix-Captures", isDirectory: true)
        guard let dir else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let url = dir.appendingPathComponent("clipboard-\(stamp).\(ext)")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
