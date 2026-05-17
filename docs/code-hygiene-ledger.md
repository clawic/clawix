# Code Hygiene Ledger

This ledger records code hygiene campaigns, exceptions, and validation evidence.

Source conversation: `019e2bee-b635-7c51-b569-bd31b3cca875`
Source session: private session, not published

## 2026-05-17 - Program bootstrap

- Status: ACTIVE
- Scope: Clawix + ClawJS.
- Work recorded: policy, baseline, report format, decision checklist, and skills/check scaffolding.
- Initial cleanup completed: zero blocking findings, zero actionable TODO/FIXME/HACK/XXX findings, and zero unreferenced asset candidates.
- Blocking gate activation: active for clear mechanical debt through changed/release hygiene checks; semantic duplicates and external Swift calibration remain report-only or external pending.
- Validation evidence: code hygiene check/self-test, audit self-test, and skill projection check passed locally.

## 2026-05-17 - Report-only audit expansion

- Status: ACTIVE
- Scope: TODO/FIXME/HACK/XXX, byte-identical duplicate assets, and unreferenced asset candidates.
- Mode: report-only for duplicate assets; actionable TODO/FIXME/HACK/XXX and unreferenced asset candidates are kept at zero by the hygiene check.
- Latest summary: 1,909 files scanned; 0 TODO/FIXME/HACK/XXX findings; 6 duplicate asset groups covering 12 files; 0 unreferenced asset candidates.
- Calibration: generated bundles and public/platform asset surfaces are excluded from actionable cleanup candidates.

## 2026-05-17 - Knip report-only calibration

- Status: PARTIAL
- Tool: Knip 6.14.0 through `scripts/code-hygiene-knip.mjs`.
- Config: `web/knip.json`.
- Latest summary: 23 files with issues; 197 export/type findings after two web cleanup lots removed unused files, dependencies, package-script binaries, and clear private export/type findings; Tailwind was retained as calibrated build dependency.
- Baseline: remaining Clawix web export/type findings are covered by 3 entries with owner, reason, reference, and 2026-08-15 expiry.
- Mode: report-only for semantic export/API findings; clear file/dependency findings are kept at zero.

## 2026-05-17 - Periphery report-only setup

- Status: EXTERNAL PENDING
- Tool: Periphery 3.7.4 through `scripts/code-hygiene-periphery.mjs`.
- Latest summary: 13 Swift packages discovered; local Periphery binary not installed on PATH, so no Swift findings have been calibrated yet.
- Retention rules: public API, SwiftUI previews, Objective-C-accessible declarations, and Codable properties retained by default.
- Mode: report-only until the pinned external binary is installed.
