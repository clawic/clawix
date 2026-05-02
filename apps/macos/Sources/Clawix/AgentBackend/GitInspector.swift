import Foundation

// Lightweight git probe for a working directory. Used to populate the
// chat footer branch pill (current branch, list of local branches,
// number of uncommitted files). Reads `.git/HEAD` + `.git/refs/heads`
// directly and shells out to `git status` only for the dirty file
// count — keeps it cheap enough to call once per chat at load time.

struct GitSnapshot {
    let hasRepo: Bool
    let branch: String?
    let branches: [String]
    let uncommittedFiles: Int?

    static let empty = GitSnapshot(hasRepo: false, branch: nil, branches: [], uncommittedFiles: nil)
}

enum GitInspector {

    static func inspect(cwd: String?) -> GitSnapshot {
        guard let cwd, !cwd.isEmpty else { return .empty }
        let expanded = (cwd as NSString).expandingTildeInPath
        let fm = FileManager.default

        // Walk up looking for `.git`. Clawix sessions can be started in a
        // subdirectory of the repo, so we don't require `.git` to live at
        // exactly `cwd`.
        var dir = URL(fileURLWithPath: expanded, isDirectory: true)
        var gitRoot: URL? = nil
        for _ in 0..<8 {
            let candidate = dir.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                gitRoot = candidate
                break
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }

        guard let gitRoot else { return .empty }

        let branch = readHEADBranch(gitDir: gitRoot)
        let branches = listLocalBranches(gitDir: gitRoot, current: branch)
        let dirty = countUncommittedFiles(at: dir.path)

        return GitSnapshot(
            hasRepo: true,
            branch: branch,
            branches: branches,
            uncommittedFiles: dirty
        )
    }

    private static func readHEADBranch(gitDir: URL) -> String? {
        let head = gitDir.appendingPathComponent("HEAD")
        guard let raw = try? String(contentsOf: head, encoding: .utf8) else { return nil }
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("ref: refs/heads/") {
            return String(line.dropFirst("ref: refs/heads/".count))
        }
        // Detached HEAD: just show the short SHA.
        return String(line.prefix(7))
    }

    private static func listLocalBranches(gitDir: URL, current: String?) -> [String] {
        var out: [String] = []
        let fm = FileManager.default

        // Loose refs under .git/refs/heads/**.
        let headsRoot = gitDir.appendingPathComponent("refs/heads", isDirectory: true)
        if let enumerator = fm.enumerator(at: headsRoot, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let url as URL in enumerator {
                let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
                guard isFile else { continue }
                let rel = url.path.replacingOccurrences(of: headsRoot.path + "/", with: "")
                if !rel.isEmpty { out.append(rel) }
            }
        }

        // Packed refs (a single `packed-refs` file is common in older repos
        // and after `git gc`).
        let packed = gitDir.appendingPathComponent("packed-refs")
        if let raw = try? String(contentsOf: packed, encoding: .utf8) {
            for line in raw.split(separator: "\n") {
                let parts = line.split(separator: " ")
                guard parts.count >= 2 else { continue }
                let ref = String(parts[1])
                if ref.hasPrefix("refs/heads/") {
                    out.append(String(ref.dropFirst("refs/heads/".count)))
                }
            }
        }

        // Dedup, surface the current branch first.
        var seen = Set<String>()
        var ordered: [String] = []
        if let current, !current.isEmpty {
            ordered.append(current)
            seen.insert(current)
        }
        for b in out.sorted() where !seen.contains(b) {
            ordered.append(b)
            seen.insert(b)
        }
        return ordered
    }

    private static func countUncommittedFiles(at workingDirectory: String) -> Int? {
        let proc = Process()
        proc.launchPath = "/usr/bin/env"
        proc.arguments = ["git", "status", "--porcelain"]
        proc.currentDirectoryPath = workingDirectory

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()

        do {
            try proc.run()
        } catch {
            return nil
        }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return 0 }
        let lines = text.split(separator: "\n").filter { !$0.isEmpty }
        return lines.count
    }
}
