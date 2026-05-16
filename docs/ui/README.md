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
- `implementation-evidence.manifest.json`: required UI implementation evidence
  and PR/check output contract.
- `state-coverage.manifest.json`: required interactive state source-evidence
  contract for visible UI scopes.
- `surface-references.manifest.json`: public-safe reference contract for every
  visible surface coverage entry.
- `visual-model-allowlist.manifest.json`: explicit visual model gate for
  visual/copy/layout mutation authority.
- `component-extraction.manifest.json`: reusable component extraction policy
  and bounded API audit rules.
- `mechanical-equivalence.manifest.json`: before/after evidence contract for
  mechanical UI refactors.
- `pattern-registry/`: pattern manifests and human notes.
- `visible-surfaces.inventory.json`: current visible UI candidate inventory.
- `copy.inventory.json`: copy canon policy and private snapshot requirements.
- `rendered-geometry.manifest.json`: public contract for private rendered
  geometry evidence.
- `visual-change-scopes.manifest.json`: public-safe approved scope metadata for
  visual/copy/layout work.
- `visual-change-detectors.manifest.json`: platform-specific source tokens for
  unauthorized visual/copy/layout diffs.
- `visual-proposals.registry.json`: public-safe conceptual proposal records for
  visual/copy/layout changes.
- `debt.baseline.json`: frozen existing visual drift.
- `debt-baseline.manifest.json`: compatibility alias for the original plan term
  `docs/ui/debt-baseline.*`; `debt.baseline.json` remains canonical.
- `debt-report.registry.json`: report-only pending items derived from the debt
  baseline.
- `exceptions.registry.json`: temporary scoped exceptions with owner, reason,
  review date, and expiry.
- `protected-surfaces.registry.json`: user-approved frozen visual surfaces.
- `canon-promotions.registry.json`: public-safe records for user-approved canon
  promotions.
- `performance-budgets.registry.json`: critical-flow budget registry.
- `private-baselines.manifest.json`: public contract for private visual,
  geometry, and performance baselines.
- `private-visual-validation.manifest.json`: public contract for the aggregate
  private visual validation runner.
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
7. Keep canon promotion records current with
   `scripts/ui_canon_promotion_check.mjs`; only the user can approve a
   promotion.
8. Keep decision verification evidence current with
   `scripts/ui_decision_verification_check.mjs`.
9. Keep UI debt reports current with `scripts/ui_debt_report_check.mjs`; debt
   items are report-only outside a visual-authorized cleanup scope.
10. Keep UI exceptions current with `scripts/ui_exception_check.mjs`; active
   exceptions must be owned, approved, reviewed, and expiring.
11. Keep protected surface freeze contracts current with
   `scripts/ui_protected_surface_check.mjs`.
12. Keep geometry contracts current with `scripts/ui_geometry_contract_check.mjs`.
13. Keep UI implementation evidence output current with
   `scripts/ui_implementation_evidence_check.mjs`; every UI change must declare
   mutation class, mapping, touched files, visible surfaces, state coverage, and
   public checks.
14. Keep interactive state source coverage current with
   `scripts/ui_state_coverage_check.mjs`; missing source evidence must be an
   explicit expiring gap.
15. Keep visible surface references current with
   `scripts/ui_surface_reference_check.mjs`; pattern references must resolve to
   public-safe repo files or docs anchors.
16. Keep rendered geometry evidence contracts current with
   `scripts/ui_rendered_geometry_manifest_check.mjs`.
17. Keep copy contracts current with `scripts/ui_copy_governance_check.mjs`.
18. Keep performance budget contracts current with
   `scripts/ui_performance_budget_check.mjs`; budget flow references must match
   private baseline references.
19. Keep component extraction APIs current with
   `scripts/ui_component_extraction_check.mjs`.
20. Keep mechanical refactor evidence current with
   `scripts/ui_mechanical_equivalence_check.mjs`.
21. Keep visual authorization scopes current with
   `scripts/ui_visual_scope_check.mjs`; no scope is authorized by default, and
   approved scopes must declare files plus a change budget.
22. Keep visual change detectors current with `scripts/ui_visual_detector_check.mjs`.
23. Keep visual model authorization current with
   `scripts/ui_visual_model_allowlist_check.mjs`; the active model signal must
   identify an allowlisted visual model.
24. Keep visual guard failure diagnostics current with
   `scripts/ui_visual_guard_failure_check.mjs`.
25. Keep conceptual visual proposal records current with
   `scripts/ui_visual_proposal_check.mjs`.
26. Keep visible source coverage current with `scripts/ui_surface_inventory_check.mjs`.
27. Keep private baseline coverage current with
   `scripts/ui_private_baseline_manifest_check.mjs`; the public repo stores only
   safe hashes, aliases, tolerances, and runner IDs.
28. Keep aggregate private visual validation current with
    `scripts/ui_private_visual_validation_manifest_check.mjs`.
29. When all private roots are available, verify visual evidence end to end with
    `CLAWIX_UI_PRIVATE_BASELINE_ROOT=<private-root> CLAWIX_UI_PRIVATE_GEOMETRY_ROOT=<private-root> CLAWIX_UI_PRIVATE_COPY_ROOT=<private-root> node scripts/ui_private_visual_verify.mjs --require-approved`.
30. When private geometry evidence is available, verify it with
    `CLAWIX_UI_PRIVATE_GEOMETRY_ROOT=<private-root> node scripts/ui_private_geometry_verify.mjs --require-approved`.
31. When private baselines are available, verify them with
    `CLAWIX_UI_PRIVATE_BASELINE_ROOT=<private-root> node scripts/ui_private_baseline_verify.mjs --require-approved`.
32. When private copy snapshots are available, verify them with
    `CLAWIX_UI_PRIVATE_COPY_ROOT=<private-root> node scripts/ui_private_copy_verify.mjs --require-approved`.
33. When the lane is not visual-authorized, use
   `visual-change-proposal.template.md` instead of changing presentation.
