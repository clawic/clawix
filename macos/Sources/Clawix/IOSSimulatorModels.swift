import Foundation

enum IOSSimulatorPointerPhase {
    case began
    case moved
    case ended
}

struct IOSSimulatorNativeDisplayDescriptor: Equatable {
    let deviceUDID: String
    let deviceName: String
}

struct ToolResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

struct SimDevice: Equatable {
    let runtime: String
    let name: String
    let udid: String
    let state: String
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
