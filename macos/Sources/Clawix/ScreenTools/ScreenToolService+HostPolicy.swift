import Foundation

extension ScreenToolService {
    func authorize(_ action: String, origin: HostActionOrigin = .userInterface) -> Bool {
        let authorization = HostActionPolicy.authorize(
            surface: .screenTools,
            action: action,
            origin: origin
        )
        if !authorization.allowed {
            ToastCenter.shared.show(authorization.reason ?? "Action blocked by host policy", icon: .warning)
        }
        return authorization.allowed
    }
}
