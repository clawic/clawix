# V1 Surface Closure Completion Audit

Source conversation: `019e2727-cf2b-7c41-9feb-1fd2b5c77554`
Source session: private session, not published

This audit records the required one-by-one review of the private source
conversation before the v1 surface closure goal can be closed. It mirrors the
37 binding answers from the private source without publishing private paths or
private local files.

Source extraction:

- 39 `request_user_input` prompts were reviewed.
- 37 binding answers are mirrored in `docs/v1-surface-closure-decisions.json`.
- 2 excluded prompts are documented: `bridge_manifest_source` had no output
  after rollback, and the first `bridge_version_field` request failed in
  Default mode before the later answered prompt.
- The free-form `apps_design_storage` concern is retained as the inventory
  requirement for the later `apps_design_contract_status` move-now decision.
- Acceptance validation matrix: `docs/v1-surface-closure-acceptance.json`
  records mandatory closure categories: `bridge-swift`, `bridge-android`,
  `bridge-windows`, `deep-links`, `pairing`, `storage-boundary`,
  `framework-owned-artifacts`, `host-tools-policy`, `provider-routing`,
  `mcp-registry`, `integrations-qa`,
  `domain-resource-fixtures`, `docs-alignment`, `source-size`,
  `public-hygiene`, and `external-pending-policy`.
- Validation ledger: `docs/v1-surface-closure-validation.json` records latest
  local pass, `EXTERNAL PENDING`, and blocked-tooling status per acceptance
  category.

Status vocabulary:

- `verified`: current repository evidence proves the decision is implemented or intentionally documented.
- `external-pending`: current repository evidence proves the program path exists, but final validation depends on a physical device, provider, paid service, native permission, or live external system.

| # | Decision | Required answer | Review status | Evidence |
| --- | --- | --- | --- | --- |
| 1 | `bridge_contract_v1` | Align all current bridge contracts as v1 | verified | Clawix `docs/interface-matrix.md`, `scripts/interface_surface_guard.mjs`, bridge fixtures, and ClawJS `surface-registry` classify the bridge as v1. |
| 2 | `bridge_version_field` | Keep `schemaVersion` | verified | Clawix bridge guard rejects `protocolVersion` and requires `schemaVersion: 1`; naming docs document the bridge exception. |
| 3 | `bridge_source_of_truth` | Swift plus JSON fixtures, no v8/legacy narrative | verified | Clawix guard checks Swift/fixture parity and stale bridge-history spellings; docs use the clean v1 contract. |
| 4 | `active_target_scope` | Align Android and Windows active targets | verified | Android and Windows bridge round-trip tests assert `schemaVersion: 1`, session vocabulary, JSON pairing, and port `24080`. |
| 5 | `framework_store_ownership` | Framework-owned | verified | Clawix interface matrix assigns agents, skills, connections, apps, design, audio, MCP, providers, snippets, and integrations to framework contracts. |
| 6 | `surface_parity_gate` | Real gate | verified | `scripts/interface_surface_guard.mjs` validates `docs/interface-surface-clawix.registry.json` and `docs/interface-matrix.md`. |
| 7 | `session_deep_link` | `clawix://session/<sessionId>` | verified | Clawix deep-link tests accept `session` and reject retired `chat`; the matrix and naming guide use the session route. |
| 8 | `oauth_deep_link` | `clawix://auth/callback/<provider>` | verified | Clawix OAuth strategy, deep-link tests, matrix, and naming guide use `auth/callback` and reject retired `oauth-callback`. |
| 9 | `pairing_qr_contract` | JSON bridge QR | verified | Clawix Android/Windows/macOS pairing tests and matrix require JSON with `v`, `host`, `port`, `token`, `shortCode`, and `hostDisplayName`. |
| 10 | `registry_shape` | Separate registries | verified | Clawix keeps `interface-surface-clawix.registry.json` separate from `persistent-surface-clawix.manifest.json`. |
| 11 | `bridge_v1_frame_scope` | All current frames are v1 | verified | Bridge fixtures and guards cover session, agent, audio, skill, rate-limit, index, pairing, and auth frame families as v1. |
| 12 | `send_frame_name` | `sendMessage` | verified | Clawix bridge decoder/encoder and guard reject retired `sendPrompt` in public bridge surfaces. |
| 13 | `chat_session_vocabulary` | Wire uses Session vocabulary | verified | Clawix bridge types use `WireSession`, `sessionUpdated`, and `sessionId`; `chat` remains UI vocabulary. |
| 14 | `host_display_name` | `hostDisplayName` | verified | Clawix and ClawJS pairing/auth contracts and tests use `hostDisplayName`; guard rejects `macName`. |
| 15 | `client_kind_values` | `companion` and `desktop` | verified | Bridge auth/client identity fixtures and guard encode client role separately from platform metadata. |
| 16 | `client_identity_fields` | Add client IDs | verified | Bridge protocol registry and fixtures include `clientId`, `installationId`, and `deviceId`. |
| 17 | `storage_bucket_policy` | Bucket policy | verified | `docs/data-storage-boundary.md`, Clawix storage guard, and persistent-surface manifest classify framework, host, vault, and cache buckets. |
| 18 | `apps_design_storage` | Move now | verified | Clawix interface/storage guards reject App Support as canonical Apps/Design storage and point to framework workspace storage. |
| 19 | `audio_dictation_storage` | Framework audio | verified | Clawix matrix and ClawJS audio CLI/package fixtures put audio catalog/transcripts in framework audio, leaving host temp/debug/prefs local. |
| 20 | `agent_skill_storage_format` | Hybrid framework | verified | Clawix matrix and ClawJS agents/skills contracts use filesystem content plus `core.sqlite` indexes, policies, audit, and secret refs. |
| 21 | `project_identity_storage` | Resource canonical | verified | Clawix storage boundary docs and guards treat ClawJS resource IDs as identity and host paths as mutable locators/cache. |
| 22 | `secrets_boundary` | Host/vault only | verified | Storage boundary guard and matrix require opaque framework refs and reject plaintext secrets in framework storage. |
| 23 | `local_models_storage` | Host capability | verified | Clawix matrix classifies model binaries/cache as host-local and framework exposure as capability metadata. |
| 24 | `agent_tools_policy` | Host API plus matrix | verified | Browser, Screen Tools, Mac Utilities, Git, Remote Mesh, OpenCode, and Simulators are covered by matrix rows, host policy/audit, or dev-only classification. |
| 25 | `quickask_prompts_storage` | Framework snippets | verified | Clawix matrix maps QuickAsk prompt/template content to framework snippets while host hotkey/panel state stays local. |
| 26 | `provider_config_owner` | Framework plus vault | verified | Clawix matrix and storage guard classify provider settings/routing as framework config with credentials in host vault refs. |
| 27 | `external_integrations_policy` | Framework QA | external-pending | Hermetic QA and matrix coverage exist; live provider checks remain `EXTERNAL PENDING` without explicit approval. |
| 28 | `mcp_config_policy` | Framework registry | verified | Clawix matrix and host-ownership docs treat external host configs such as Codex as read-only sources and route edits through framework registry/API. |
| 29 | `experimental_surface_policy` | Classify everything | verified | Clawix interface matrix has stable, dev-only, and removed statuses and guard rejects broad beta/experimental skips. |
| 30 | `domain_verticals_policy` | Close all now | external-pending | Calendar, Contacts, Life, Database, Index, Marketplace, IoT, and Publishing have matrix/programmatic contracts; live providers/devices/payments remain `EXTERNAL PENDING`. |
| 31 | `vertical_completion_depth` | Minimum contract | verified | Domain rows include owner, storage boundary, API/events/resource shape, fixture/validation target, and UI/programmatic parity. |
| 32 | `migration_policy_no_users` | Clean v1 cut | verified | Guards reject v5/v8, retired bridge names, old ports, retired deep links, and legacy pairing-token stable contracts. |
| 33 | `repo_scope` | Clawix plus ClawJS | verified | Evidence spans Clawix host/UI matrix and ClawJS framework contracts, CLI registry, resources, and domain fixtures. |
| 34 | `missing_domain_contracts` | Resource registry first | verified | Calendar, Contacts, Life, Index, and Design are represented through framework resource/API registry contracts before standalone package expansion. |
| 35 | `execution_batching` | Closed batches | verified | Each closure batch is committed with targeted gates; Clawix and ClawJS matrices/guards are updated with the implementation. |
| 36 | `experimental_correction` | Do not skip existing experimental surfaces | verified | The matrix explicitly classifies current surfaces as stable, dev-only, or removed and the guard rejects unclassified stable skips. |
| 37 | `external_pending_policy` | Separate external validation | verified | Clawix interface matrix and completion gates record physical, paid, provider, destructive, and permission-bound checks as `EXTERNAL PENDING`. |

Current close condition: all listed decisions have public-safe implementation
or explicit external-pending evidence. Completion remains blocked while the
validation ledger reports `blocked-tooling` for Android and Windows bridge
tests. The private source session must also be re-read again immediately before
any `update_goal(status=complete)` call.
