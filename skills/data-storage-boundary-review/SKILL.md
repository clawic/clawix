---
name: data-storage-boundary-review
description: Review storage placement across framework global data, workspace data, host state, sidecars, caches, vaults, and external sources.
keywords: [storage, database, sidecar, workspace, host-state, cache]
---

# data-storage-boundary-review

Choose or audit where data belongs.

## Procedure

1. Read data-storage boundary, host ownership docs, relevant ADRs, and surface registry entries.
2. Classify the data as framework global, workspace-local framework data, host operational state, GUI-only state, external read-only source, sidecar, cache, blob store, or vault.
3. Prefer main relational storage for user-facing structured records that benefit from relationships.
4. Use sidecars for high-churn runtime/session/audio/blob/search/notify/monitor/feed/vault data when the technical reason is explicit.
5. Ensure normal mutation goes through SDK/CLI/service/host contracts rather than direct SQLite writes from hosts.
6. Update registries, docs, tests, and migration notes.

## Constraints

- Do not introduce new canonical `.clawjs/` writes.
- Do not put plaintext secrets in the main database.
- Do not use sensitivity alone as a reason to fragment relational knowledge.
