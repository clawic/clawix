# Interface governance

This directory is the machine-readable interface governance layer for Clawix.
It complements `STYLE.md`, `STANDARDS.md`, and `macos/PERF.md`.

The system protects approved UI and prevents visual drift. It is not a license for agents to repair unrelated UI. If a guard finds visual debt outside the current authorized scope, the correct result is a tracked pending item.

## Mutation classes

- `functional-ui`: wiring, state, loading/error behavior, actions, and
  accessibility behavior that does not change presentation.
- `visual-ui`: color, spacing, size, icon, layout, animation, hierarchy, or
  typography changes.
- `copy-ui`: visible labels, tooltips, names, microcopy, empty/loading/error
  text, and copy hierarchy.
- `mechanical-equivalent-refactor`: extraction or cleanup that proves identical
  rendered output.

Only an explicitly authorized visual lane may make `visual-ui` or `copy-ui`
decisions. The concrete authorization assignment is private and stays outside
the public repo.

## Files

- `interface-governance.config.json`: global guard configuration.
- `pattern-registry/`: pattern manifests and human notes.
- `visible-surfaces.inventory.json`: current visible UI candidate inventory.
- `debt.baseline.json`: frozen existing visual drift.
- `protected-surfaces.registry.json`: user-approved frozen visual surfaces.
- `performance-budgets.registry.json`: critical-flow budget registry.
- `private-baselines.manifest.json`: public contract for private visual,
  geometry, and performance baselines.
- `visual-change-proposal.template.md`: conceptual-only proposal template for
  non-authorized visual/copy/layout changes.
- `inspiration/`: non-canonical external references.

## Required workflow

1. Classify the change as functional, visual, copy, or mechanical-equivalent.
2. If it is visual/copy, verify the active lane is privately authorized and the
   scope is explicitly authorized.
3. Find the relevant pattern in the registry.
4. Use the pattern's geometry, state, copy, and validation contract.
5. If a guard finds unrelated drift, list it. Do not fix it as a side effect.
6. If a component is extracted, prove visual equivalence or leave it as a
   conceptual proposal.
7. Keep geometry contracts current with `scripts/ui_geometry_contract_check.mjs`.
8. Keep visible source coverage current with `scripts/ui_surface_inventory_check.mjs`.
9. Keep private baseline coverage current with
   `scripts/ui_private_baseline_manifest_check.mjs`; the public repo stores only
   safe hashes, aliases, tolerances, and runner IDs.
10. When the lane is not visual-authorized, use
   `visual-change-proposal.template.md` instead of changing presentation.
