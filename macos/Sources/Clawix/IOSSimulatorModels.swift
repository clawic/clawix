import Foundation
import CoreGraphics

enum IOSSimulatorPointerPhase {
    case began
    case moved
    case ended
}

struct IOSSimulatorNativeDisplayDescriptor: Equatable {
    let deviceUDID: String
    let deviceName: String
    let aspectRatio: CGFloat
}

struct ToolResult: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String
}

struct SimDevice: Equatable {
    let runtime: String
    let name: String
    let udid: String
    let state: String

    var isPhone: Bool { name.localizedCaseInsensitiveContains("iPhone") }
}

struct IOSSimulatorDeviceChoice: Identifiable, Equatable {
    let id: String
    let udid: String
    let name: String
    let runtime: String
    let isBooted: Bool

    init(device: SimDevice) {
        self.id = device.udid
        self.udid = device.udid
        self.name = device.name
        self.runtime = device.runtime
        self.isBooted = device.state == "Booted"
    }

    var menuTitle: String {
        let suffix = isBooted ? " · booted" : ""
        return "\(name)\(suffix)"
    }
}

struct SimctlDeviceList: Decodable {
    let devices: [String: [SimctlDevice]]
}

struct SimctlDevice: Decodable {
    let name: String
    let udid: String
    let state: String
}

enum SimulatorError: LocalizedError {
    case noDevice
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDevice:
            return "No available iPhone simulator was found. Install an iOS runtime in Xcode."
        case .commandFailed(let message):
            return message.isEmpty ? "The simulator command failed." : message
        }
    }
}
