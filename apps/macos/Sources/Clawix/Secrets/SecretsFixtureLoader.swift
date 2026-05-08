import Foundation
import SecretsModels
import SecretsVault

/// Seeds the vault from a JSON fixture when `CLAWIX_SECRETS_FIXTURE` is
/// set. Used by dummy mode to populate hundreds of plausible fake
/// secrets through the same `store.createSecret` path the UI uses, so
/// values get encrypted with the live master key.
///
/// Idempotent: any entry whose `internalName` already exists in the
/// target vault is skipped, so re-launching dummy mode (which wipes
/// the vault dir but not the fixture file) reseeds cleanly.
///
/// Fixture shape (JSON array):
/// ```
/// [
///   {
///     "kind": "api_key",
///     "internalName": "openai_main",
///     "title": "OpenAI · main",
///     "brandPreset": "openai",
///     "tags": ["llm", "prod"],
///     "notes": "Optional free-form notes.",
///     "archived": false,
///     "compromised": false,
///     "fields": [
///       {
///         "name": "token",
///         "fieldKind": "password",
///         "placement": "header",
///         "isSecret": true,
///         "isConcealed": true,
///         "secretValue": "sk-..."
///       }
///     ]
///   }
/// ]
/// ```
enum SecretsFixtureLoader {
    static func loadIfNeeded(store: SecretsStore, vaults: [VaultRecord]) {
        guard
            let raw = ProcessInfo.processInfo.environment["CLAWIX_SECRETS_FIXTURE"],
            !raw.isEmpty
        else { return }
        let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
        guard let data = try? Data(contentsOf: url) else { return }
        let entries: [Entry]
        do {
            entries = try JSONDecoder().decode([Entry].self, from: data)
        } catch {
            return
        }
        guard let target = vaults.first else { return }

        let existing: Set<String> = (try? Set(store.listSecrets(includeTrashed: true).map { $0.internalName })) ?? []

        var seeded = 0
        for entry in entries where !existing.contains(entry.internalName) {
            do {
                let secret = try store.createSecret(in: target, draft: entry.toDraft())
                if entry.archived == true {
                    _ = try? store.updateTitle(secretId: secret.id, title: secret.title, archived: true)
                }
                if entry.compromised == true {
                    _ = try? store.setCompromised(id: secret.id, flag: true, reason: "fixture seed")
                }
                seeded += 1
            } catch {
                continue
            }
        }
        if seeded > 0 {
            FileHandle.standardError.write(Data("clawix: seeded \(seeded) fixture secret(s) from \(url.path)\n".utf8))
        }
    }
}

private struct Entry: Decodable {
    let kind: String
    let internalName: String
    let title: String
    let brandPreset: String?
    let tags: [String]?
    let notes: String?
    let archived: Bool?
    let compromised: Bool?
    let fields: [Field]?

    func toDraft() -> DraftSecret {
        let resolvedKind = SecretKind(rawValue: kind) ?? .secureNote
        let draftFields = (fields ?? []).enumerated().map { idx, f -> DraftField in
            DraftField(
                name: f.name,
                fieldKind: FieldKind(rawValue: f.fieldKind ?? "password") ?? .password,
                placement: FieldPlacement(rawValue: f.placement ?? "none") ?? .none,
                isSecret: f.isSecret ?? true,
                isConcealed: f.isConcealed ?? true,
                publicValue: f.publicValue,
                secretValue: f.secretValue,
                sortOrder: idx
            )
        }
        return DraftSecret(
            kind: resolvedKind,
            brandPreset: brandPreset,
            internalName: internalName,
            title: title,
            fields: draftFields,
            notes: notes,
            tags: tags ?? []
        )
    }
}

private struct Field: Decodable {
    let name: String
    let fieldKind: String?
    let placement: String?
    let isSecret: Bool?
    let isConcealed: Bool?
    let publicValue: String?
    let secretValue: String?
}
