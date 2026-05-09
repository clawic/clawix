import Foundation

enum AppVersion {
    static let marketing: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }()

    static let build: String = {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }()

    static var displayString: String {
        "\(marketing) (\(build))"
    }
}
