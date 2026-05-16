---
name: ui-canon-review
description: Review whether a Clawix UI pattern, visual decision, copy change, or component extraction belongs in canon, debt, exception, or protected-surface scope.
keywords: [ui, interface, canon, visual, registry, pattern, approval]
---

# ui-canon-review

Use when deciding whether a UI change should become Clawix canon.

## Procedure

1. Read `docs/adr/0010-interface-governance.md`, `docs/ui/README.md`,
   `STYLE.md`, and the relevant pattern manifest under
   `docs/ui/pattern-registry/`.
2. Classify the change as `functional-ui`, `visual-ui`, `copy-ui`, or
   `mechanical-equivalent-refactor`.
3. If the change affects `visual-ui` or `copy-ui`, verify explicit user
   approval and the private visual authorization policy. Non-authorized agents
   stop at a conceptual proposal.
   For approved copy, verify private copy snapshot evidence:
   ```
   CLAWIX_UI_PRIVATE_COPY_ROOT=<private-root> node scripts/ui_private_copy_verify.mjs --require-approved
   ```
4. Decide whether the change maps to an existing pattern, creates a new
   pattern, extends debt, needs a timed exception, or requires protected-surface
   approval.
5. Never promote local visual taste to global canon without explicit user OK.

## Constraints

- Do not repair unrelated drift.
- Do not change protected surfaces without explicit permission.
- External references in `docs/ui/inspiration/` are not canon by default.
