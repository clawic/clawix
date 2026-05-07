import Foundation

/// User-set display names for projects, keyed by `cwd`. Lives in
/// UserDefaults rather than the snapshot file so it survives the
/// snapshot getting nuked (cache rebuilds, dummy mode toggles, etc.):
/// the user already chose this name and would not expect it to be
/// blown away by an internal cache reset.
///
/// The daemon does not yet model project entities, so this override
/// is local to the iPhone. When the bridge eventually grows a
/// `renameProject` frame, this map can be the optimistic side and the
/// daemon's reply becomes the canonical source.
enum ProjectLabelsCache {
    private static let key = "Clawix.ProjectLabels.v1"

    static func load() -> [String: String] {
        guard let raw = UserDefaults.standard.dictionary(forKey: key) else { return [:] }
        var out: [String: String] = [:]
        for (k, v) in raw {
            if let s = v as? String { out[k] = s }
        }
        return out
    }

    static func save(_ labels: [String: String]) {
        if labels.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(labels, forKey: key)
        }
    }
}
