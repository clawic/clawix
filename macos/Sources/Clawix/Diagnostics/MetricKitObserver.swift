import Foundation
import MetricKit
import os

/// Subscriber that captures every `MXMetricPayload` and
/// `MXDiagnosticPayload` Apple delivers and persists the JSON to
/// `~/Library/Application Support/<bundleId>/Diagnostics/` so a
/// post-mortem investigation has a stable artifact.
///
/// MetricKit is the only API that gives `MXAppLaunchMetric`,
/// `MXHangDiagnostic` (with symbolicated backtraces),
/// `MXAppExitMetric`, and `MXAnimationMetric` (hitch ratio) - Apple
/// computes them on-device using the same telemetry the App Store
/// dashboard sees, so it is a free second source independent from
/// our own samplers.
///
/// Always-on by design: payloads land at most once per ~24 h, so the
/// runtime cost of being subscribed is essentially zero. The observer
/// is registered from `AppDelegate.applicationDidFinishLaunching`.
final class MetricKitObserver: NSObject, @unchecked Sendable {
    static let shared = MetricKitObserver()

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.clawix.app",
        category: "metrickit"
    )

    func install() {
        MXMetricManager.shared.add(self)
    }

    private static let stampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    fileprivate func persist(_ data: Data, prefix: String) {
        // Replace `:` so the file name is friendly on case-insensitive
        // file systems and easy to copy-paste into a shell.
        let stamp = Self.stampFormatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let name = "\(prefix)-\(stamp).json"
        guard let url = ResourceSampler.diagnosticsFileURL(named: name) else {
            Self.log.error("MetricKit: cannot resolve diagnostics dir for \(prefix, privacy: .public)")
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            Self.log.info(
                "MetricKit \(prefix, privacy: .public) saved at \(url.path, privacy: .public) (\(data.count, privacy: .public) bytes)"
            )
        } catch {
            Self.log.error(
                "MetricKit \(prefix, privacy: .public) write failed: \(String(describing: error), privacy: .public)"
            )
        }
    }
}

extension MetricKitObserver: MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            persist(payload.jsonRepresentation(), prefix: "metrics")
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            persist(payload.jsonRepresentation(), prefix: "diagnostics")
        }
    }
}
