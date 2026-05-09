import Foundation
import Darwin
import os

/// Periodically samples process resident memory, physical footprint and
/// CPU usage. Each tick is emitted as a signpost event in the `resource`
/// category so traces correlate spikes against whatever else is running
/// at the same wall-clock. The most recent sample is also persisted to
/// `~/Library/Application Support/<bundleId>/Diagnostics/last-resources.json`
/// when the app exits so a post-mortem investigation can read the final
/// state without relaunching.
///
/// Boot from `AppDelegate.applicationDidFinishLaunching`; persist on
/// `applicationWillTerminate`. Always-on, ~10 µs per tick.
enum ResourceSampler {
    private static let queue = DispatchQueue(label: "clawix.diag.sampler", qos: .utility)
    nonisolated(unsafe) private static var timer: DispatchSourceTimer?
    nonisolated(unsafe) private static var lastTotalTicks: UInt64 = 0
    nonisolated(unsafe) private static var lastIdleTicks: UInt64 = 0
    nonisolated(unsafe) private static var lastSample: Sample?

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.clawix.app",
        category: "resource-sampler"
    )

    struct Sample: Codable {
        let timestamp: TimeInterval
        let residentBytes: UInt64
        let footprintBytes: UInt64
        /// Process CPU usage, normalised so 100 = one fully busy core.
        /// On a hex-core machine the realistic max is therefore ~600.
        let processCpuPercent: Double
        let appVersion: String?
        let buildNumber: String?
    }

    static func start() {
        queue.async {
            guard timer == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + 1.0, repeating: 1.0, leeway: .milliseconds(200))
            t.setEventHandler { tick() }
            t.resume()
            timer = t
        }
    }

    static func stop() {
        queue.async {
            timer?.cancel()
            timer = nil
        }
    }

    /// Persists the most recent sample to disk. Call from
    /// `applicationWillTerminate` so a post-mortem read of "what did
    /// the process look like before it shut down" is one `cat` away.
    static func persistLastSample() {
        // Capture the tail value off the sampler queue so we don't
        // serialise on the main thread; small, atomic, fine to block
        // for a few hundred microseconds at exit time.
        queue.sync {
            guard let sample = lastSample else { return }
            guard let url = diagnosticsFileURL(named: "last-resources.json") else { return }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(sample) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    /// Resolves `~/Library/Application Support/<bundleId>/Diagnostics/<name>`,
    /// creating the directory tree if needed. Returns nil on sandbox
    /// or filesystem errors (the caller should treat that as "no
    /// diagnostics dump this run", not a fatal condition).
    static func diagnosticsFileURL(named name: String) -> URL? {
        let fm = FileManager.default
        let bundleId = Bundle.main.bundleIdentifier ?? "clawix.desktop"
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = support
            .appendingPathComponent(bundleId, isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        return dir.appendingPathComponent(name)
    }

    private static func tick() {
        let resident = residentSize()
        let footprintBytes = footprint()
        let cpuPct = processCpuPercent()
        let info = Bundle.main.infoDictionary
        let sample = Sample(
            timestamp: Date().timeIntervalSince1970,
            residentBytes: resident,
            footprintBytes: footprintBytes,
            processCpuPercent: cpuPct,
            appVersion: info?["CFBundleShortVersionString"] as? String,
            buildNumber: info?["CFBundleVersion"] as? String
        )
        lastSample = sample
        // Each metric is its own event so Instruments charts the values
        // straight from the trace, no log parsing required.
        PerfSignpost.resource.event("rss_mb", Int(resident / 1024 / 1024))
        PerfSignpost.resource.event("footprint_mb", Int(footprintBytes / 1024 / 1024))
        PerfSignpost.resource.event("cpu_pct", cpuPct)
    }

    // MARK: - Mach calls

    private static func residentSize() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size
        )
        let kerr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    intPtr,
                    &count
                )
            }
        }
        return kerr == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }

    private static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let kerr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    intPtr,
                    &count
                )
            }
        }
        return kerr == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }

    /// Aggregates per-thread CPU usage (`thread_basic_info.cpu_usage`)
    /// across all live threads of the current process. Mirrors what
    /// Activity Monitor's "%CPU" column reports: one fully busy core
    /// reads as 100, an 8-thread saturated process can hit ~800. The
    /// `TH_USAGE_SCALE` constant is the kernel's fixed-point scale.
    private static func processCpuPercent() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let kerr = task_threads(mach_task_self_, &threadList, &threadCount)
        guard kerr == KERN_SUCCESS, let threads = threadList else { return 0 }
        defer {
            // `threads` is the base of the thread-id array allocated
            // by the kernel for us; vm_deallocate releases that page.
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: threads)),
                vm_size_t(MemoryLayout<thread_t>.size * Int(threadCount))
            )
        }
        var total: Double = 0
        for i in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(
                MemoryLayout<thread_basic_info>.size / MemoryLayout<natural_t>.size
            )
            let res = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
                ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                    thread_info(
                        threads[i],
                        thread_flavor_t(THREAD_BASIC_INFO),
                        intPtr,
                        &count
                    )
                }
            }
            if res == KERN_SUCCESS, (info.flags & TH_FLAGS_IDLE) == 0 {
                total += (Double(info.cpu_usage) / Double(TH_USAGE_SCALE)) * 100.0
            }
        }
        return total
    }
}
