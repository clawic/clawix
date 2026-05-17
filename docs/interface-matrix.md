# Clawix Interface Matrix

This matrix is the Clawix gate for ADR 0007. It is separate from
`persistent-surface-clawix.manifest.json`: the persistent manifest describes
durable names, while this matrix describes product/interface parity.

The source registry is `docs/interface-surface-clawix.registry.json`. A Clawix
surface is not complete merely because it is hidden behind a beta or
experimental switch. Every current surface must be one of:

- `stable`: v1 product surface with owner, storage boundary, human UI,
  programmatic interface, fixtures/tests, and validation.
- `dev-only`: explicitly not a product v1 surface.
- `removed`: no longer shown or shipped as a v1 surface.

## Completion Rules

- ClawJS owns framework contracts, v1 schemas, fixtures, reusable domain APIs,
  framework storage, and the public `claw` programmatic surface.
- Clawix owns human UI, embedded signed-host behavior, visual state, host-local
  caches, host approvals, and host-specific native permission execution.
- Plaintext secrets live only in the signed host/vault. Framework records may
  contain opaque references and policies.
- Stable Clawix UI must have a matching programmatic surface: SDK, CLI, service
  API, MCP, Relay, or a documented host API.
- External live validation is not required by default. Physical, paid,
  provider-role-dependent, destructive, or production-data checks are recorded
  as `EXTERNAL PENDING`, separate from real defects.

## Stable v1 Matrix

| Surface | Owner | Human UI | Programmatic Surface | Storage Boundary | Required Validation |
| --- | --- | --- | --- | --- | --- |
| Bridge v1 | Framework | Pairing and companion clients | Swift `BridgeProtocol` plus JSON fixtures; Android/Windows parity | Framework contract | Round-trip fixture tests across clients |
| Session deep links | Host | Open/copy session links | `clawix://session/<sessionId>` | Host route | Parser accepts session and rejects chat |
| OAuth callback deep links | Host | OAuth callback handling | `clawix://auth/callback/<provider>` | Host route | Parser accepts auth callback and rejects the retired callback route spelling |
| Pairing QR | Host | Pairing QR sheet | JSON payload with `v`, `host`, `port`, `token`, `shortCode`, `hostDisplayName` | Host runtime | Payload tests assert JSON, port `24080`, short code and host display identity |
| Agents, Personalities, Connections | Framework | Clawix agent and connection views | `claw agents`, `claw personalities`, `claw connections`; ClawJS agent/integration APIs, CLI/SDK, fixtures | Framework files plus `core.sqlite`, host secret refs | No direct Clawix canonical writes |
| Skills and Skill Collections | Framework | macOS Clawix skills/library UI | `claw skills`, `claw skill-collections`; ClawJS skills/library APIs, CLI/SDK, MCP resources | Framework files plus `core.sqlite` | Skill fixtures and interface coverage |
| Secrets | Host | Unlock, reveal and approvals | Host/vault APIs with opaque framework refs | Host vault | Signed-host/vault tests and plaintext negative checks |
| MCP | Framework | MCP settings | `claw mcp list|get|upsert|delete|config-path`; ClawJS MCP registry API | Framework registry; external configs read-only | Registry tests and Codex read-only guard |
| Provider accounts/routing | Framework + Host | Provider account/model settings | `claw providers routing list|set|delete`; `claw providers settings list|set`; framework config plus host vault refs | Framework config; credentials in host vault | Routing tests; no UserDefaults as canonical store |
| QuickAsk snippets/prompts | Framework | QuickAsk slash/mention templates | `claw snippets list|upsert|delete`; framework snippets/prompts/skills | Framework snippets; host hotkey/panel prefs local | Snippet tests; host prefs remain local |
| Voice/audio/dictation | Framework + Host | Dictation and audio catalog UI | `claw audio index|transcript|artifact list|get|delete`; `@clawjs/audio` API/CLI/fixtures | Framework audio sidecar; host temp/debug/prefs local | Transcript/catalog tests and host exception checks |
| Apps | Framework | Apps catalog and app surface | `claw apps list|upsert`; ClawJS apps/resource APIs | Framework workspace storage | Reject App Support as canonical Apps path |
| Design | Framework | Styles, templates, references, editor | `claw design list|upsert`; design resource types in registry/runtime | Framework workspace storage | Design fixtures and storage boundary tests |
| Browser tool | Host | Browser/right sidebar | Host browser policy/API/audit | Host policy plus UI cache | Approval/policy tests |
| Screen tools | Host | Capture tools | `HostActionPolicy` approval/audit API | Host policy plus UI prefs | Signed-host permission validation + policy tests |
| Mac Utilities | Host | Native utility controls | `HostActionPolicy` approval/audit API | Host policy + host action audit | Approval/audit tests |
| Git workflow | Framework + Host | Git workflow affordances | Framework git/resource APIs plus host policy | Framework resource plus host policy | Policy fixtures |
| Remote Mesh | Framework + Host | Mesh targets and status | Framework mesh APIs and bridge fixtures | Framework runtime plus host state | Mesh API and bridge parity tests |
| OpenCode/runtime adapters | Framework | Runtime adapter selector | Framework runtime adapter registry | Framework runtime | Adapter registry tests |
| Local Models | Host + Framework | Model availability/selection | Framework capability records | Host model cache; framework capability metadata | No synced blob guard |
| Telegram/Connections QA | Framework + Host | Integration settings and QA state | ClawJS Integration QA Lab and provider matrices | Framework integration records; host secret refs | Hermetic QA tests; live checks `EXTERNAL PENDING` |
| Publishing | Framework | Calendar/composer/channels | `claw content brand|destination|campaign|entry|approval|publish`; content Relay read/write routes | Framework publishing storage | Publishing approval fixtures; live channel publish `EXTERNAL PENDING` without explicit approval |
| Database and Workbench | Framework + Host | Explorer and workbench | `claw database ...`, `claw db <collection> ...`, `DatabaseApiClient` | Framework database; host vault refs for credentials | Service fixtures and secret-ref tests |
| Index/Search | Framework | Catalog/search/monitors/alerts | `claw sessions index`, `claw search rebuild`, inspect storage/events/API routes | Framework resource registry | Resource fixtures and Codex read-only mirror tests |
| Marketplace | Framework | Offers/wants/prospects/receipts | `claw marketplace choice`, marketplace identity/profile/vertical APIs | Framework marketplace storage | Contract fixtures; payment/live installs `EXTERNAL PENDING` without explicit approval |
| IoT/Home | Framework + Host | Devices/scenes/approvals | `claw iot homes|things|state|lights|climate|scenes|automations|approvals`; IoT Relay routes | Framework IoT plus host policy | Contract fixtures; physical devices `EXTERNAL PENDING` |
| Calendar | Framework + Host | Calendar mini-app | `claw calendar list|get|create|update|delete`; `claw time calendar`; host calendar command contract | Framework resource registry plus signed-host permission broker | Calendar fixtures; live macOS/provider sync `EXTERNAL PENDING` |
| Contacts | Framework + Host | Contacts mini-app | `claw contacts list|get|create|update|archive`; host contacts command contract | Framework resource registry plus signed-host permission broker | Contacts fixtures; live macOS/provider sync `EXTERNAL PENDING` |
| Life verticals | Framework | Life vertical explorer | `claw signals catalog|seed-catalog|observe|list|delete`; signal resource registry/runtime contract | Framework resource registry | Life/signal fixtures; native/provider adapters `EXTERNAL PENDING` |
| Identity/Profile | Framework | Identity/profile settings | Framework profile/identity APIs | Framework `core.sqlite` | Profile fixtures |
| Claw framework status | Framework + Host | Framework settings/status | `claw` CLI, SDK, host status APIs | Framework global plus host state | Host/framework status tests |

## Dev-Only Matrix

| Surface | Owner | Human UI | Programmatic Surface | Boundary | Required Validation |
| --- | --- | --- | --- | --- | --- |
| Simulators | Host | Developer sidebar items | Launcher/preflight dev tooling | Host dev state | Release visibility tests ensure it is not product v1 |
| iOS Skills seed catalog | Framework | Local iOS layout scratch surface only, not product navigation | Blocked until iOS consumes real `skillsList`/`skillsView` bridge frames | No product storage; seed data only | Interface guard rejects iOS product navigation to `SkillsListView` |
| Windows WinUI shell | Host | WinUI shell with visible `Phase 4` action stubs | Bridge/Core parity only; GUI actions are not v1 product commitments | Host-local dev state | Interface guard requires explicit `dev-only` classification while stubs remain |

## Guardrails

- `schemaVersion` is retained for the bridge JSON wire contract and must be `1`.
- Bridge docs and public wire names use `session`, not stable `chat`.
- Public bridge names use `sendMessage`, `WireSession`, `sessionUpdated`, and
  `hostDisplayName`.
- Stable Clawix defaults must use port `24080`.
- Retired chat, OAuth callback, and pairing-token deep link spellings are not
  accepted v1 contracts.
- `FeatureFlags.developerSurfaces` is only for surfaces classified as
  `dev-only`; it may not be used as a reason to skip any current stable
  surface from this matrix.
