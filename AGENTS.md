# Clawix

Compact operating entrypoint for humans and coding agents in this repository.
Use this file as a router. Keep detailed procedures in docs, playbooks, and
`skills/<id>/SKILL.md`.

## Canon

- Highest authority: `CONSTITUTION.md`, shared with ClawJS. Read it fully for
  major architecture, product, data, agent, UX, security, or integration
  decisions.
- Main router: `docs/decision-map.md`. It maps decision -> document ->
  validation and tells agents which canon/check applies.
- Claude Code shim: `CLAUDE.md` points back here and must remain short.
- Visual canon: `STYLE.md`. Read it before changing user-facing screens,
  chrome, visual components, design tokens, icons, spacing, motion, or
  microcopy.

Read the relevant canonical docs before changing their surfaces:

- Framework/host boundary: `docs/host-ownership.md`,
  `docs/adr/0001-claw-framework-host-boundary.md`
- Storage/data placement: `docs/data-storage-boundary.md`
- Naming/stability: `docs/naming-style-guide.md`,
  `docs/agentic-naming-guide.md`, `docs/vocabulary.md`,
  `docs/adr/0002-naming-and-stability-surfaces.md`,
  `docs/adr/0009-agentic-naming-and-code-structure.md`
- Testing and validation: `docs/adr/0003-testing-architecture.md`,
  `docs/adr/0005-integration-qa-lab.md`, `playbooks/testing.md`,
  `playbooks/testing-matrix.md`
- Source file boundaries: `docs/adr/0004-source-file-boundaries.md`
- Human/programmatic parity: `docs/interface-matrix.md`,
  `docs/adr/0007-dual-human-programmatic-surfaces.md`
- CLI guidance/resource assertions: `docs/adr/0008-cli-jit-guidance-actor-assertions-resource-registry.md`
- Platform procedures: `playbooks/README.md` and the relevant platform
  playbook.

## Repository Shape

Clawix is the native human interface and embedded signed host for ClawJS/Claw.
It is not the canonical framework store. Framework contracts, schemas,
fixtures, canonical storage, domain APIs, and the public `claw` CLI belong to
ClawJS/Claw.

Top-level areas:

- `macos/`: SwiftUI macOS app and embedded host integration.
- `ios/`, `android/`, `linux/`, `windows/`, `web/`: platform clients.
- `packages/`: shared Swift packages.
- `cli/`: legacy/transitional Clawix host/install/diagnostic npm surface, not
  the public framework CLI.
- `docs/`: architecture docs, ADRs, registries, and generated manifests.
- `playbooks/`: task and platform procedures.
- `skills/`: projected just-in-time agent workflows from the ClawJS canonical
  skill library.
- `scripts/`: repository checks and automation.

## Agent Discovery

For non-trivial questions or plans about framework behavior, contracts,
storage, CLI, schemas, permissions, grants, approvals, audit, data placement,
naming, public packages, routes, ports, protocols, or Clawix/ClawJS
integration, start with a `claw` discovery pass when available:

```bash
claw search <topic> --json
claw inspect commands|why|database|schemas|storage|codebase --json
claw collections list --json
claw collections <collection> schema --json
claw db <collection> list|query --json
```

Treat source files as evidence after the CLI/registry map. If `claw` is not
available, say so and use direct docs/source reads.

Before asking a technical question, check the relevant canon. If asking is
still needed, explain the meaning, consequences, tradeoffs, and recommended
default.

## Skills

Shared ClawJS/Clawix workflow skills are canonically authored in the ClawJS
repository and projected here for agents that only open Clawix. Run:

```bash
node scripts/check-clawjs-skills-sync.mjs
```

when adding or changing projected skills. If the sibling ClawJS checkout is not
available, the check validates local presence/frontmatter and reports that the
canonical comparison was skipped.

Use the relevant skill instead of loading long instructions into context:

- Architecture alignment: `constitution-drift-audit`,
  `architecture-drift-repair`, `adr-to-guardrail`,
  `decision-map-maintenance`
- Stable surfaces: `naming-surface-audit`, `surface-registry-alignment`,
  `cli-agent-surface-work`, `source-file-boundary-refactor`
- Data/storage: `canonical-catalog-expansion`,
  `data-storage-boundary-review`
- Host/security/validation: `host-boundary-review`,
  `secrets-boundary-review`, `integration-qa-lab`,
  `host-dependent-validation`, `performance-investigation`
- Collaboration hygiene: `public-hygiene-review`, `docs-alignment-update`,
  `code-review-risk`, `commit-hygiene-public`
- Interface governance: `ui-canon-review`, `ui-implementation`,
  `visual-regression`, `ui-performance-budget`

## Invariants

- `claw` is the single public framework CLI. Clawix CLI surfaces are host,
  install, bridge, and diagnostic helpers only.
- ClawJS/Claw owns canonical framework contracts, schemas, fixtures, storage
  resolution, domain APIs, SDK, and CLI.
- Clawix owns native UI, visual state, host identity, review/approval surfaces,
  and host-specific operational state.
- Clawix UI canon is governed by `docs/adr/0010-interface-governance.md` and
  `docs/ui/`. Non-authorized agents must not change visual/copy/layout
  decisions; they report drift and leave conceptual proposals instead.
- Framework global data belongs under `~/.claw`; workspace framework data
  belongs under `.claw/`; Clawix host-operational state belongs under
  `~/.clawix`; `.clawjs/` is a retired pre-public path.
- User-facing structured framework records belong in `core.sqlite`. Sidecars
  require explicit technical reasons such as churn, blobs, search indexes,
  sessions, logs, caches, or encrypted vault state.
- Plaintext secrets never live in `core.sqlite`, logs, fixtures, screenshots,
  generated artifacts, or public docs.
- Sensitive native permissions, grants, approvals, audit, LaunchAgents, Mach
  services, and native execution belong to the active signed host, not Node.
- `~/.codex` is an external read-only source by default. Mirror or index it
  only; do not delete, move, overwrite, chmod broadly, or write into it without
  explicit reversible opt-in.
- When background bridge daemon mode owns runtime, do not reintroduce a second
  GUI-owned backend or bridge.
- Capabilities are complete only when human and programmatic surfaces are
  registered or their gaps are explicitly classified.
- New hand-authored files at 1200+ lines need a split plan or baseline
  rationale; new 2000+ line files are blocked unless explicitly exempted.
  Emergency-debt files above 5000 lines must not grow except for extraction,
  deletion, or compatibility-preserving split work.

## Validation

Use focused checks during iteration:

```bash
bash scripts/test.sh fast
bash scripts/test.sh changed
bash scripts/test.sh integration
bash macos/scripts/public_hygiene_check.sh
node scripts/check-clawjs-skills-sync.mjs
```

Validation safety:

- Hermetic tests are useful but not sufficient for host-dependent bugs.
- Host-dependent paths include installed apps, signed helpers, localhost,
  filesystem state under the user's home, auth, polling, native permissions,
  and device/simulator state.
- Do not send real prompts, touch production data, call paid APIs, mutate real
  services, or reveal secrets without explicit approval in the current thread.
- Prefer fixtures, dry-run paths, interceptors, local backends, and mocks.
- Mark missing physical/provider prerequisites as `EXTERNAL PENDING` and keep
  them separate from defects.
- Performance work starts with reproduction and instrumentation before
  optimization.

Public platform docs describe only safe launcher contracts. Maintainer-private
launchers, signing identities, device names, app-mode toggles, and local
preflight flows live outside the public repository.

## Public Hygiene

The public repo must not contain maintainer-private paths, signing identities,
bundle IDs, Team IDs, SKUs, release credentials, local launchers, private
automation, private Q&A indexes, logs, caches, or screenshots.

Before publication or broad review, run:

```bash
bash macos/scripts/public_hygiene_check.sh
```

Classify hygiene findings as `safe_public`, `false_positive`,
`needs_user_decision`, or `must_remove_before_publish`. Do not resolve
uncertainty by publishing the private value.

## Commits

Public commit hygiene only:

- Use Conventional Commits: `type(scope): description`.
- Keep commits scoped by intention.
- Do not sweep unrelated edits from a dirty tree.
- Add changesets only when release metadata explicitly requires them.
- Push, publish, upload, tagging, and release actions require explicit
  approval.

Maintainer-private commit automation, local history rewriting procedures,
ledger workflows, and personal push policy do not belong in this public repo.
