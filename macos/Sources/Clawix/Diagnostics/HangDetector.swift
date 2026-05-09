import Foundation
import CoreFoundation
import os

/// DEBUG-only main-thread hang detector.
///
/// Listens to runloop activity transitions on `.commonModes` and
/// records when the main thread enters a "processing" phase. A guard
/// thread polling at 100 ms decides the main thread has been stuck if
/// `now - enteredAt > thresholdMs` (default 250 ms, override via
/// `CLAWIX_HANG_MS=<int>`). On detection it emits a signpost in the
/// `hang` category, a `Logger.warning`, and schedules a post-resume
/// `Thread.callStackSymbols` capture so the trace shows what the main
/// thread was doing right after the stall released.
///
/// Why not rely on `RenderProbe.HitchProbe`? `HitchProbe` samples
/// post-frame at 60 Hz on the main runloop's timer mode, so it cannot
/// see stalls during scroll / window drag (event-tracking mode), or
/// any synchronous block that holds the runloop past frame
/// boundaries. `HangDetector` watches every runloop cycle on every
/// common mode, including event tracking.
///
/// Intentionally `#if DEBUG` by default. Override with
/// `CLAWIX_FORCE_HANG_DETECTOR=1` if you need it in a release build
/// for an in-the-wild repro.
enum HangDetector {
    nonisolated(unsafe) private static var observer: CFRunLoopObserver?
    nonisolated(unsafe) private static var enteredAt: CFAbsoluteTime = 0
    nonisolated(unsafe) private static var lastReportedAt: CFAbsoluteTime = 0
    nonisolated(unsafe) private static var guardTimer: DispatchSourceTimer?
    private static let guardQueue = DispatchQueue(label: "clawix.diag.hang", qos: .utility)

    static let thresholdMs: Double = {
        if let raw = ProcessInfo.processInfo.environment["CLAWIX_HANG_MS"],
           let value = Double(raw), value > 0 {
            return value
        }
        return 250
    }()

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.clawix.app",
        category: "hang"
    )

    static func start() {
        // Apple's recommendation is "investigate hangs in development";
        // always-on detection in release means every customer device
        // pays the runloop observer cost. Gate explicitly.
        #if !DEBUG
        let force = ProcessInfo.processInfo.environment["CLAWIX_FORCE_HANG_DETECTOR"] == "1"
        guard force else { return }
        #endif

        guard observer == nil else { return }

        let activities: CFRunLoopActivity = [
            .entry, .beforeTimers, .beforeSources, .afterWaiting, .beforeWaiting, .exit
        ]

        // `order: 999_999` runs the observer AFTER everyone else in the
        // same activity slot, so the timestamp brackets the actual
        // user-code work the runloop is about to do (or just did).
        let cfActivities = CFRunLoopActivity(rawValue: activities.rawValue)
        observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            cfActivities.rawValue,
            true,
            999_999
        ) { _, activity in
            switch activity {
            case .beforeTimers, .beforeSources, .afterWaiting:
                enteredAt = CFAbsoluteTimeGetCurrent()
            case .beforeWaiting, .exit:
                enteredAt = 0
            default:
                break
            }
        }
        if let observer {
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }

        let timer = DispatchSource.makeTimerSource(queue: guardQueue)
        timer.schedule(
            deadline: .now() + 0.1,
            repeating: 0.1,
            leeway: .milliseconds(50)
        )
        timer.setEventHandler {
            let entered = enteredAt
            guard entered > 0 else { return }
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - entered) * 1000.0
            // Only re-report if the main thread resumed and stalled
            // again on a different cycle. Otherwise a 5 s freeze would
            // log fifty identical warnings as the guard polls.
            guard elapsedMs > thresholdMs, entered != lastReportedAt else { return }
            lastReportedAt = entered
            report(elapsedMs: elapsedMs)
        }
        timer.resume()
        guardTimer = timer
    }

    private static func report(elapsedMs: Double) {
        let ms = Int(elapsedMs)
        let threshold = Int(thresholdMs)
        PerfSignpost.hang.event("main-stalled", ms)
        log.warning(
            "main thread stalled \(ms, privacy: .public) ms (threshold \(threshold, privacy: .public) ms)"
        )
        // Capture the post-resume main-thread stack. By the time this
        // closure runs the stall has unblocked, so the symbols
        // describe what the main thread is doing right after release.
        // Imperfect (the actual culprit may already have returned) but
        // useful as a first pass without entitlements; pair with an
        // Instruments Time Profiler trace for the live picture.
        DispatchQueue.main.async {
            let symbols = Thread.callStackSymbols.prefix(20).joined(separator: "\n")
            log.warning("post-stall main stack:\n\(symbols, privacy: .public)")
        }
    }
}
