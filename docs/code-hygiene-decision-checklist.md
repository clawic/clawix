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
| `rollout_model` | Limpiar todo primero | validated | Initial cleanup completed: blocking findings, actionable TODO/FIXME/HACK/XXX findings, unreferenced asset candidates, and clear web file/dependency findings are zero; semantic exports and Swift calibration remain baselined/report-only or `EXTERNAL PENDING`. |
| `baseline_governance` | Motivo + caducidad | implemented | Baseline schema/checker require expiry metadata; Clawix web contract findings are baselined with owner, reason, reference, and 2026-08-15 expiry. |
| `autofix_policy` | Solo sugerir cambios | documented | Audit/cleanup skills prohibit default destructive autofix. |
| `export_policy` | API publica se conserva | implemented | ADR 0016 public contract retention rule; Clawix web bridge/UI/icon exports are retained via expiring baseline with owner, reason, reference, and expiry. |
| `unused_files` | Entrypoints configurados primero | implemented | Knip config declares explicit entry/project scope; Clawix web cleanup cleared file findings and reduced export/type noise. |
| `dependency_policy` | Normalizar por workspace | implemented | Web cleanup removed unused dependencies and package-script binaries; Tailwind retained as calibrated build dependency. |
| `swift_tooling` | Periphery calibrado | blocked | Periphery 3.7.4 runner and report pair exist with Swift retention flags; local binary install remains `EXTERNAL PENDING`. |
| `swift_public` | Conservar como contrato | documented | ADR 0016 public Swift retention rule. |
| `swiftui_dynamic` | Retener por patron | documented | ADR 0016 semantic report-only rule. |
| `semantic_placeholders` | Issue/backlog o ADR | documented | ADR 0016 future-intent rule. |
| `enum_members` | Report-only con canon | documented | ADR 0016 semantic report-only rule. |
| `todo_policy` | Si, con categorias | validated | `code-hygiene-audit` scans TODO/FIXME/HACK/XXX with categories; actionable findings are zero after generated/self-test calibration. |
| `duplication_scope` | Codigo + assets obvios | implemented | Knip reports code duplicate candidates when present and `code-hygiene-audit` detects byte-identical duplicate assets; duplicate severity remains report-only by decision. |
| `duplicate_severity` | Report-only al inicio | documented | ADR 0016 semantic report-only rule. |
| `asset_policy` | Eliminar si no referenciado | validated | Unreferenced asset candidates are zero after excluding generated/public/platform surfaces from cleanup candidates; duplicate assets remain report-only. |
| `test_code_policy` | Si, pero con fixtures protegidas | documented | Cleanup skill procedure. |
| `generated_policy` | Manifest + marcadores | documented | ADR 0016 generated/vendor rule. |
| `docs_references` | Solo docs canonicas | documented | ADR 0016 public/canonical retention rule. |
| `cleanup_batching` | Por categoria y repo | documented | Cleanup skill procedure. |
| `ci_gate` | Changed + release | validated | ClawJS/Clawix changed lanes call hygiene checks, Clawix changed lane passed locally, and release lanes include hygiene with external-only requirements reported separately. |
| `report_format` | JSON + Markdown | implemented | `docs/code-hygiene-report.json` and `.md`. |
| `skill_shape` | Dos skills | implemented | `code-hygiene-audit`, `code-hygiene-cleanup`. |
| `skill_location` | ClawJS y proyectada | validated | ClawJS canonical skills exist; Clawix projection validation passed through `check-clawjs-skills-sync`. |
| `recurrence` | Cada campana + pre-release | implemented | ADR 0016, ledger, skills, changed lane, and release lane encode campaign/pre-release use. |
| `ledger` | Si, compacto | implemented | `docs/code-hygiene-ledger.md`. |
| `expiry_window` | 90 dias | implemented | Baseline default and checker. |
| `cleanup_safety` | Checks verdes por lote | validated | Cleanup lots were followed by green code hygiene self-tests, changed-lane checks, and targeted package tests. |
| `knip_install` | Dev dependency fija | implemented | Package metadata, lockfile, Knip config, exact-version runner, and report-only summary. |
| `periphery_install` | Tool versionada | blocked | Periphery is pinned to 3.7.4 with a report-only runner and explicit `EXTERNAL PENDING` until the binary is installed. |
| `new_deps_policy` | Solo herramientas justificadas | documented | Tool registry and ADR 0016. |
