# Code Hygiene Decision Checklist

Source conversation: `019e2bee-b635-7c51-b569-bd31b3cca875`

This checklist is required before the code hygiene goal can be closed. Every
decision must be marked `implemented`, `validated`, `documented`, or `blocked`
with concrete evidence.

| Decision | Required answer | Status | Evidence |
| --- | --- | --- | --- |
| `strictness` | Fallar solo lo claro | documented | ADR 0016 and `code-hygiene-check` bootstrap. |
| `scope` | Clawix + ClawJS | documented | ADR 0016 and mirrored Clawix artifacts. |
| `enum_policy` | Conservar si son canon | documented | ADR 0016 report-only semantic policy. |
| `rollout_model` | Limpiar todo primero | blocked | Cleanup campaign is pending. |
| `baseline_governance` | Motivo + caducidad | implemented | Baseline schema/checker require expiry metadata; Clawix web contract findings are baselined with owner, reason, reference, and 2026-08-15 expiry. |
| `autofix_policy` | Solo sugerir cambios | documented | Audit/cleanup skills prohibit default destructive autofix. |
| `export_policy` | API publica se conserva | partially implemented | ADR 0016 public contract retention rule; Clawix web bridge/UI/icon exports are retained via expiring baseline pending next review. |
| `unused_files` | Entrypoints configurados primero | partially implemented | Knip config declares explicit entry/project scope; Clawix web cleanup cleared file findings and reduced export/type noise. |
| `dependency_policy` | Normalizar por workspace | partially implemented | Web cleanup removed unused dependencies and package-script binaries; Tailwind retained as calibrated build dependency. |
| `swift_tooling` | Periphery calibrado | partially implemented | Periphery 3.7.4 runner and report pair exist with Swift retention flags; local binary install remains `EXTERNAL PENDING`. |
| `swift_public` | Conservar como contrato | documented | ADR 0016 public Swift retention rule. |
| `swiftui_dynamic` | Retener por patron | documented | ADR 0016 semantic report-only rule. |
| `semantic_placeholders` | Issue/backlog o ADR | documented | ADR 0016 future-intent rule. |
| `enum_members` | Report-only con canon | documented | ADR 0016 semantic report-only rule. |
| `todo_policy` | Si, con categorias | partially implemented | Report-only `code-hygiene-audit` scans TODO/FIXME/HACK/XXX and records categories; cleanup classification pending. |
| `duplication_scope` | Codigo + assets obvios | partially implemented | Report-only `code-hygiene-audit` detects byte-identical duplicate assets; code duplicate scan pending. |
| `duplicate_severity` | Report-only al inicio | documented | ADR 0016 semantic report-only rule. |
| `asset_policy` | Eliminar si no referenciado | partially implemented | Report-only audit now detects duplicate assets and unreferenced asset candidates; removal remains pending cleanup review. |
| `test_code_policy` | Si, pero con fixtures protegidas | documented | Cleanup skill procedure. |
| `generated_policy` | Manifest + marcadores | documented | ADR 0016 generated/vendor rule. |
| `docs_references` | Solo docs canonicas | documented | ADR 0016 public/canonical retention rule. |
| `cleanup_batching` | Por categoria y repo | documented | Cleanup skill procedure. |
| `ci_gate` | Changed + release | partially implemented | ClawJS/Clawix changed lanes call hygiene check; full release proof pending. |
| `report_format` | JSON + Markdown | implemented | `docs/code-hygiene-report.json` and `.md`. |
| `skill_shape` | Dos skills | implemented | `code-hygiene-audit`, `code-hygiene-cleanup`. |
| `skill_location` | ClawJS y proyectada | partially implemented | ClawJS canonical skills exist; Clawix projection exists pending full repo validation. |
| `recurrence` | Cada campana + pre-release | documented | ADR 0016 and ledger; automation cadence pending. |
| `ledger` | Si, compacto | implemented | `docs/code-hygiene-ledger.md`. |
| `expiry_window` | 90 dias | implemented | Baseline default and checker. |
| `cleanup_safety` | Checks verdes por lote | documented | Cleanup skill procedure. |
| `knip_install` | Dev dependency fija | implemented | Package metadata, lockfile, Knip config, exact-version runner, and report-only summary. |
| `periphery_install` | Tool versionada | partially implemented | Periphery is pinned to 3.7.4 with a report-only runner and explicit external pending until the binary is installed. |
| `new_deps_policy` | Solo herramientas justificadas | documented | Tool registry and ADR 0016. |
