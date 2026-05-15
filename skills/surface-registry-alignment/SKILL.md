---
name: surface-registry-alignment
description: Align stable paths, APIs, CLI commands, schemas, events, IDs, storage keys, and UI/programmatic parity with the surface registries.
keywords: [surface, registry, cli, api, events, schemas, parity]
---

# surface-registry-alignment

Keep stable surfaces registry-backed and inspectable.

## Procedure

1. Read the surface registry ADR, interface matrix, decision map, and relevant generated manifest.
2. Identify every new or changed stable surface: CLI command, API route, event, schema, ID prefix, storage path, preference key, database table, or UI capability.
3. Register it through the typed registry or the project-approved manifest path.
4. Ensure `claw inspect` or the equivalent inspection surface can explain the surface.
5. Classify human and programmatic surfaces as `stable`, `local-only`, `blocked`, `not applicable`, or another accepted status.
6. Add tests or guards that reject manual lists drifting away from registry truth.

## Constraints

- Manual docs are allowed as generated output or explanations, not as the registry source.
- UI-only capabilities are incomplete unless a programmatic surface exists or the gap is classified.
- Do not copy whole provider schemas into Claw-owned registries.
