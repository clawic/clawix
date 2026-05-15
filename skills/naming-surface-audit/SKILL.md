---
name: naming-surface-audit
description: Audit and improve stable names, aliases, vocabulary, field casing, routes, ports, packages, and agent-search discoverability.
keywords: [naming, aliases, vocabulary, casing, routes, packages, search]
---

# naming-surface-audit

Improve naming quality across public and stable surfaces.

## Procedure

1. Read the naming guide, naming ADR, and decision-map rows for the affected surface.
2. Inventory names across code, docs, tests, CLI help, schemas, events, tables, package manifests, ports, env vars, and generated registries.
3. Check casing rules: JSON/API/YAML/framework fields use `camelCase`; CLI flags use `kebab-case`; SQL/collections use `snake_case`; events use `domain.action`.
4. Identify stale synonyms, ambiguous abbreviations, legacy names, or names that agents cannot search naturally.
5. Prefer explicit aliases and migration notes over silent renames when the surface is public.
6. Add or update guards when a naming rule should stay frozen.

## Constraints

- Do not rename a public surface without a migration or explicit pre-public removal decision.
- Do not introduce project-private brands, bundle ids, local paths, or maintainer names.
- Names must be human-meaningful and agent-discoverable.
