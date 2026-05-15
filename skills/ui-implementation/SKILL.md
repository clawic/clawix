---
name: ui-implementation
description: Implement functional Clawix UI wiring while respecting visual mutation boundaries, pattern contracts, protected surfaces, and debt baselines.
keywords: [ui, implementation, functional-ui, wiring, state, validation]
---

# ui-implementation

Use when implementing UI behavior, state, loading/error handling, actions, or
accessibility behavior.

## Procedure

1. Read `docs/adr/0010-interface-governance.md`, `docs/ui/README.md`, and the
   relevant pattern manifest.
2. Declare the mutation class. Non-authorized agents may proceed only for
   `functional-ui` or governance/tooling work.
3. Keep visual shape stable. Do not change colors, spacing, typography, icons,
   layout, hierarchy, animations, or visible copy unless explicitly authorized.
4. If a guard reports out-of-scope visual debt, list it as pending. Do not fix
   it in the current change.
5. Run `node scripts/ui_governance_guard.mjs` and the focused functional tests.

## Constraints

- No opportunistic visual cleanup.
- No protected-surface edits without explicit permission.
- Mechanical extraction requires before/after equivalence evidence.
