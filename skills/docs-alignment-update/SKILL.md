---
name: docs-alignment-update
description: Update docs, playbooks, shims, generated docs, and alignment checks so public instructions route to the right canonical sources.
keywords: [docs, alignment, agents, claude, decision-map, playbooks]
---

# docs-alignment-update

Keep documentation aligned with behavior and routing.

## Procedure

1. Identify the canonical source for the changed behavior before editing docs.
2. Update public docs, README, playbooks, `AGENTS.md`, `CLAUDE.md` shims, generated docs, and decision maps only where they route to or explain that source.
3. Keep `AGENTS.md` compact; link to skills or docs for procedures.
4. Add alignment-check snippets only for durable rules worth enforcing.
5. Remove stale duplicated instructions when a canonical doc or skill supersedes them.
6. Run docs alignment/link checks or record why they cannot run.

## Constraints

- Do not make `CLAUDE.md` a second instruction source.
- Do not duplicate long ADR or playbook content inside `AGENTS.md`.
- Public docs must not contain private paths, signing identities, or personal workflow instructions.
