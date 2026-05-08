import Foundation
import os.signpost

/// Centralised performance signpost taxonomy.
///
/// Every hot path that wants to be visible in Instruments goes through
/// a `PerfSignpost` case instead of importing `os.signpost` directly.
/// The category name doubles as the lane Instruments shows in the
/// "os_signpost" track, so a trace lights up rows like `ui.chat`,
/// `ui.sidebar`, `ipc.client`, `render.markdown`, `resource`, etc.
///
/// Cost when active: each interval is one userspace boundary cross
/// (~50 ns) plus a few bytes in the unified-log ring buffer. When the
/// category is disabled at the kernel level, the signposter
/// short-circuits before any work happens. We additionally honour
/// `CLAWIX_DISABLE_SIGNPOSTS=1` for the rare case we want a release
/// build with zero signpost activity.
///
/// All hot paths live in this single file so the taxonomy is
/// discoverable. If you need to add a category, add it here, document
/// what it covers in `apps/macos/PERF.md`, and only then start
/// emitting from a call site.
enum PerfSignpost: String, CaseIterable {
    case uiChat = "ui.chat"
    case uiSidebar = "ui.sidebar"
    case stateAppState = "state.appstate"
    case ipcClient = "ipc.client"
    case renderMarkdown = "render.markdown"
    case renderStreaming = "render.streaming"
    case imageLoad = "image.load"
    case secretsCrypto = "secrets.crypto"
    case hang = "hang"
    case resource = "resource"

    private static let subsystem: String = Bundle.main.bundleIdentifier ?? "com.clawix.app"

    /// Master kill switch. Read once at process start; flipping it at
    /// runtime would require restarting the app.
    static let isSuppressed: Bool = {
        ProcessInfo.processInfo.environment["CLAWIX_DISABLE_SIGNPOSTS"] == "1"
    }()

    private static let signposters: [PerfSignpost: OSSignposter] = {
        var map: [PerfSignpost: OSSignposter] = [:]
        for category in PerfSignpost.allCases {
            map[category] = OSSignposter(subsystem: subsystem, category: category.rawValue)
        }
        return map
    }()

    var signposter: OSSignposter { Self.signposters[self]! }

    /// Wraps `block` in a begin/end pair Instruments renders as a
    /// coloured bar. Use for work whose duration is the actionable
    /// number (decode latency, parse cost, snapshot build time).
    @discardableResult
    @inline(__always)
    func interval<T>(_ name: StaticString, _ block: () throws -> T) rethrows -> T {
        guard !Self.isSuppressed else { return try block() }
        let sp = signposter
        let state = sp.beginInterval(name, id: sp.makeSignpostID())
        defer { sp.endInterval(name, state) }
        return try block()
    }

    /// Fire-and-forget point-in-time event. Use for things whose
    /// duration is meaningless (a delta arrived, a checkpoint was
    /// scheduled, a value crossed a threshold).
    @inline(__always)
    func event(_ name: StaticString) {
        guard !Self.isSuppressed else { return }
        signposter.emitEvent(name)
    }

    /// Event with an integer payload. Renders as `name=value` in the
    /// trace metadata column, which is enough for charting RSS,
    /// hitches, queue depths, etc., from Instruments without parsing
    /// log text.
    @inline(__always)
    func event(_ name: StaticString, _ value: Int) {
        guard !Self.isSuppressed else { return }
        signposter.emitEvent(name, "value=\(value)")
    }

    /// Event with a floating-point payload. Same shape as the Int
    /// overload; kept separate so call sites pick the right precision
    /// without losing it to an Int truncation.
    @inline(__always)
    func event(_ name: StaticString, _ value: Double) {
        guard !Self.isSuppressed else { return }
        signposter.emitEvent(name, "value=\(value)")
    }
}
