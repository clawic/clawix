import Foundation

final class AndroidPipeCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }
}

struct AndroidToolResult {
    let status: Int32
    let stdout: String
    let stdoutData: Data
    let stderr: String
}

struct AndroidToolchain {
    let adbPath: String
    let emulatorPath: String?
    let avds: [AndroidAVDChoice]
}

struct AndroidEmulatorDevice: Equatable {
    let serial: String
    let state: String
    let avdName: String?

    var displayName: String {
        if let avdName, !avdName.isEmpty { return AndroidDeviceNameFormatter.displayName(for: avdName) }
        return serial
    }
}

struct AndroidAVDConfig: Equatable {
    let width: Int?
    let height: Int?
    let deviceName: String?
}

struct AndroidAVDChoice: Identifiable, Equatable, Comparable {
    let id: String
    let name: String
    let config: AndroidAVDConfig

    init(name: String, config: AndroidAVDConfig) {
        self.id = name
        self.name = name
        self.config = config
    }

    var displayName: String {
        AndroidDeviceNameFormatter.displayName(
            for: (config.deviceName?.isEmpty == false ? config.deviceName : nil) ?? name
        )
    }

    var menuTitle: String {
        if let width = config.width, let height = config.height {
            return "\(displayName) · \(width)x\(height)"
        }
        return displayName
    }

    static func < (lhs: AndroidAVDChoice, rhs: AndroidAVDChoice) -> Bool {
        let lhsTablet = lhs.isTablet
        let rhsTablet = rhs.isTablet
        if lhsTablet != rhsTablet { return !lhsTablet && rhsTablet }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private var isTablet: Bool {
        let lower = "\(name) \(config.deviceName ?? "")".lowercased()
        if lower.contains("tablet") || lower.contains("fold") { return true }
        if let width = config.width, let height = config.height {
            return max(width, height) >= 1800 && min(width, height) >= 1200
        }
        return false
    }
}

enum AndroidDeviceNameFormatter {
    static func displayName(for raw: String) -> String {
        raw
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map(formatToken)
            .joined(separator: " ")
    }

    private static func formatToken(_ token: Substring) -> String {
        let raw = String(token)
        let lower = raw.lowercased()
        switch lower {
        case "avd": return "AVD"
        case "api": return "API"
        case "pixel": return "Pixel"
        case "nexus": return "Nexus"
        case "tablet": return "Tablet"
        default:
            if lower.allSatisfy(\.isNumber) { return lower }
            if lower.count <= 2 { return lower.uppercased() }
            return lower.prefix(1).uppercased() + lower.dropFirst()
        }
    }
}

enum AndroidSimulatorError: LocalizedError {
    case noAVD
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAVD:
            return "No Android Virtual Devices were found. Create phone and tablet AVDs with Android Studio or avdmanager."
        case .commandFailed(let message):
            return message.isEmpty ? "Android command failed." : message
        }
    }
}
