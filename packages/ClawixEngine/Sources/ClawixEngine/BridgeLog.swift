import Foundation

/// Shared stderr logger for the bridge code paths. Writes go through
/// the same `[clawix-bridge]` prefix the daemon already uses so the
/// reader script that watches `/private/tmp/clawix-bridged.err` and
/// `clawix logs` doesn't need to learn a second format. The macOS GUI
/// also calls into this when it spins up an in-process `BridgeServer`,
/// which lands those lines in the GUI's own stderr (visible in
/// Console.app under the `Clawix` process).
public enum BridgeLog {
    public static func write(_ message: String) {
        let safe = redact(message)
        FileHandle.standardError.write(Data(("[clawix-bridge] \(safe)\n").utf8))
    }

    /// Redact obvious bearer-token-shaped substrings (any 32+ alnum
    /// run that isn't part of a longer alnum word) and the user's
    /// home path so logs we ship into screenshots / bug reports don't
    /// leak secrets or local paths. Mirrors `BridgedLog.redact` from
    /// `clawix-bridged/main.swift`.
    private static func redact(_ s: String) -> String {
        let patterns = [
            "(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{32,}(?![A-Za-z0-9_-])",
            NSHomeDirectory().replacingOccurrences(of: "/", with: "\\/")
        ]
        return patterns.reduce(s) { current, pattern in
            guard let re = try? NSRegularExpression(pattern: pattern) else { return current }
            let range = NSRange(current.startIndex..., in: current)
            let replacement = pattern.hasPrefix("(?<!") ? "<redacted>" : "~"
            return re.stringByReplacingMatches(in: current, range: range, withTemplate: replacement)
        }
    }
}
