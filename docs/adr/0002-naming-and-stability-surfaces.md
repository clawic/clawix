# ADR 0002: Naming and stability surfaces

Status: accepted
Date: 2026-05-13
Source conversation: private local planning session

## Context

Clawix is the native human interface and signed host for ClawJS. Before broader
public adoption, all accidental names in the host, bridge, CLI, paths, protocol,
and docs must be corrected without preserving legacy compatibility unless a
later task explicitly requires migration.

This ADR mirrors the canonical ClawJS naming ADR:
`docs/adr/0001-naming-and-stability-surfaces.md` in the ClawJS repository.
When implementing shared framework or public CLI behavior, the ClawJS ADR is the
primary source. This Clawix ADR records the host-specific consequences.

## Host and framework boundary

- Framework/product name: `ClawJS`.
- Framework public CLI: `claw`.
- Clawix is the app, native UI, and signed host.
- The `clawix` CLI is host/bridge/install/diagnostic only.
- The `clawix` CLI must keep existing product-host duties such as install/open,
  bridge lifecycle, mobile pairing, preflight, logs, and diagnostics. It is not
  legacy and must not be removed.
- Do not add domain/product/framework commands to `clawix`; they belong in
  `claw`.
- Clawix host/bridge operational home is `~/.clawix/`.
- ClawJS global home is `~/.claw/`, not Application Support and not
  `~/.clawjs/`.
- Workspace data lives under `<workspace>/.claw/`.
- New workspace writes must not use `.clawjs/`.
- Clawix GUI-only native app state may continue to use platform-native app data
  such as Application Support when it is not framework state.

## Clawix bridge naming

- The host bridge service is named `clawix-bridge`.
- The LaunchAgent/service suite label is `clawix.bridge`.
- Binary, log, and unit names use `clawix-bridge`.
- Environment variables use `CLAWIX_BRIDGE_*`.
- Clawix host/app env vars use `CLAWIX_*`; framework env vars consumed from
  ClawJS use `CLAW_*`. Hybrid names such as `CLAWIX_CLAW_*` are not V1
  surfaces.
- `clawix-bridged` and `CLAWIX_BRIDGED_*` are retired pre-public names.
- Bonjour/mDNS service type is `_clawix-bridge._tcp`.
- `24080` is the stable Clawix host/bridge entrypoint.
- Clawix host/dev/bridge ports live in `24080-24099`.
- ClawJS service ports live in `24100-24199` and are consumed from the ClawJS
  registry, not duplicated in Clawix.
- The stable Clawix socket is `~/.clawix/run/clawix-bridge.sock`; Windows pipe
  equivalent is `\\.\pipe\clawix-bridge`.

## Protocol and deep links

- Protocol documents and new frames use `sessionId`, not `chatId`.
- `chat` remains UI vocabulary only.
- `threadId` is reserved for external runtime IDs.
- Frame/event `type` strings use `lowerCamelCase`.
- Versioned JSON envelopes use `schemaVersion`, including the Clawix bridge.
- Clawix deep links are:
  - `clawix://auth/callback/<provider>`
  - pairing uses QR JSON `{ v, host, port, token, ... }`, not a stable pairing deep link
  - `clawix://session/<sessionId>`
  - `clawix://settings/<section>`
- `claw://` is reserved for future framework-level links.
- Client role is `clientKind`; platform is a separate diagnostic field.
- `hostId` for this product is `clawix`; platform stays separate.
- Pairing and audit distinguish `deviceId`, `installationId`, and `clientId`.

## Public identity and repository hygiene

- Public Clawix domains are `clawix.com`, `www.clawix.com`, and
  `pkg.clawix.com`.
- Public reverse-DNS examples derive from owned domains and use
  `com.clawix...`.
- Public repo placeholders may use `com.example...` only for fixtures and
  templates.
- Real bundle IDs, Team IDs, signing identities, SKUs, release credentials, and
  maintainer-local paths stay outside the public repo.
- Public registries may contain placeholders for bundle IDs, Team IDs, signing
  identities, SKUs, entitlements, Mach services, and LaunchAgent labels; real
  private values stay outside the public repo.
- Release builds must fail if a real target is missing its configured ID or
  still uses a placeholder.

## Packages, formats, and caches

- Clawix-owned packages use `@clawix/*`, except the product/host CLI package
  and binary named `clawix`.
- Package names, package exports, package bins, private `/api/<app>/...`
  routes, file formats, error codes, enum wire values, and provider mappings
  are stable surfaces and must be registered before V1.
- Stable error codes use `snake_case`.
- Import/export/backup/snapshot formats that can be saved or imported must
  declare versioned schemas and fixtures.
- Caches that survive app restart are registered as rebuildable cache surfaces.

## Shared vocabulary

Clawix must follow the ClawJS ADR for stable terms: `runtimeId`, `agentId`,
`providerId`, `modelId`, `account`, `permissions`, `policies`, `approvals`,
`grants`, `leases`, `capabilities`, `file`, `attachment`, `artifact`,
`document`, `asset`, `message`, `turn`, `event`, `frame`, `chunk`, `delta`,
`completed`, and timestamp fields such as `createdAt` and `updatedAt`.

## Guardrails

Clawix checks and reviews must block new public/stable uses of:

- `.clawjs` as a new-write path
- `CLAWIX_BRIDGED`
- `clawix-bridged`
- protocol-stable `chatId` and `openChat`
- public `/ws` as a contract
- `claw.dev`
- real private signing or bundle identifiers

When Clawix consumes ClawJS packages, ports, APIs, schemas, database names, or
domain names, use the ClawJS naming ADR as the source of truth.
