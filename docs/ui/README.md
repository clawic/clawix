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
- `debt.baseline.json`: frozen existing visual drift.
- `protected-surfaces.registry.json`: user-approved frozen visual surfaces.
- `performance-budgets.registry.json`: critical-flow budget registry.
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
