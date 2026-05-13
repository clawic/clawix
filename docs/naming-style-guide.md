# Clawix naming style guide

This guide applies the ClawJS naming style guide to Clawix host, bridge, app,
protocol, docs, tests, scripts, and public repository hygiene.

The canonical shared guide lives in the ClawJS repository at
`docs/naming-style-guide.md`.

## Clawix-specific rules

- `Clawix` is the native app and signed host.
- `ClawJS` is the framework/product.
- `claw` is the framework CLI.
- `clawix` is host/bridge/install/diagnostic CLI only.
- Do not add product/domain/framework commands to `clawix`.
- Clawix host env vars use `CLAWIX_*`.
- The bridge service is `clawix-bridge`.
- The service suite label is `clawix.bridge`.
- Retire `clawix-bridged` and `CLAWIX_BRIDGED_*`.
- The Bonjour service type is `_clawix-bridge._tcp`.
- The stable bridge port is `24080`.
- Clawix host/dev/bridge ports are `24080-24099`.
- ClawJS service ports are read from the ClawJS registry.
- Clawix operational home is `~/.clawix/`.
- Clawix bridge socket is `~/.clawix/run/clawix-bridge.sock`.
- Windows pipe equivalent is `\\.\pipe\clawix-bridge`.
- ClawJS global home is `~/.claw/`.
- Workspace writes use `.claw/`, not `.clawjs/`.

## Protocol rules

- Use `sessionId`, not stable `chatId`, in bridge/protocol contracts.
- `chat` may appear only as UI copy or UI-local naming.
- Use `threadId` only for external runtime IDs.
- Use `schemaVersion` for data and `protocolVersion` for wire protocols.
- Frame/event `type` strings use `lowerCamelCase`.
- Deep links use:
  - `clawix://auth/callback/<provider>`
  - `clawix://pair/<token>`
  - `clawix://session/<sessionId>`
  - `clawix://settings/<section>`
- `claw://` is reserved for future framework-level links.

## Identifier rules

- `hostId` for this product is `clawix`.
- `platform` is separate from `hostId`.
- Distinguish `deviceId`, `installationId`, and `clientId`.
- Use `clientKind` for client role.
- Use `runtimeId`, `agentId`, `providerId`, `modelId`, and `account` with the
  same meanings as ClawJS.

## Public hygiene

- Public examples may use `com.example...` only as placeholders.
- Public Clawix reverse-DNS examples use `com.clawix...`.
- Real bundle IDs, Team IDs, signing identities, SKUs, release credentials,
  local private paths, and maintainer configuration never enter the repo.
- Release builds must fail if a real configured target is missing its ID or is
  still using a placeholder.

## Review checklist

Before adding or renaming a Clawix surface:

- Read `docs/adr/0002-naming-and-stability-surfaces.md`.
- Check the shared ClawJS naming guide and ADR when a name touches framework,
  CLI, domains, routes, protocols, data, ports, packages, or docs.
- Do not introduce `clawix-bridged`, `CLAWIX_BRIDGED_*`, public `/ws`,
  `.clawjs` new writes, or stable protocol `chatId`/`openChat`.
- Keep Clawix docs aligned with the ClawJS source of truth.
