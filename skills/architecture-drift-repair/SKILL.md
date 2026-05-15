---
name: architecture-drift-repair
description: Repair confirmed architecture drift in small batches while preserving public canon and avoiding broad opportunistic refactors.
keywords: [architecture, drift, repair, adr, guardrail, refactor]
---

# architecture-drift-repair

Repair a confirmed mismatch between implementation and accepted architecture.

## Procedure

1. Begin from a specific drift finding, ADR, decision-map row, failing guard, or documented contradiction.
2. Re-read the canonical source and the smallest affected implementation area.
3. Define a batch that can be reviewed independently and should compile independently.
4. Update implementation, docs, tests, manifests, and guardrails together when the drift crosses those surfaces.
5. If the drift requires a broad migration, land only a bounded preparatory repair and record the remaining debt.
6. Validate with the relevant focused checks before broader lanes.

## Constraints

- Keep repairs small; "align with the Constitution" is not permission for a sweeping refactor.
- Do not hide drift by deleting checks, weakening docs, or bypassing ownership boundaries.
- Preserve unrelated user or agent work in a dirty tree.
