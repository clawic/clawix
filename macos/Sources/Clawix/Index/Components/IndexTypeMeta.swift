import SwiftUI

/// Per-type display metadata used by the type sidebar, the cards and
/// the detail panes. Mirrors what `@clawjs/index` ships in `uiHints`
/// but renders client-side via Lucide + project palette so the surface
/// stays consistent even when the type was declared by an agent at
/// runtime without `uiHints`.
struct IndexTypeMeta: Equatable, Hashable {
    let typeName: String
    let displayName: String
    let lucideName: String
    let accent: Color
    let kind: Kind

    enum Kind: String, Hashable {
        case media
        case text
        case data
    }
}

enum IndexTypeCatalog {
    static let canonicalOrder: [String] = [
        "product", "listing", "article", "post", "video", "episode",
        "paper", "profile", "place", "channel", "doc", "repo",
        "event", "job", "review",
    ]

    static let known: [String: IndexTypeMeta] = [
        "product": .init(typeName: "product",  displayName: "Products",  lucideName: "shopping_bag", accent: Color(red: 1.00, green: 0.61, blue: 0.42), kind: .media),
        "listing": .init(typeName: "listing",  displayName: "Listings",  lucideName: "bed_double",    accent: Color(red: 0.48, green: 0.66, blue: 1.00), kind: .media),
        "article": .init(typeName: "article",  displayName: "Articles",  lucideName: "newspaper",     accent: Color(red: 0.77, green: 0.64, blue: 0.42), kind: .text),
        "post":    .init(typeName: "post",     displayName: "Posts",     lucideName: "message_square",accent: Color(red: 0.63, green: 0.54, blue: 1.00), kind: .text),
        "video":   .init(typeName: "video",    displayName: "Videos",    lucideName: "play",          accent: Color(red: 1.00, green: 0.43, blue: 0.43), kind: .media),
        "episode": .init(typeName: "episode",  displayName: "Episodes",  lucideName: "headphones",    accent: Color(red: 0.71, green: 0.42, blue: 1.00), kind: .media),
        "paper":   .init(typeName: "paper",    displayName: "Papers",    lucideName: "file_text",     accent: Color(red: 0.37, green: 0.75, blue: 0.60), kind: .text),
        "profile": .init(typeName: "profile",  displayName: "Profiles",  lucideName: "user",          accent: Color(red: 1.00, green: 0.71, blue: 0.42), kind: .media),
        "place":   .init(typeName: "place",    displayName: "Places",    lucideName: "map_pin",       accent: Color(red: 1.00, green: 0.54, blue: 0.65), kind: .media),
        "channel": .init(typeName: "channel",  displayName: "Channels",  lucideName: "radio",         accent: Color(red: 0.42, green: 0.82, blue: 0.88), kind: .text),
        "doc":     .init(typeName: "doc",      displayName: "Docs",      lucideName: "book_open",     accent: Color(red: 0.54, green: 0.66, blue: 0.85), kind: .text),
        "repo":    .init(typeName: "repo",     displayName: "Repos",     lucideName: "github",        accent: Color(red: 0.60, green: 0.64, blue: 0.70), kind: .text),
        "event":   .init(typeName: "event",    displayName: "Events",    lucideName: "calendar",      accent: Color(red: 0.94, green: 0.56, blue: 0.42), kind: .media),
        "job":     .init(typeName: "job",      displayName: "Jobs",      lucideName: "briefcase",     accent: Color(red: 0.53, green: 0.73, blue: 0.52), kind: .text),
        "review":  .init(typeName: "review",   displayName: "Reviews",   lucideName: "star",          accent: Color(red: 1.00, green: 0.81, blue: 0.43), kind: .text),
    ]

    static func meta(for typeName: String) -> IndexTypeMeta {
        if let canonical = known[typeName] { return canonical }
        return IndexTypeMeta(
            typeName: typeName,
            displayName: typeName.capitalized,
            lucideName: "tag",
            accent: Color(white: 0.66),
            kind: .data
        )
    }

    static func lucideImage(for typeName: String, size: CGFloat = 14) -> some View {
        let meta = meta(for: typeName)
        return Image(lucideOrSystem: meta.lucideName)
            .font(.system(size: size, weight: .medium))
    }
}
