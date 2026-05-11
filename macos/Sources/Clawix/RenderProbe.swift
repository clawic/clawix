import Foundation

// Diagnostic only. Tracks SwiftUI body re-evaluations and (optionally) the
// CPU cost of expensive functions. Aggregates both into a single line per
// window in /tmp/clawix-renders.log so it's easy to eyeball where the
// sidebar is burning cycles.
//
// Two APIs:
//   RenderProbe.tick("ViewName")
//      → counts a body evaluation. Add at the very top of `var body`.
//   RenderProbe.time("makeSnapshot") { ... }
//      → counts an invocation AND records elapsed milliseconds.
//
// Each window's flush prints, alphabetised:
//   ViewName=count                        (tick-only)
//   makeSnapshot=count tot=X.Xms mx=Y.Yms (time)
//
// Counters reset every window so the numbers describe the last second, not
// session totals — much easier to correlate with "I just hovered / dragged
// / typed". Reset by deleting the file on disk.
enum RenderProbe {
    private static let queue = DispatchQueue(label: "RenderProbe")
    nonisolated(unsafe) private static var counts: [String: Int] = [:]
    nonisolated(unsafe) private static var totalMs: [String: Double] = [:]
    nonisolated(unsafe) private static var maxMs: [String: Double] = [:]
    nonisolated(unsafe) private static var didStart = false
    nonisolated(unsafe) private static var windowStart = CFAbsoluteTimeGetCurrent()
    nonisolated(unsafe) private static var lastActivityAt: CFAbsoluteTime?
    private static let path = "/tmp/clawix-renders.log"
    private static let flushInterval: TimeInterval = 0.5
    private static let hitchActivityWindow: TimeInterval = 3.0

    static func tick(_ name: String) {
        queue.async {
            recordActivityIfNeeded(name)
            counts[name, default: 0] += 1
            startIfNeeded()
        }
    }

    @discardableResult
    @inline(__always)
    static func time<T>(_ name: String, _ block: () -> T) -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = block()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        queue.async {
            lastActivityAt = CFAbsoluteTimeGetCurrent()
            counts[name, default: 0] += 1
            totalMs[name, default: 0] += elapsed
            if elapsed > (maxMs[name] ?? 0) { maxMs[name] = elapsed }
            startIfNeeded()
        }
        return result
    }

    static func recordHitch(_ name: String, at now: CFAbsoluteTime) {
        queue.async {
            guard let lastActivityAt,
                  now - lastActivityAt <= hitchActivityWindow,
                  counts.keys.contains(where: { !$0.hasPrefix("hitch>") })
            else { return }
            counts[name, default: 0] += 1
            startIfNeeded()
        }
    }

    private static func recordActivityIfNeeded(_ name: String) {
        guard !name.hasPrefix("hitch>") else { return }
        lastActivityAt = CFAbsoluteTimeGetCurrent()
    }

    private static func startIfNeeded() {
        guard !didStart else { return }
        didStart = true
        try? "".write(toFile: path, atomically: true, encoding: .utf8)
        // Timer.scheduledTimer needs a real run loop. The probe queue is
        // a serial DispatchQueue with no run loop attached, so schedule
        // the periodic flush on the main run loop instead.
        DispatchQueue.main.async {
            Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { _ in
                queue.async { flush() }
            }
            HitchProbe.start()
        }
    }

    private static func flush() {
        guard !counts.isEmpty else { return }
        let now = CFAbsoluteTimeGetCurrent()
        let window = max(0.001, now - windowStart)
        windowStart = now

        let keys = Set(counts.keys).union(totalMs.keys).sorted()
        guard keys.contains(where: { !$0.hasPrefix("hitch>") }) else {
            counts.removeAll(keepingCapacity: true)
            totalMs.removeAll(keepingCapacity: true)
            maxMs.removeAll(keepingCapacity: true)
            return
        }

        let stamp = String(format: "%.3f", Date().timeIntervalSince1970)
        let entries: [String] = keys.map { key in
            let c = counts[key] ?? 0
            if let total = totalMs[key] {
                let mx = maxMs[key] ?? 0
                return "\(key)=\(c) tot=\(fmt(total))ms mx=\(fmt(mx))ms"
            }
            return "\(key)=\(c)"
        }
        let line = "[\(stamp) Δ\(String(format: "%.2f", window))s] \(entries.joined(separator: "  "))\n"
        if let data = line.data(using: .utf8),
           let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        }
        counts.removeAll(keepingCapacity: true)
        totalMs.removeAll(keepingCapacity: true)
        maxMs.removeAll(keepingCapacity: true)
    }

    private static func fmt(_ value: Double) -> String {
        String(format: value < 10 ? "%.2f" : "%.1f", value)
    }
}

/// Detects main-thread stalls. A 60Hz timer logs the wall-clock delta
/// between fires; whenever that delta is much larger than 16.7ms the main
/// run loop was blocked. Buckets each hitch by severity so the render log
/// surfaces both "we dropped a couple of frames" and "the UI froze for a
/// quarter second" without flooding it with single-frame variance.
enum HitchProbe {
    nonisolated(unsafe) private static var lastTick: CFAbsoluteTime = 0
    nonisolated(unsafe) private static var didStart = false

    static func start() {
        guard !didStart else { return }
        didStart = true
        lastTick = CFAbsoluteTimeGetCurrent()
        // `.common` mode (instead of plain `.default`) so the probe keeps
        // ticking during scroll, window drag and other event tracking
        // phases — exactly the moments we most want to measure stalls.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in
            let now = CFAbsoluteTimeGetCurrent()
            let deltaMs = (now - lastTick) * 1000.0
            lastTick = now
            if deltaMs > 33 { RenderProbe.recordHitch("hitch>33ms", at: now) }
            if deltaMs > 100 { RenderProbe.recordHitch("hitch>100ms", at: now) }
            if deltaMs > 250 { RenderProbe.recordHitch("hitch>250ms", at: now) }
            if deltaMs > 1000 { RenderProbe.recordHitch("hitch>1000ms", at: now) }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}
