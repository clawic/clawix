---
name: visual-regression
description: Run and interpret Clawix UI geometry, screenshot, protected-surface, and debt-baseline checks without authorizing visual repair.
keywords: [ui, visual, regression, screenshots, geometry, baseline]
---

# visual-regression

Use when validating that UI has not drifted.

## Procedure

1. Read `docs/adr/0010-interface-governance.md`, `docs/ui/README.md`, and the
   relevant pattern manifests.
2. Run public checks:
   ```
   node scripts/ui_governance_guard.mjs
   node scripts/ui_rendered_geometry_manifest_check.mjs
   node scripts/ui_private_baseline_manifest_check.mjs
   ```
3. When private visual baselines are available, run the private/local screenshot
   and geometry comparison for the changed surface:
   ```
   CLAWIX_UI_PRIVATE_GEOMETRY_ROOT=<private-root> node scripts/ui_private_geometry_verify.mjs --require-approved
   CLAWIX_UI_PRIVATE_BASELINE_ROOT=<private-root> node scripts/ui_private_baseline_verify.mjs --require-approved
   ```
4. Classify findings as protected-surface drift, new visual debt, expired
   exception, missing registry mapping, or non-visual false positive.
5. Report out-of-scope drift; do not repair it unless the active model and task
   are explicitly visual-authorized.

## Constraints

- Private screenshots/baselines stay outside the public repo.
- Passing public checks does not approve a new visual direction.
- A user-approved baseline is required before a surface becomes protected.
