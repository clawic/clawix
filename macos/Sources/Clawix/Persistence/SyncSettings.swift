import Foundation

// User-facing toggles that control whether app actions are mirrored to
// the underlying runtime (Codex CLI today). The local SQLite store is
// always the canonical source of truth for what the app shows; these
// flags only gate the side-effect of also writing to the runtime.
//
// Stored in UserDefaults under the standard app prefs suite, mirroring
// the convention used by PreferredLanguage and the sidebar toggles.
enum SyncSettings {
    private static let store: UserDefaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard
    private static let archiveKey = "SyncArchiveWithCodex"
    private static let renamesKey = "SyncRenamesWithCodex"
    private static let autoReloadKey = "AutoReloadOnFocus"

    static var syncArchiveWithCodex: Bool {
        get { store.object(forKey: archiveKey) as? Bool ?? true }
        set { store.set(newValue, forKey: archiveKey) }
    }

    static var syncRenamesWithCodex: Bool {
        get { store.object(forKey: renamesKey) as? Bool ?? true }
        set { store.set(newValue, forKey: renamesKey) }
    }

    static var autoReloadOnFocus: Bool {
        get { store.object(forKey: autoReloadKey) as? Bool ?? true }
        set { store.set(newValue, forKey: autoReloadKey) }
    }
}
