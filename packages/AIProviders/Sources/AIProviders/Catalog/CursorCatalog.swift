import Foundation

public enum CursorCatalog {
    public static let definition = ProviderDefinition(
        id: .cursor,
        displayName: "Cursor",
        tagline: "API access via your Cursor account. OAuth not yet public.",
        authMethods: [.apiKey],
        defaultBaseURL: URL(string: "https://api.cursor.sh/v1"),
        supportsCustomBaseURL: false,
        docsURL: URL(string: "https://www.cursor.com/settings")!,
        brand: ProviderBrand(monogram: "C", colorHex: "#000000"),
        models: [
            ModelDefinition(
                id: "cursor-fast",
                providerId: .cursor,
                displayName: "Cursor Fast",
                capabilities: [.chat],
                isDefaultFor: [.chat]
            ),
            ModelDefinition(
                id: "cursor-small",
                providerId: .cursor,
                displayName: "Cursor Small",
                capabilities: [.chat]
            )
        ],
        notes: "Generate an API key in cursor.com → Settings → API."
    )
}
