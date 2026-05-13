# Claw data storage boundary

This document records the canonical data-placement decisions for ClawJS/Claw,
Claw.app, and Clawix. It complements `docs/host-ownership.md`: ownership says
who is responsible; this page says where data lives.

## Canonical roots

- Framework global root: `~/.claw`
- Framework main database: `~/.claw/data/core.sqlite`
- Framework files/blob root: `~/.claw/data/files`
- Workspace root: `.claw/`
- Clawix host-operational root: `~/.clawix`
- Host GUI-only app state: platform-native app data when it is not framework
  state

Older `.clawjs/` workspace paths and older Clawix-named framework data roots are
retired pre-public locations. New canonical writes must not create
`.clawjs/data/database.sqlite`, `.clawjs/data/productivity.sqlite`,
`.clawjs/data/storage.sqlite`, or `.clawjs/code/code.sqlite`.

## Main database

`core.sqlite` is the main framework database. It stores user-facing structured
records and framework metadata that benefit from one queryable relational graph.
The point of this decision is to avoid many small per-domain SQLite files such
as `productivity.sqlite` for records that naturally join, search, export, and
backup together.

The main database owns:

- Database namespaces, collections, records, schemas, record notes, scoped API
  tokens, and realtime record metadata.
- Productivity records: tasks, notes, people, goals, projects, reminders,
  deadlines, inbox threads/messages, events, saved views, comments,
  attachments metadata, custom fields, and field values.
- Workspace collections and metadata that are framework data, not source files.
- Memory and knowledge records: entities, facts, pages, page blocks, links,
  mentions, revisions, comments, and profile projections.
- User model, signals observations, time projections, MCP metadata, channel
  metadata, apps/resources/design metadata, publishing/social, marketplace,
  home, technical IoT adapters, and other structured domain tables when the data
  is not a native secret and not a high-churn runtime log.

Framework-visible app projections may be stored in the main database when they
are part of the reusable framework contract. Host-only UI preferences still live
under the host root.

## Sidecar databases

Sidecars are allowed when isolation has a concrete reason: high churn, service
lifecycle isolation, large indexes, binary/object stores, or operational logs.
They live under the same framework global root, not under a workspace legacy
folder.

Canonical sidecars:

- `runtime.sqlite`: runtime, sandbox, code index, bridge/daemon operational
  state, and delegation/jobs operational state.
- `sessions.sqlite`: session service data and long-running session event state
  when it is not just a searchable main-db projection.
- `audio.sqlite` plus `audio/`: audio and voice catalog/output metadata and
  generated audio assets.
- `drive.sqlite` plus `files/` or `blobs/`: object storage metadata, workspace
  blobs, and drive-like artifacts.
- `search.sqlite`: search/index data that can be rebuilt from canonical sources.
- `notify.sqlite`, `monitor.sqlite`, `feed.sqlite`, `infra.sqlite`, and
  `ops.sqlite`: service-specific operational state where a separate lifecycle is
  valuable. `ops` and `infra` are not public top-level product surfaces unless a
  later ADR promotes them.
- `vault.sqlite`: encrypted secret vault state only. Main database records may
  keep `secret_ref` references, never plaintext secrets.

Sidecars are not a place to re-create canonical product data just because a
service has its own package. If a service stores durable user-facing structured
records, prefer `core.sqlite` with namespaced/prefixed tables.

## Secrets

Secrets are separate from the main database. Plaintext secrets never live in
`core.sqlite`. The framework stores encrypted vault data in the secrets/vault
sidecar or host-owned secret storage, and other records refer to secrets by
opaque ids such as `secret_ref`.

Approvals, grants, and audit records that are specific to a signed host live in
the active host root. Framework policy records may reference them, but the host
owns the native permission identity and approval UI.

## Workspace data

`.claw/` stores workspace-local framework files: `manifest.json`,
`state/desired/`, `state/observed/`, `projections/`, `sessions/`, `audit/`,
`locks/`, `backups/`, `browser/`, design/style/template/reference assets, and
other source-like files that should travel with a workspace.

Do not add new workspace-local SQLite databases for canonical framework data.
Do not add `.clawjs/` readers or migrations for pre-public workspace databases
unless a later ADR records a bounded removal exception. New writes go to
`.claw/`, `core.sqlite`, or a canonical sidecar under the framework global
root.

## Migration rule

The v1/refactor direction is reset-controlled for duplicated Claw/Clawix
development data, but non-destructive for valuable external sources. Codex data
under `~/.codex` is never migrated destructively; it is read, mirrored, or
indexed only.

Every future domain migration must state which of these buckets it uses:
main database, sidecar database, workspace files, host state, external
read-only source, or encrypted secret reference.
