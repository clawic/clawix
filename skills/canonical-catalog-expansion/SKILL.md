---
name: canonical-catalog-expansion
description: Add or improve canonical data catalog collections, fields, aliases, relations, evidence tags, docs, and tests.
keywords: [catalog, database, collections, schemas, fields, relations]
---

# canonical-catalog-expansion

Grow the canonical data catalog without degrading schema quality.

## Procedure

1. Read `docs/canonical-data-catalog.md`, the catalog ADR, data-storage boundary, and naming guide.
2. Use `claw collections list`, `claw collections <collection> schema`, and `claw db <collection> list|query` when available.
3. Decide whether the entity is built-in canonical or belongs in a custom database.
4. Add purpose, evidence tags, sparse optional fields, semantic relation fields, aliases, and migration/debt notes.
5. Keep user-facing structured records in the main database unless a sidecar reason is technical and explicit.
6. Update docs, tests, generated catalog coverage, and CLI/schema discovery together.

## Constraints

- A business category alone is not a reason for a separate database.
- Separate sidecars for volume, churn, blobs, sync complexity, logs, caches, encrypted vaults, or reconstructable indexes.
- Do not let Clawix define a parallel canonical schema.
