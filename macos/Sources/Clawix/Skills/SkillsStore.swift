import Foundation
import Combine

/// Owns the catalog of skills exposed in the Skills page and the active
/// set per scope. Source of truth lives in ClawJS (single central
/// library at `~/.clawjs/skills/<kind>/<slug>/SKILL.md`), but Clawix
/// holds a hot copy here so the UI stays responsive and reflects edits
/// the moment the user makes them.
///
/// Wire transport: today the store works with seed data + UserDefaults
/// so the UI is testable end-to-end without a daemon. When the bridge
/// frames v6 land, `bind(daemon:)` swaps the local backend for the
/// real one and the seed becomes a no-op fallback.
@MainActor
final class SkillsStore: ObservableObject {

    // MARK: - Public state

    /// Full catalog: built-ins + user-created + imported, regardless of
    /// whether they're active. The Skills page renders this.
    @Published private(set) var catalog: [SkillSpec] = []

    /// Active skills keyed by scope tag ("global" | "project:<id>" |
    /// "chat:<id>"). The runtime resolves the effective set per chat by
    /// merging in priority order (chat > project > global).
    @Published private(set) var activeByScope: [String: [ActiveSkillState]] = [:]

    /// Sync targets configured for distribution to external agents
    /// (Codex CLI, HermesAgent, Cursor projects, ...).
    @Published private(set) var syncTargets: [SkillSyncTarget] = []

    /// Free-text search query. Filtering happens at the view layer.
    @Published var searchQuery: String = ""

    /// Active filter pills, set by the catalog page.
    @Published var kindFilter: SkillKind? = nil
    @Published var scopeFilter: SkillScopeKind? = nil
    @Published var tagFilter: String? = nil

    /// Last sync run, surfaced as "Last synced 2m ago" in the UI.
    @Published private(set) var lastSyncedAt: Date?

    /// Set to non-nil when an async op is in flight (UI shows a spinner).
    @Published private(set) var pendingOperation: String?

    // MARK: - Init / seed

    init(seedBuiltins: Bool = true) {
        if seedBuiltins {
            installSeedCatalog()
            installSeedSyncTargets()
        }
        loadUserCatalogFromDefaults()
        loadActiveFromDefaults()
    }

    // MARK: - Catalog queries

    /// Filter the catalog by the current search/filter state. Called
    /// from the catalog page; pure function on @Published inputs so
    /// SwiftUI re-evaluates on every relevant change.
    func filtered() -> [SkillSpec] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return catalog.filter { skill in
            if let kindFilter, skill.kind != kindFilter { return false }
            if let scopeFilter, skill.scope.kind != scopeFilter { return false }
            if let tagFilter, !skill.tags.contains(tagFilter) { return false }
            guard !q.isEmpty else { return true }
            if skill.name.lowercased().contains(q) { return true }
            if skill.description.lowercased().contains(q) { return true }
            if skill.tags.contains(where: { $0.lowercased().contains(q) }) { return true }
            if skill.body.lowercased().contains(q) { return true }
            return false
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func skill(slug: String) -> SkillSpec? {
        catalog.first { $0.slug == slug }
    }

    /// Returns every distinct tag in the catalog, sorted by frequency
    /// then alphabetically. Used to power the tag chip cloud in the UI.
    func allTags() -> [String] {
        var counts: [String: Int] = [:]
        for skill in catalog {
            for tag in skill.tags { counts[tag, default: 0] += 1 }
        }
        return counts.keys.sorted { lhs, rhs in
            let lc = counts[lhs] ?? 0
            let rc = counts[rhs] ?? 0
            if lc != rc { return lc > rc }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    // MARK: - Activation

    func isActive(slug: String, atScope scopeTag: String) -> Bool {
        (activeByScope[scopeTag] ?? []).contains(where: { $0.slug == slug })
    }

    /// Toggle a skill on/off at the given scope. Persists to defaults
    /// so toggles survive relaunches even before the bridge is wired.
    func setActive(slug: String, scopeTag: String, active: Bool, params: [String: SkillParamValue]? = nil) {
        guard let skill = catalog.first(where: { $0.slug == slug }) else { return }
        var current = activeByScope[scopeTag] ?? []
        current.removeAll { $0.slug == slug }
        if active {
            let priority = priorityFor(kind: skill.kind, scope: scopeTag)
            current.append(ActiveSkillState(
                slug: slug,
                kind: skill.kind,
                scopeTag: scopeTag,
                priority: priority,
                params: params ?? skill.instance?.params
            ))
            current.sort { $0.priority < $1.priority }
        }
        if current.isEmpty {
            activeByScope.removeValue(forKey: scopeTag)
        } else {
            activeByScope[scopeTag] = current
        }
        persistActiveToDefaults()
    }

    /// Resolve the effective active set for a given chat context,
    /// applying the global → project → chat hierarchy. Personalities
    /// closer to the chat scope override broader ones.
    func resolveActive(projectId: String?, chatId: UUID?) -> [ActiveSkillState] {
        var merged: [String: ActiveSkillState] = [:]
        // Global first (lowest precedence), then project, then chat.
        for state in activeByScope["global"] ?? [] {
            merged[state.slug] = state
        }
        if let projectId {
            for state in activeByScope["project:\(projectId)"] ?? [] {
                merged[state.slug] = state
            }
        }
        if let chatId {
            for state in activeByScope["chat:\(chatId.uuidString)"] ?? [] {
                merged[state.slug] = state
            }
        }
        return merged.values.sorted { $0.priority < $1.priority }
    }

    // MARK: - Editing (creation / update / removal)

    /// Insert or replace a skill in the catalog. The bridge will later
    /// persist this change to the central library; for now we keep it
    /// in memory + UserDefaults so the UI iterates while ClawJS is
    /// still being implemented in parallel.
    func upsert(_ skill: SkillSpec) {
        if let index = catalog.firstIndex(where: { $0.slug == skill.slug }) {
            catalog[index] = skill
        } else {
            catalog.append(skill)
        }
        persistUserCatalogToDefaults()
    }

    func remove(slug: String) {
        catalog.removeAll { $0.slug == slug }
        // Also strip from any active set so the UI doesn't carry a
        // ghost reference.
        for (scope, states) in activeByScope {
            let filtered = states.filter { $0.slug != slug }
            if filtered.isEmpty {
                activeByScope.removeValue(forKey: scope)
            } else {
                activeByScope[scope] = filtered
            }
        }
        persistUserCatalogToDefaults()
        persistActiveToDefaults()
    }

    /// Create an instance from a parametrizable template. Returns the
    /// new instance's slug. Default `frozen: false` (reference mode).
    @discardableResult
    func instantiate(template: SkillSpec, params: [String: SkillParamValue], saveAs: String? = nil, frozen: Bool = false) -> String {
        precondition(template.isTemplate, "instantiate only valid on parametrizable templates")
        let baseSlug = saveAs ?? "\(template.slug)-\(shortId())"
        let slug = uniqueSlug(baseSlug)
        let instance = SkillSpec(
            slug: slug,
            name: nameForInstance(template: template, params: params, fallback: saveAs),
            description: template.description,
            version: template.version,
            kind: template.kind,
            body: frozen ? renderTemplate(template: template, params: params) : template.body,
            scope: SkillScope.global,
            tags: template.tags,
            syncTo: [],
            syncMode: .symlink,
            params: nil,
            instance: SkillInstanceRef(ofTemplate: template.slug, params: params, frozen: frozen),
            capsule: template.capsule,
            soul: template.soul,
            presets: nil,
            builtin: false,
            importedFrom: nil,
            author: "you",
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        upsert(instance)
        return slug
    }

    /// Convert a non-frozen instance into a frozen snapshot (body is
    /// rendered once, link to template dropped).
    func freeze(instanceSlug: String) {
        guard var instance = catalog.first(where: { $0.slug == instanceSlug }),
              let ref = instance.instance,
              let template = catalog.first(where: { $0.slug == ref.ofTemplate })
        else { return }
        instance.body = renderTemplate(template: template, params: ref.params)
        instance.instance = SkillInstanceRef(ofTemplate: ref.ofTemplate, params: ref.params, frozen: true)
        upsert(instance)
    }

    // MARK: - Sync (filesystem proxy to external agents)

    /// Trigger a re-sync run. The bridge implementation will call
    /// `claw.skills.sync()` in ClawJS and stream progress; the seed
    /// implementation just touches `lastSyncedAt`.
    func syncNow() async {
        pendingOperation = "Syncing"
        // Real implementation: bridge call.
        try? await Task.sleep(nanoseconds: 200_000_000)
        lastSyncedAt = Date()
        pendingOperation = nil
    }

    func setSyncTarget(slug: String, target: String, enabled: Bool) {
        guard let index = catalog.firstIndex(where: { $0.slug == slug }) else { return }
        var skill = catalog[index]
        if enabled {
            if !skill.syncTo.contains(target) { skill.syncTo.append(target) }
        } else {
            skill.syncTo.removeAll { $0 == target }
        }
        catalog[index] = skill
        persistUserCatalogToDefaults()
    }

    func registerSyncTarget(_ target: SkillSyncTarget) {
        if let index = syncTargets.firstIndex(where: { $0.id == target.id }) {
            syncTargets[index] = target
        } else {
            syncTargets.append(target)
        }
    }

    func removeSyncTarget(id: String) {
        syncTargets.removeAll { $0.id == id }
    }

    // MARK: - Persistence (local UserDefaults until bridge is wired)

    private static let activeKey = "ClawixSkillsActiveByScope"
    private static let userCatalogKey = "ClawixSkillsUserCatalog"

    private func loadUserCatalogFromDefaults() {
        guard let data = UserDefaults.standard.data(forKey: Self.userCatalogKey),
              let decoded = try? JSONDecoder().decode([SkillSpec].self, from: data)
        else { return }
        for skill in decoded where !skill.builtin {
            if let index = catalog.firstIndex(where: { $0.slug == skill.slug }) {
                catalog[index] = skill
            } else {
                catalog.append(skill)
            }
        }
    }

    private func persistUserCatalogToDefaults() {
        let userSkills = catalog.filter { !$0.builtin }
        if userSkills.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.userCatalogKey)
            return
        }
        if let data = try? JSONEncoder().encode(userSkills) {
            UserDefaults.standard.set(data, forKey: Self.userCatalogKey)
        }
    }

    private func loadActiveFromDefaults() {
        guard let data = UserDefaults.standard.data(forKey: Self.activeKey),
              let decoded = try? JSONDecoder().decode([String: [ActiveSkillSnapshot]].self, from: data)
        else { return }
        activeByScope = decoded.mapValues { snapshots in
            snapshots.map { snap in
                ActiveSkillState(
                    slug: snap.slug,
                    kind: snap.kind,
                    scopeTag: snap.scopeTag,
                    priority: snap.priority,
                    params: snap.params
                )
            }
        }
    }

    private func persistActiveToDefaults() {
        let snapshot = activeByScope.mapValues { states in
            states.map { state in
                ActiveSkillSnapshot(
                    slug: state.slug,
                    kind: state.kind,
                    scopeTag: state.scopeTag,
                    priority: state.priority,
                    params: state.params
                )
            }
        }
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.activeKey)
        }
    }

    /// On-disk shape (UserDefaults) for active set. Keeps Codable
    /// conformance simple by storing flat structs instead of relying
    /// on ActiveSkillState's identity-derived fields.
    private struct ActiveSkillSnapshot: Codable {
        let slug: String
        let kind: SkillKind
        let scopeTag: String
        let priority: Int
        let params: [String: SkillParamValue]?
    }

    // MARK: - Internals

    private func priorityFor(kind: SkillKind, scope scopeTag: String) -> Int {
        // Personalities first (low number = first in prompt), then
        // snippets, then procedures, then roles. Within kind, scope
        // adds a small offset (chat tightest, global broadest) so
        // chat > project > global tie-breaks if same skill is active
        // at multiple scopes.
        let kindBase: Int
        switch kind {
        case .personality: kindBase = 0
        case .snippet:     kindBase = 100
        case .role:        kindBase = 200
        case .procedure:   kindBase = 300
        }
        let scopeOffset: Int
        if scopeTag == "global" {
            scopeOffset = 0
        } else if scopeTag.hasPrefix("project:") {
            scopeOffset = 1
        } else if scopeTag.hasPrefix("chat:") {
            scopeOffset = 2
        } else {
            scopeOffset = 0
        }
        return kindBase + scopeOffset
    }

    private func nameForInstance(template: SkillSpec, params: [String: SkillParamValue], fallback: String?) -> String {
        if let fallback, !fallback.isEmpty { return fallback }
        let paramSummary = params
            .sorted { $0.key < $1.key }
            .map { "\($0.value.displayString)" }
            .joined(separator: " · ")
        return paramSummary.isEmpty ? "\(template.name) · custom" : "\(template.name) · \(paramSummary)"
    }

    private func uniqueSlug(_ base: String) -> String {
        var candidate = base
        var counter = 2
        while catalog.contains(where: { $0.slug == candidate }) {
            candidate = "\(base)-\(counter)"
            counter += 1
        }
        return candidate
    }

    private func shortId() -> String {
        String(UUID().uuidString.prefix(6).lowercased())
    }

    /// Trivial template renderer for the freeze path. Replaces
    /// `{{key}}` placeholders in the body with param values. The real
    /// rendering happens in ClawJS at compile-time; this is just a
    /// stop-gap so freeze produces something useful while the bridge
    /// is being implemented.
    private func renderTemplate(template: SkillSpec, params: [String: SkillParamValue]) -> String {
        var rendered = template.body
        for (key, value) in params {
            rendered = rendered.replacingOccurrences(of: "{{\(key)}}", with: value.displayString)
        }
        return rendered
    }

    // MARK: - Seed catalog (built-ins for first-run UX)

    private func installSeedCatalog() {
        catalog = SkillsSeedCatalog.builtins
    }

    private func installSeedSyncTargets() {
        syncTargets = [
            SkillSyncTarget(
                id: "codex",
                label: "Codex CLI",
                home: NSString("~/.codex/skills").expandingTildeInPath,
                mode: .symlink,
                lastSyncedAt: nil,
                lastError: nil
            ),
            SkillSyncTarget(
                id: "hermes",
                label: "HermesAgent",
                home: NSString("~/.hermes/skills").expandingTildeInPath,
                mode: .symlink,
                lastSyncedAt: nil,
                lastError: nil
            )
        ]
    }
}

// MARK: - Seed catalog data (separated for readability)

enum SkillsSeedCatalog {
    static let builtins: [SkillSpec] = [
        // ── Personalities (3 of the 14 ClawJS presets, the rest seed in
        // the same shape once ClawJS skills-v2 lands and ships them
        // properly under ~/.clawjs/skills/personality/_builtin/).
        SkillSpec(
            slug: "ceo-pragmatic",
            name: "CEO · Pragmatic",
            description: "Founder/CEO mindset: outcomes over process, terse, prioritises what moves the needle this week.",
            version: "0.1.0",
            kind: .personality,
            body: """
            You operate as a pragmatic CEO. Bias to outcomes over process. \
            Cut filler sentences. Single-CTA messages. Push back when the \
            user's question is the wrong one. Surface the next 1-2 actions \
            after every analysis.
            """,
            scope: .global,
            tags: ["leadership", "executive", "decision-making"],
            syncTo: [],
            syncMode: .symlink,
            params: nil,
            instance: nil,
            capsule: SkillCapsule(
                text: "Lean CEO mindset: outcomes > process, terse, single CTA, surface next 1-2 actions.",
                priority: 5,
                readWhen: ["strategy", "weekly priorities", "trade-offs"]
            ),
            soul: SkillSoulModules(presetId: "executive", modules: [:]),
            presets: nil,
            builtin: true,
            importedFrom: nil,
            author: "clawjs",
            updatedAt: nil
        ),
        SkillSpec(
            slug: "engineer-rigorous",
            name: "Engineer · Rigorous",
            description: "Senior engineer mindset: traces root causes, names tradeoffs, never ships without a verification step.",
            version: "0.1.0",
            kind: .personality,
            body: """
            You think like a senior staff engineer. Trace root causes, \
            don't patch symptoms. Name tradeoffs explicitly. Always \
            propose a verification step before declaring work done. \
            Prefer reading the code over speculating.
            """,
            scope: .global,
            tags: ["engineering", "debugging", "rigor"],
            syncTo: [],
            syncMode: .symlink,
            params: nil,
            instance: nil,
            capsule: nil,
            soul: SkillSoulModules(presetId: "engineer", modules: [:]),
            presets: nil,
            builtin: true,
            importedFrom: nil,
            author: "clawjs",
            updatedAt: nil
        ),
        SkillSpec(
            slug: "tutor-patient",
            name: "Tutor · Patient",
            description: "Teacher mindset: builds the user's mental model, asks 'do you want me to explain X' before diving in.",
            version: "0.1.0",
            kind: .personality,
            body: """
            You teach. Calibrate explanations to the user's evident level. \
            Offer to expand or simplify. Use analogies when helpful. \
            Never condescend; assume the user is smart but new to this \
            specific area.
            """,
            scope: .global,
            tags: ["teaching", "explanation", "patience"],
            syncTo: [],
            syncMode: .symlink,
            params: nil,
            instance: nil,
            capsule: nil,
            soul: SkillSoulModules(presetId: "tutor", modules: [:]),
            presets: nil,
            builtin: true,
            importedFrom: nil,
            author: "clawjs",
            updatedAt: nil
        ),

        // ── Procedure templates with parameters (the "many ways to
        // write an email" pattern).
        SkillSpec(
            slug: "email-writing",
            name: "Email writing",
            description: "Compose an email with the right tone, length and intent. Configure once, save as your own.",
            version: "0.1.0",
            kind: .procedure,
            body: """
            Write an email matching these constraints:

            - Tone: {{tone}}
            - Length: {{length}}
            - Intent: {{intent}}
            - Industry: {{industry}}

            Subject ≤ 50 chars. Single CTA. No "synergy", "leverage", \
            "circle back", "touch base". When intent == cold, lead with \
            a personalized hook in line 1; when intent == follow-up, \
            reference the prior thread by date in line 1.
            """,
            scope: .global,
            tags: ["email", "writing", "communication"],
            syncTo: [],
            syncMode: .symlink,
            params: [
                SkillParam(key: "tone", label: "Tone", type: .enumValue, options: ["formal", "neutral", "casual"], defaultValue: .string("formal"), required: true, prompt: nil),
                SkillParam(key: "length", label: "Length", type: .enumValue, options: ["short", "medium", "long"], defaultValue: .string("short"), required: true, prompt: nil),
                SkillParam(key: "intent", label: "Intent", type: .enumValue, options: ["cold", "follow-up", "reminder", "internal-update"], defaultValue: .string("cold"), required: true, prompt: nil),
                SkillParam(key: "industry", label: "Industry", type: .string, options: nil, defaultValue: .string(""), required: false, prompt: "e.g. SaaS, fintech, hospitality")
            ],
            instance: nil,
            capsule: nil,
            soul: nil,
            presets: [
                SkillPreset(slug: "cold-email-saas-formal", label: "Cold · SaaS · formal · short",
                            params: ["tone": .string("formal"), "length": .string("short"), "intent": .string("cold"), "industry": .string("SaaS")]),
                SkillPreset(slug: "follow-up-casual",       label: "Follow-up · casual · short",
                            params: ["tone": .string("casual"), "length": .string("short"), "intent": .string("follow-up"), "industry": .string("")]),
                SkillPreset(slug: "internal-update-neutral", label: "Internal update · neutral · medium",
                            params: ["tone": .string("neutral"), "length": .string("medium"), "intent": .string("internal-update"), "industry": .string("")])
            ],
            builtin: true,
            importedFrom: nil,
            author: "clawjs",
            updatedAt: nil
        ),
        SkillSpec(
            slug: "code-review",
            name: "Code review",
            description: "Structured review with severity tags and an overall verdict. Configurable depth.",
            version: "0.1.0",
            kind: .procedure,
            body: """
            Review the supplied diff or files at depth: {{depth}}.

            Output structure:
            1. Summary (1 paragraph).
            2. Per-file findings, each tagged [BLOCK] / [HIGH] / [LOW] / [NIT].
            3. Cross-cutting concerns.
            4. Verdict: ship / iterate / rewrite.

            For depth = light, only flag [BLOCK] / [HIGH]. For depth = \
            full, include [LOW] and [NIT] as well.
            """,
            scope: .global,
            tags: ["engineering", "review", "quality"],
            syncTo: ["codex"],
            syncMode: .symlink,
            params: [
                SkillParam(key: "depth", label: "Depth", type: .enumValue, options: ["light", "standard", "full"], defaultValue: .string("standard"), required: true, prompt: nil)
            ],
            instance: nil,
            capsule: nil,
            soul: nil,
            presets: nil,
            builtin: true,
            importedFrom: nil,
            author: "clawjs",
            updatedAt: nil
        ),

        // ── Snippet (the "building block" pattern).
        SkillSpec(
            slug: "cloudflare-ops",
            name: "Cloudflare ops · my account",
            description: "How to operate my Cloudflare account: which zones, which API token in the Vault, what's safe to mutate.",
            version: "0.1.0",
            kind: .snippet,
            body: """
            When I ask about Cloudflare:

            - The active zones are landed-on under my main account.
            - Use the API token stored under Vault key `cloudflare_api`.
            - Safe to mutate: DNS records, WAF rules, page rules.
            - NEVER touch: payment method, account roles, R2 lifecycle \
              policies (those need explicit confirmation each time).
            - Prefer the zone-scoped token over the user-scoped one.
            """,
            scope: .global,
            tags: ["devops", "cloudflare", "infra"],
            syncTo: ["codex"],
            syncMode: .symlink,
            params: nil,
            instance: nil,
            capsule: SkillCapsule(
                text: "Cloudflare: token under Vault key cloudflare_api; safe to mutate DNS/WAF/page rules; never touch payment/roles/R2 lifecycle without confirmation.",
                priority: 50,
                readWhen: ["DNS", "Cloudflare", "WAF", "API token"]
            ),
            soul: nil,
            presets: nil,
            builtin: true,
            importedFrom: nil,
            author: "you",
            updatedAt: nil
        ),

        // ── Role (curated combo of personality + snippets).
        SkillSpec(
            slug: "devops-cloudflare",
            name: "DevOps · Cloudflare specialist",
            description: "Engineer-rigorous personality + Cloudflare ops snippet. Activate when working on infra/DNS.",
            version: "0.1.0",
            kind: .role,
            body: """
            (This role pulls together other skills; the body is short.)

            You are an infra-focused operator working on Cloudflare. \
            Defer to the engineer-rigorous personality for tone and \
            decision-making. Defer to the cloudflare-ops snippet for \
            account-specific facts.
            """,
            scope: .global,
            tags: ["devops", "cloudflare", "infra", "role"],
            syncTo: [],
            syncMode: .symlink,
            params: nil,
            instance: nil,
            capsule: nil,
            soul: nil,
            presets: nil,
            builtin: true,
            importedFrom: nil,
            author: "you",
            updatedAt: nil
        )
    ]
}
