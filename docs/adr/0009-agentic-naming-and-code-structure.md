# ADR 0009: Agentic naming and code structure

Status: accepted

Date: 2026-05-15

## Context

Clawix mirrors ClawJS framework contracts while owning native UI, visual state,
host identity, review/approval surfaces, and host-specific operational state.
The shared naming rules already cover stable public surfaces, but source
filenames, Swift types, UI-local names, bridge terms, JSON files, Markdown
docs, and helper functions need a tighter standard for coding agents.

This ADR mirrors ClawJS ADR 0013 and records the Clawix-specific consequence:
Clawix may use UI vocabulary such as `chat` in visible copy and UI-local code,
but bridge/protocol/storage terms must stay aligned with ClawJS vocabulary
unless a documented exception exists.

## Decision

ClawJS remains canonical for shared framework vocabulary. Clawix keeps a host
extension in:

- `docs/adr/0009-agentic-naming-and-code-structure.md`
- `docs/agentic-naming-guide.md`
- `docs/vocabulary.registry.json`
- `docs/vocabulary.md`
- `docs/naming-style-guide.md`
- `docs/adr/0004-source-file-boundaries.md`
- `scripts/naming-shape-check.mjs`
- `scripts/source-size-check.mjs`

`AGENTS.md` and `CLAUDE.md` remain short routing docs.

### Clawix vocabulary

Use `session` / `sessionId` in bridge, protocol, storage, durable cache, and
framework-facing code. Use `threadId` only for external runtime identifiers.
Use `chat` only for UI copy, UI-local state, localization, and provider-native
APIs unless `docs/vocabulary.registry.json` records a bounded exception.

Clawix-specific canonical terms include:

- `Clawix`: native app and signed host.
- `ClawJS`: framework/product owned by the sibling repo.
- `claw`: public framework CLI.
- `clawix`: host/install/bridge/diagnostic CLI only.
- `clawix-bridge`: bridge service.
- `CLAWIX_*`: host environment variables.
- `CLAWIX_BRIDGE_*`: bridge environment variables.

### Names

Swift source follows the language idiom, normally `PascalCase` for files that
contain primary types. TypeScript/JavaScript source uses `kebab-case`.
Markdown docs and playbooks use `kebab-case` except conventional root docs.
Owned JSON/YAML files use role suffixes such as `.registry.json`,
`.manifest.json`, `.fixture.json`, `.schema.json`, or `.baseline.json`.

Internal Swift and TypeScript symbols are in scope. Types use domain + role,
such as `BridgeSessionStore`, `SnapshotCacheReader`, or
`IdentitySettingsController`. Functions use verb + object, such as
`loadSessions`, `renderMessageRow`, or `resolveBridgeStatus`.

### Structure

Clawix source files split by responsibility: root layout, subviews,
interactions, data adapters, state transforms, persistence, bridge contracts,
and platform helpers. The goal is navigability and safe agent edits, not a
raw line-count target.

Comments should capture why, invariants, host/provider quirks, security
constraints, or short module maps. Do not add task narration.

## Guardrails

`scripts/naming-shape-check.mjs` produces human-readable output by default and
JSON with `--json`. It audits vocabulary drift, file names, role suffixes, and
broad suspicious naming shapes. It hard-blocks only critical public,
protocol, storage, host-security, or privacy-sensitive drift.

`scripts/source-size-check.mjs` reports size plus compression signals such as
pathological long lines, compressed enum/list patterns, large export surfaces,
and emergency-debt growth. It should not pressure agents to hide complexity in
long lines.

## Consequences

Broad cleanup is expected. Rename work should happen by compilable family:
symbols first, filenames and routes after imports still resolve, then targeted
validation. False positives stay documented when the replacement is not
clearly better.

Clawix mirrors ClawJS vocabulary and may add host/UI exceptions, but it does
not redefine shared framework terms locally.
