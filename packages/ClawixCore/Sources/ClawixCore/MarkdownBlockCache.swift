import Foundation

/// Process-wide cache for parsed markdown block lists, keyed by the
/// exact source string. Both the iOS `AssistantMarkdownView` and the
/// macOS `AssistantMarkdownText` parse user-visible chunks of markdown
/// at body-evaluation time; both pay the same cost to reparse a settled
/// message every time SwiftUI re-runs an ancestor body. NSCache makes
/// the lookup O(1), the keys are byte-equal source strings (so any
/// streaming delta on a *different* message is a no-op), and eviction
/// kicks in automatically under memory pressure.
///
/// Generic over the parsed block type because the two platforms use
/// different parsers and different block models — iOS emits its own
/// `AssistantBlock`, macOS emits `AnnotatedBlock` carrying streaming
/// fade offsets. The cache itself doesn't care: it stores whatever the
/// caller hands it, keyed by source string.
///
/// Designed to live as a `static let` singleton on each platform's
/// renderer (NOT inside a `@StateObject`/`@State`). Per-view caches die
/// when the view unmounts, which is exactly what we don't want here:
/// closing and reopening a chat throws every parse away and the user
/// pays the reparse cost on every open.
public final class MarkdownBlockCache<Block>: @unchecked Sendable {
    /// `NSCache` only stores `AnyObject` values, so wrap whatever block
    /// list the caller hands us in a thin reference box. The box is
    /// `final` so `NSCache`'s internal accounting stays predictable.
    private final class Box {
        let value: Block
        init(_ value: Block) { self.value = value }
    }

    private let storage: NSCache<NSString, Box> = NSCache<NSString, Box>()

    public init(countLimit: Int = 64) {
        storage.countLimit = countLimit
    }

    /// Retrieve a cached parse if one exists. `nil` means "miss, parse
    /// and call `set`."
    public func get(for source: String) -> Block? {
        storage.object(forKey: source as NSString)?.value
    }

    /// Insert a parse result. Overwrites any previous entry for the
    /// same source (no-op when the source is byte-equal because the new
    /// box wraps the same blocks).
    public func set(_ value: Block, for source: String) {
        storage.setObject(Box(value), forKey: source as NSString)
    }

    /// Convenience: cache-aware parse. The closure runs only on a miss
    /// and the result is memoized for future calls with the same source.
    public func parse(_ source: String, _ produce: (String) -> Block) -> Block {
        if let hit = get(for: source) { return hit }
        let value = produce(source)
        set(value, for: source)
        return value
    }
}
