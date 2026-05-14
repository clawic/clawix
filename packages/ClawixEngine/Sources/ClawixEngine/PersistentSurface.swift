import Foundation

public enum ClawixPersistentSurfaceAPI {
    public static let publicApiPrefix = "/v1"

    public static func path(_ suffix: String) -> String {
        "\(publicApiPrefix)\(suffix)"
    }
}

public enum ClawixPersistentSurfaceKeys {
    public static let dictationActiveModel = "dictation.activeModel"
    public static let bridgeBearer = "ClawixBridge.Bearer.v1"
    public static let bridgeShortCode = "ClawixBridge.ShortCode.v1"
    public static let bridgeCoordinatorURL = "ClawixBridge.Coordinator.URL.v1"
    public static let bridgeIrohNodeID = "ClawixBridge.Iroh.NodeID.v1"
}

public enum ClawixPersistentSurfacePathComponents {
    public static let applicationSupportName = "Clawix"
    public static let audioDirectory = "audio"
    public static let audioMetadataFile = "audio-meta.json"
    public static let meshHome = ".clawix/mesh"
}
