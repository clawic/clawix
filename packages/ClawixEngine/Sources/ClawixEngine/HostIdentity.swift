import Foundation

enum HostIdentity {
    static var localizedName: String? {
        #if os(macOS)
        Host.current().localizedName
        #else
        let name = ProcessInfo.processInfo.hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
        #endif
    }
}
