# Code Hygiene Completion Audit

Source conversation: `019e2bee-b635-7c51-b569-bd31b3cca875`
Source session: private session, not published

This audit records the required one-by-one review of the 11 `request_user_input`
batches and their 33 binding answers before the code hygiene goal can be
closed. Public evidence stays in the repository; the private source session path
stays out of public docs.

Status vocabulary:

- `verified`: current repo evidence proves the decision is implemented or intentionally documented.
- `external-pending`: current repo evidence proves the program path exists, but the remaining step depends on a local external tool/runtime.

| # | Decision | Required answer | Review status | Evidence |
| --- | --- | --- | --- | --- |
| 1 | `strictness` | Fallar solo lo claro | verified | ADR 0016, `code-hygiene-check`, and report gates fail only clear mechanical debt. |
| 2 | `scope` | Clawix + ClawJS | verified | Mirrored artifacts exist in both repos; Clawix skill projection is checked from Clawix. |
| 3 | `enum_policy` | Conservar si son canon | verified | ADR 0016 keeps semantic enum members report-only unless canon rejects them. |
| 4 | `rollout_model` | Limpiar todo primero | verified | Initial cleanup is complete: zero blocking findings, zero actionable TODOs, zero unreferenced asset candidates. |
| 5 | `baseline_governance` | Motivo + caducidad | verified | Baseline entries require owner area, reason, reference, and 90-day expiry. |
| 6 | `autofix_policy` | Solo sugerir cambios | verified | Audit and cleanup skills forbid default destructive autofix. |
| 7 | `export_policy` | API publica se conserva | verified | Public/API contracts are retained or explicitly baselined; implementation-only exports were made private. |
| 8 | `unused_files` | Entrypoints configurados primero | verified | Knip config declares entry/project scope before file cleanup; file findings are zero for clear unused files. |
| 9 | `dependency_policy` | Normalizar por workspace | verified | Knip is pinned and dependency findings are normalized by workspace reports. |
| 10 | `swift_tooling` | Periphery calibrado | external-pending | Periphery 3.7.4 runner/report exists; local binary is missing and recorded separately. |
| 11 | `swift_public` | Conservar como contrato | verified | ADR 0016 preserves public Swift/API surfaces as contract unless explicitly retired. |
| 12 | `swiftui_dynamic` | Retener por patron | verified | ADR 0016 keeps SwiftUI and dynamic-use patterns report-only. |
| 13 | `semantic_placeholders` | Issue/backlog o ADR | verified | ADR 0016 requires future intent to be backed by backlog/ADR rather than dormant code. |
| 14 | `enum_members` | Report-only con canon | verified | Enum members are semantic report-only findings with canon references. |
| 15 | `todo_policy` | Si, con categorias | verified | Audit categorizes TODO/FIXME/HACK/XXX; actionable findings are currently zero. |
| 16 | `duplication_scope` | Codigo + assets obvios | verified | Knip covers code duplicate candidates and audit covers byte-identical obvious asset duplicates. |
| 17 | `duplicate_severity` | Report-only al inicio | verified | Duplicate assets remain report-only and do not authorize automatic removal. |
| 18 | `asset_policy` | Eliminar si no referenciado | verified | Unreferenced asset candidates are zero; generated/public asset surfaces are calibrated. |
| 19 | `test_code_policy` | Si, pero con fixtures protegidas | verified | Cleanup skill protects fixtures and tests while still allowing targeted test-code cleanup. |
| 20 | `generated_policy` | Manifest + marcadores | verified | Generated/vendor/public surfaces are documented and excluded from false cleanup candidates. |
| 21 | `docs_references` | Solo docs canonicas | verified | ADR 0016 and decision maps are the durable documentation anchors. |
| 22 | `cleanup_batching` | Por categoria y repo | verified | Cleanup skill requires one repo/category per batch with green checks before continuing. |
| 23 | `ci_gate` | Changed + release | verified | Changed lanes include hygiene checks; release lanes include hygiene and separate external requirements. |
| 24 | `report_format` | JSON + Markdown | verified | JSON and Markdown report pairs exist for audit, Knip, Periphery, and summary report. |
| 25 | `skill_shape` | Dos skills | verified | `code-hygiene-audit` and `code-hygiene-cleanup` exist. |
| 26 | `skill_location` | ClawJS y proyectada | verified | Canonical skills live in ClawJS and Clawix validates the projection. |
| 27 | `recurrence` | Cada campana + pre-release | verified | Ledger, skills, changed lane, and release lane encode campaign/pre-release use. |
| 28 | `ledger` | Si, compacto | verified | `docs/code-hygiene-ledger.md` records campaigns, exceptions, and validation evidence. |
| 29 | `expiry_window` | 90 dias | verified | Baseline default expiry is 90 days and checked programmatically. |
| 30 | `cleanup_safety` | Checks verdes por lote | verified | Cleanup evidence includes green self-tests, changed lanes, and targeted package tests. |
| 31 | `knip_install` | Dev dependency fija | verified | Knip 6.14.0 is pinned and checked as a dev dependency. |
| 32 | `periphery_install` | Tool versionada | external-pending | Periphery is versioned at 3.7.4; installation/calibration remains external pending until the binary is available. |
| 33 | `new_deps_policy` | Solo herramientas justificadas | verified | Tool registry documents Knip and Periphery with justified modes and non-destructive defaults. |

Current close condition: all decisions are implemented, documented, validated,
or explicitly blocked as external pending; no private session path is published.
