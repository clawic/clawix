---
name: source-file-boundary-refactor
description: Split or contain large source files according to the source-file boundary ADR without changing behavior opportunistically.
keywords: [source-size, refactor, boundaries, large-files, modules]
---

# source-file-boundary-refactor

Reduce source-file boundary debt.

## Procedure

1. Read the source-file boundary ADR and current baseline before editing.
2. Identify the responsibility boundary: parsing, registry data, UI state, rendering, service wiring, tests, fixtures, or utilities.
3. Extract one responsibility at a time while preserving public behavior.
4. Keep entrypoints thin: parse flags, delegate, and return.
5. Add or preserve tests that prove behavior did not change.
6. Update baselines only for accepted exceptions, not to hide new growth.

## Constraints

- Do not mix behavior changes into mechanical extraction unless needed for compilation.
- Do not grow files above limits except for extraction or explicit architecture approval.
- Prefer existing package patterns over new abstraction styles.
