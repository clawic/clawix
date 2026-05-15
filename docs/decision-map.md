# Clawix decision map

This map tells contributors and agents where durable Clawix/ClawJS decisions
live and which check or review step protects them. It is an index, not a second
source of truth: update the canonical document first, then update this map.
The contract format is decision -> document -> validation.

## Architecture and ownership

| Decision | Canonical document | Guardrail or validation |
| --- | --- | --- |
| ClawJS/Claw owns framework contracts, schemas, fixtures, storage resolution, domain APIs, and the public `claw` CLI. | [`docs/host-ownership.md`](host-ownership.md), [`docs/adr/0001-claw-framework-host-boundary.md`](adr/0001-claw-framework-host-boundary.md) | `bash scripts/doc_alignment_check.sh` requires the ownership docs and frozen terms. Review ClawJS changes against the sibling ClawJS decision map. |
| Clawix is the native human interface and an embedded signed host through `ClawHostKit`. | [`docs/host-ownership.md`](host-ownership.md), [`AGENTS.md`](../AGENTS.md) | `bash scripts/doc_alignment_check.sh` requires `ClawHostKit`, `Claw.app`, and `claw` ownership language. |
| Sensitive native permissions, approvals, grants, audit logs, LaunchAgents, Mach services, and native execution belong to the active signed host, not Node. | [`docs/host-ownership.md`](host-ownership.md), [`docs/adr/0001-claw-framework-host-boundary.md`](adr/0001-claw-framework-host-boundary.md) | Review host-dependent work with signed-host validation. Dry-run or fixture validation counts only as partial validation for sensitive permission paths. |
| Clawix consumes ClawJS CLI guidance, actor assertions, and opaque `res_*` resources; project/sidebar identity must be resource-backed while paths remain mutable locators. | [`docs/adr/0008-cli-jit-guidance-actor-assertions-resource-registry.md`](adr/0008-cli-jit-guidance-actor-assertions-resource-registry.md), [`docs/host-ownership.md`](host-ownership.md) | Migration tests must prove project renames/moves preserve sidebar, sort, snapshots, and instructions. |
| Stable capabilities are complete only when their human Clawix UI and programmatic framework/host surface are both registered; beta/experimental labels cannot exempt an existing surface from ownership, parity, fixtures, or validation. | [`docs/interface-matrix.md`](interface-matrix.md), [`docs/interface-surface-clawix.registry.json`](interface-surface-clawix.registry.json), [`docs/adr/0007-dual-human-programmatic-surfaces.md`](adr/0007-dual-human-programmatic-surfaces.md) | `node scripts/interface_surface_guard.mjs` validates every current feature surface has `stable`, `dev-only`, or `removed` status and rejects stale v1 bridge/deep-link names. |

## Storage and data placement

| Decision | Canonical document | Guardrail or validation |
| --- | --- | --- |
| Framework global data, framework databases, workspace files, host state, and GUI-only app state have separate roots. | [`docs/data-storage-boundary.md`](data-storage-boundary.md), [`docs/host-ownership.md`](host-ownership.md) | `bash scripts/doc_alignment_check.sh` requires the storage boundary and blocks stale pre-refactor roots. |
| New workspace-local framework writes use `.claw/`; `.clawjs/` is retired pre-public compatibility. | [`docs/data-storage-boundary.md`](data-storage-boundary.md), [`docs/naming-style-guide.md`](naming-style-guide.md), [`docs/adr/0002-naming-and-stability-surfaces.md`](adr/0002-naming-and-stability-surfaces.md) | `bash scripts/doc_alignment_check.sh` requires `.claw/` and retired `.clawjs` language. Code review must reject new canonical `.clawjs` writes unless a successor ADR grants a bounded exception. |
| User-facing structured records belong in `core.sqlite`; high-churn runtime/search/blob state uses sidecars; plaintext secrets never live in the main database. | [`docs/data-storage-boundary.md`](data-storage-boundary.md) | `bash scripts/doc_alignment_check.sh` requires `core.sqlite`, sidecar names, and plaintext secret language. |
| Codex data under `~/.codex` is an external read-only source by default. | [`docs/host-ownership.md`](host-ownership.md), [`docs/adr/0001-claw-framework-host-boundary.md`](adr/0001-claw-framework-host-boundary.md) | Review any Codex-source integration for read/mirror/index behavior only. Writes into Codex-owned sources need explicit reversible opt-in. |

## Runtime, bridge, and validation

| Decision | Canonical document | Guardrail or validation |
| --- | --- | --- |
| When the background bridge daemon is active, there is one runtime owner; Clawix must not also bootstrap a GUI-owned backend or second `BridgeServer`. | [`AGENTS.md`](../AGENTS.md), [`docs/host-ownership.md`](host-ownership.md), macOS bridge docs under [`playbooks/macos/`](../playbooks/macos/) | Targeted bridge E2E and code review must verify one runtime owner. PENDING GUARDRAIL: add a static check that rejects a second GUI-owned bridge bootstrap when daemon mode is enabled. |
| iOS-visible or remote-visible runtime capabilities are implemented on the daemon or host contract surface before UI clients consume them. | [`docs/host-ownership.md`](host-ownership.md), [`packages/ClawixCore/Sources/ClawixCore/BridgeProtocol.md`](../packages/ClawixCore/Sources/ClawixCore/BridgeProtocol.md) | Add or update bridge protocol fixtures/E2E before wiring UI clients. Treat UI-only validation as partial for cross-device features. |
| Validation must not send real prompts, mutate production data, touch real services, or consume paid APIs unless explicitly approved. | [`AGENTS.md`](../AGENTS.md), [`CONTRIBUTING.md`](../CONTRIBUTING.md), macOS E2E scripts under [`macos/scripts/`](../macos/scripts/) | Prefer fixtures, local backends, dry-run paths, and interceptors. Mark unavailable real integrations as `EXTERNAL PENDING` in validation reports. |
| Clawix follows the framework-owned Integration QA Lab standard for external connectors; UI wiring alone cannot make a connector complete. | [`docs/adr/0005-integration-qa-lab.md`](adr/0005-integration-qa-lab.md), ClawJS Integration QA Lab docs, [`qa/scenarios/telegram-integration-qa-lab.md`](../qa/scenarios/telegram-integration-qa-lab.md) | Clawix may display QA state or request approvals, but live checks must go through framework/host boundaries, brokered credential leases, and `EXTERNAL PENDING` reporting for unavailable provider prerequisites. |
| Host-dependent bugs require host-equivalent validation when feasible, not only hermetic tests. | [`AGENTS.md`](../AGENTS.md), [`macos/PERF.md`](../macos/PERF.md), [`playbooks/`](../playbooks/) | Use the signed app or host-equivalent launcher for final validation. Report isolated-only validation as partial. |

## Platform launch and performance

| Decision | Canonical document | Guardrail or validation |
| --- | --- | --- |
| macOS development builds go through the project launcher scripts and stable signing placeholders; public docs never include maintainer signing identities. | [`AGENTS.md`](../AGENTS.md), [`README.md`](../README.md), [`CONTRIBUTING.md`](../CONTRIBUTING.md) | `bash macos/scripts/public_hygiene_check.sh` blocks signing identity, Team ID, bundle ID, `.signing.env`, and private-path leaks. |
| macOS visible/runtime changes require the relevant build, E2E, hygiene, or playbook validation before merge. | [`CONTRIBUTING.md`](../CONTRIBUTING.md), [`playbooks/README.md`](../playbooks/README.md), [`macos/PERF.md`](../macos/PERF.md) | Run focused tests during iteration and the heavier launcher/build/playbook validation at batch boundaries. |
| Performance work starts with reproduction and instrumentation before optimization. | [`macos/PERF.md`](../macos/PERF.md) | Capture traces, logs, CPU/RAM samples, or host diagnostics before assigning cause. Separate confirmed, probable, and discarded causes. |
| Android and Web are launched through central launcher flows in the private workspace. | Private workspace operating instructions, public platform READMEs | PENDING GUARDRAIL: mirror the public, non-private launcher contract into platform docs or add public script wrappers when those surfaces become supported. |

## Source file boundaries

| Decision | Canonical document | Guardrail or validation |
| --- | --- | --- |
| Hand-authored source files stay responsibility-scoped; new 1200+ line files require a split plan or baseline exception, and 2000+ line files must not grow except for extraction or explicit architecture approval. | [`docs/adr/0004-source-file-boundaries.md`](adr/0004-source-file-boundaries.md), [`docs/source-size-baseline.json`](source-size-baseline.json) | `node scripts/source-size-check.mjs` warns at 800 lines, fails unbaselined 1200+ line files, and blocks growth above the recorded baseline. The fast test lane runs it. |

## Naming, release, privacy, and commits

| Decision | Canonical document | Guardrail or validation |
| --- | --- | --- |
| Clawix naming follows the ClawJS naming ADR, with Clawix-specific host, bridge, port, socket, deep-link, and env-var rules. | [`docs/naming-style-guide.md`](naming-style-guide.md), [`docs/adr/0002-naming-and-stability-surfaces.md`](adr/0002-naming-and-stability-surfaces.md) | `bash scripts/doc_alignment_check.sh` requires frozen Clawix naming snippets and blocks stale `clawix-bridged`/`CLAWIX_BRIDGED` agent instructions. |
| Public repositories contain only safe placeholders for signing, bundle IDs, Team IDs, launch labels, Mach services, host branding, paths, and secrets. | [`AGENTS.md`](../AGENTS.md), [`CONTRIBUTING.md`](../CONTRIBUTING.md), [`docs/host-ownership.md`](host-ownership.md) | `bash macos/scripts/public_hygiene_check.sh` is the publication gate. Review untracked/generated assets before adding them. |
| Release work is explicit and never publishes, uploads, tags, or pushes as a side effect of ordinary validation. | [`AGENTS.md`](../AGENTS.md), release notes in the private workspace | Public release scripts build artifacts only. Real release orchestration and credentials stay outside this repository. |
| Commit hygiene uses small intention-scoped commits; changesets are not a Clawix unit unless release metadata explicitly requires them. | [`AGENTS.md`](../AGENTS.md), [`CONTRIBUTING.md`](../CONTRIBUTING.md) | Review commit scope by behavior, not by file. Do not sweep unrelated edits. |

## Known pending guardrails

- PENDING GUARDRAIL: enforce "no second GUI-owned bridge/backend" with a static
  check once the bridge bootstrap points are fully centralized.
- PENDING GUARDRAIL: add a repo-wide storage writer check that flags new
  canonical `.clawjs/` writes in source code, not only docs.
- PENDING GUARDRAIL: publish a non-private launcher contract for Android/Web
  once those targets are ready for external contributors.
