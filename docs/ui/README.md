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
- `implementation-phases.manifest.json`: phase boundary for governance-first
  work, private evidence capture, and visual cleanup execution.
- `state-coverage.manifest.json`: required interactive state source-evidence
  contract for visible UI scopes.
- `surface-references.manifest.json`: public-safe reference contract for every
  visible surface coverage entry.
- `surface-baseline-coverage.manifest.json`: public-safe private baseline,
  rendered geometry, and copy snapshot references for visible surface coverage.
  Surface evidence must include the coverage ID, platform, private baseline
  reference, capture command, and approved artifact hashes before approval.
- `rendered-drift.manifest.json`: public-safe routes, categories, and required
  failure diagnostics for private rendered drift reports.
- `gate-surface.manifest.json`: public contract for local, changed, release,
  and CI gate wiring; public CI validates lints, geometry, and manifests
  without private evidence roots.
- `visual-model-allowlist.manifest.json`: explicit visual model gate for
  visual/copy/layout mutation authority.
- `component-extraction.manifest.json`: reusable component extraction policy,
  bounded API audit rules, and mechanical-equivalence evidence requirements.
- `mechanical-equivalence.manifest.json`: before/after evidence and blocking
  status contract for mechanical UI refactors. Registered records are included
  in the derived private evidence plan through an optional private root.
- `completion-audit.md`: public-safe completion ledger that mirrors the
  private goal/session re-read rule without publishing private source content.
- `completion-source.manifest.json`: public-safe contract for privately
  verifying the goal reference and source session before final completion.
- `pattern-registry/`: pattern manifests and human notes.
- `visible-surfaces.inventory.json`: current visible UI candidate inventory.
- `copy.inventory.json`: copy canon policy and private snapshot requirements.
- `rendered-geometry.manifest.json`: public contract for private rendered
  geometry evidence.
- `visual-change-scopes.manifest.json`: public-safe approved scope metadata for
  visual/copy/layout work.
- `visual-change-detectors.manifest.json`: platform-specific source tokens and
  classification buckets for unauthorized visual/copy/layout diffs.
- `visual-proposals.registry.json`: public-safe conceptual proposal records for
  visual/copy/layout changes.
- `debt.baseline.json`: frozen existing visual drift.
- `debt-baseline.manifest.json`: compatibility alias for the original plan term
  `docs/ui/debt-baseline.*`; `debt.baseline.json` remains canonical.
- `debt-report.registry.json`: report-only pending items and fix policy
  derived from the debt baseline.
- `debt-audit.manifest.json`: public-safe contract for the private visual
  inventory audit that proves exact debt findings.
- `critical-cleanup.queue.json`: non-executable V1 delivery queue for
  visual-authorized cleanup of report-only debt.
- `exceptions.registry.json`: temporary scoped exceptions with owner, reason,
  review date, and expiry.
- `protected-surfaces.registry.json`: user-approved frozen visual surfaces.
- `approval-authority.manifest.json`: aggregate contract for explicit user
  approval authority across canon, protected surfaces, scopes, and exceptions.
- `canon-units.manifest.json`: declares UI pattern as the primary canon unit
  and requires promotion for narrower units.
- `canon-promotions.registry.json`: public-safe records for user-approved canon
  promotions.
- `performance-budgets.registry.json`: critical-flow, per-platform budget
  registry.
  Private performance evidence must include hash-backed `measurementSamples`
  for every required metric before a budget can be enforced.
- `pattern-performance.manifest.json`: critical-flow ownership mapping from
  performance budgets back to registry patterns.
- `private-baselines.manifest.json`: public contract for private visual,
  geometry, and performance baselines.
- `private-evidence-plan`: derived evidence plan emitted by
  `scripts/ui_private_evidence_plan_check.mjs`.
- `private-evidence-verifier`: end-to-end private evidence verifier backed by
  the derived plan in `scripts/ui_private_evidence_verify.mjs`.
- `private-visual-validation.manifest.json`: public contract for the aggregate
  private visual and performance evidence validation runner.
- `scripts/ui_private_evidence_verify.mjs`: private-root verifier for every
  record in the derived evidence plan.
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
   `scripts/ui_decision_verification_check.mjs`; open decisions must declare
   private evidence aliases covered by the derived evidence plan plus the
   private verifiers that block closure.
9. Keep UI debt reports current with `scripts/ui_debt_report_check.mjs`; debt
   items are report-only outside a visual-authorized cleanup scope and
   opportunistic fixes stay forbidden.
10. Keep UI debt audit contracts current with
    `scripts/ui_debt_audit_manifest_check.mjs`; private visual inventory must
    prove exact debt findings before the debt baseline can be closed.
11. Keep critical cleanup queue records current with
   `scripts/ui_critical_cleanup_queue_check.mjs`; queued cleanup remains
   non-executable until an allowlisted visual lane receives approval, and V1
   delivery can only be completed or tracked pending for that lane.
12. Keep UI exceptions current with `scripts/ui_exception_check.mjs`; active
   exceptions must be owned, approved, reviewed, and expiring.
13. Keep inspiration references current with
   `scripts/ui_inspiration_reference_check.mjs`; external references are
   non-canonical until the user explicitly promotes a Clawix decision.
14. Keep protected surface freeze contracts current with
   `scripts/ui_protected_surface_check.mjs`.
15. Keep approval authority current with
   `scripts/ui_approval_authority_check.mjs`; future approvals must be from the
   user and point to private approval evidence.
16. Keep canon unit contracts current with `scripts/ui_canon_unit_check.mjs`;
   narrower units require explicit canon promotion before becoming canon.
17. Keep geometry contracts current with `scripts/ui_geometry_contract_check.mjs`.
18. Keep UI implementation evidence output current with
   `scripts/ui_implementation_evidence_check.mjs`; every UI change must declare
   mutation class, mapping, touched files, visible surfaces, state coverage, and
   public checks.
19. Keep UI implementation phases current with
   `scripts/ui_implementation_phase_check.mjs`; governance work may proceed
   before private visual evidence, but cleanup execution stays blocked.
20. Keep interactive state source coverage current with
   `scripts/ui_state_coverage_check.mjs`; missing source evidence must be an
   explicit expiring gap.
21. Keep visible surface references current with
   `scripts/ui_surface_reference_check.mjs`; pattern references must resolve to
   public-safe repo files or docs anchors.
22. Keep visible surface baseline coverage current with
   `scripts/ui_surface_baseline_coverage_check.mjs`; every inventory entry must
   have private baseline, rendered geometry, and copy snapshot references.
23. Keep rendered drift report routes current with
   `scripts/ui_rendered_drift_check.mjs`.
24. Keep gate wiring current with `scripts/ui_release_gate_check.mjs`; UI
   governance checks must stay in local test lanes and public CI, and public CI
   must not require private evidence roots.
25. Keep rendered geometry evidence contracts current with
   `scripts/ui_rendered_geometry_manifest_check.mjs`; private pattern geometry
   evidence must include measured values plus the approved geometry hash before
   pending size clauses can become measured contracts.
26. Keep copy contracts current with `scripts/ui_copy_governance_check.mjs`;
   private copy evidence must include hashed `copyItems` plus the approved
   snapshot hash before copy can be treated as approved canon.
27. Keep performance budget contracts current with
   `scripts/ui_performance_budget_check.mjs`; budget flow references must match
   private baseline references and stay scoped to critical flows.
28. Keep pattern performance ownership current with
   `scripts/ui_pattern_performance_check.mjs`; every critical flow must map to
   registry patterns that declare the same performance contract.
29. Keep pattern registry mutation permissions current with
   `scripts/ui_pattern_mutation_guard.mjs`; geometry, copy, states, and canon
   references in pattern manifests require an allowlisted visual lane.
30. Keep component extraction APIs current with
   `scripts/ui_component_extraction_check.mjs`.
31. Keep mechanical refactor evidence current with
   `scripts/ui_mechanical_equivalence_check.mjs`.
32. Keep visual authorization scopes current with
   `scripts/ui_visual_scope_check.mjs`; no scope is authorized by default, and
   approved scopes must declare files plus a change budget.
33. Keep visual change detectors current with `scripts/ui_visual_detector_check.mjs`;
   presentation, copy, and hierarchy buckets must stay explicit.
34. Keep visual model authorization current with
   `scripts/ui_visual_model_allowlist_check.mjs`; the active model signal must
   identify an allowlisted visual model.
35. Keep visual guard failure diagnostics current with
   `scripts/ui_visual_guard_failure_check.mjs`; failures must include route,
   reason, and required permission.
36. Keep conceptual visual proposal records current with
   `scripts/ui_visual_proposal_check.mjs`.
37. Keep private artifacts out of the public repo with
   `scripts/ui_private_artifact_boundary_check.mjs`; public files may store
   aliases, manifests, hashes, and runner contracts only.
38. Keep visible source coverage current with `scripts/ui_surface_inventory_check.mjs`.
   Every visible source candidate must resolve to exactly one pattern, debt,
   exception, or protected-surface classification; use `excludeScopes` to keep
   broad public-safe globs from masking known debt.
39. Keep private baseline coverage current with
   `scripts/ui_private_baseline_manifest_check.mjs`; the public repo stores only
   safe hashes, aliases, tolerances, and runner IDs.
40. Keep the private evidence plan current with
    `scripts/ui_private_evidence_plan_check.mjs`; it derives expected private
    evidence records without requiring private roots.
41. Keep aggregate private visual validation current with
    `scripts/ui_private_visual_validation_manifest_check.mjs`.
42. Keep the completion audit current with
    `scripts/ui_completion_audit_check.mjs`; it must list every decision and
    keep open private evidence as `EXTERNAL PENDING`.
43. Keep the completion source contract current with
    `scripts/ui_completion_source_manifest_check.mjs`; final completion also
    requires `scripts/ui_private_completion_source_verify.mjs` against the
    private goal file and source session.
44. When all private roots are available, verify every record in the derived
    private evidence plan with
    `CLAWIX_UI_PRIVATE_BASELINE_ROOT=<private-root> CLAWIX_UI_PRIVATE_GEOMETRY_ROOT=<private-root> CLAWIX_UI_PRIVATE_COPY_ROOT=<private-root> CLAWIX_UI_PRIVATE_DRIFT_ROOT=<private-root> CLAWIX_UI_PRIVATE_DEBT_AUDIT_ROOT=<private-root> node scripts/ui_private_evidence_verify.mjs --require-approved`.
    If mechanical-equivalence records exist, also set
    `CLAWIX_UI_PRIVATE_MECHANICAL_EQUIVALENCE_ROOT=<private-root>`.
45. When all private roots are available, verify visual and performance
    evidence end to end with
    `CLAWIX_UI_PRIVATE_BASELINE_ROOT=<private-root> CLAWIX_UI_PRIVATE_GEOMETRY_ROOT=<private-root> CLAWIX_UI_PRIVATE_COPY_ROOT=<private-root> CLAWIX_UI_PRIVATE_DRIFT_ROOT=<private-root> CLAWIX_UI_PRIVATE_DEBT_AUDIT_ROOT=<private-root> node scripts/ui_private_visual_verify.mjs --require-approved`.
46. When private debt audit evidence is available, verify it with
    `CLAWIX_UI_PRIVATE_DEBT_AUDIT_ROOT=<private-root> node scripts/ui_private_debt_audit_verify.mjs --require-approved`.
    Debt audit evidence must include hashed `findingItems` so each private
    finding is independently accountable without publishing visual values.
47. When private geometry evidence is available, verify it with
    `CLAWIX_UI_PRIVATE_GEOMETRY_ROOT=<private-root> node scripts/ui_private_geometry_verify.mjs --require-approved`.
48. When private baselines are available, verify them with
    `CLAWIX_UI_PRIVATE_BASELINE_ROOT=<private-root> node scripts/ui_private_baseline_verify.mjs --require-approved`.
49. When private performance measurements are available, verify them with
    `CLAWIX_UI_PRIVATE_BASELINE_ROOT=<private-root> node scripts/ui_private_performance_budget_verify.mjs --require-approved`.
50. When private copy snapshots are available, verify them with
    `CLAWIX_UI_PRIVATE_COPY_ROOT=<private-root> node scripts/ui_private_copy_verify.mjs --require-approved`.
    Copy evidence must include hashed `copyItems` and `copyHierarchyHash` so
    visible text, order, and hierarchy are governed without publishing raw copy.
51. When private rendered drift reports are available, verify them with
    `CLAWIX_UI_PRIVATE_DRIFT_ROOT=<private-root> node scripts/ui_private_drift_verify.mjs --require-approved`.
    Each private report must include hashed per-category `driftResults` entries
    for every public drift category, so approval records prove what was checked
    without publishing screenshots, copy, geometry, or performance captures.
50. When the lane is not visual-authorized, use
   `visual-change-proposal.template.md` instead of changing presentation.
