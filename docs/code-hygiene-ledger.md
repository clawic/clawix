# Code Hygiene Ledger

This ledger records code hygiene campaigns, exceptions, and validation evidence.

Source conversation: `019e2bee-b635-7c51-b569-bd31b3cca875`
Source session: private session, not published

## 2026-05-17 - Program bootstrap

- Status: PARTIAL
- Scope: Clawix + ClawJS.
- Work recorded: policy, baseline, report format, decision checklist, and skills/check scaffolding.
- Cleanup campaign: pending.
- Blocking gate activation: pending until existing blocking debt is cleaned.
- Validation evidence: code hygiene check/self-test, audit self-test, and skill projection check passed locally.

## 2026-05-17 - Report-only audit expansion

- Status: PARTIAL
- Scope: TODO/FIXME/HACK/XXX, byte-identical duplicate assets, and unreferenced asset candidates.
- Mode: report-only; no automatic removal and no blocking gate yet.
- Latest summary: 1,801 files scanned; 24 TODO/FIXME/HACK/XXX findings; 7 duplicate asset groups covering 14 files; 21 unreferenced asset candidates.
- Cleanup campaign: pending classification/removal by repo and category.

## 2026-05-17 - Knip report-only calibration

- Status: PARTIAL
- Tool: Knip 6.14.0 through `scripts/code-hygiene-knip.mjs`.
- Config: `web/knip.json`.
- Latest summary: 28 files with issues; 209 total export/type findings after the first web cleanup lot removed 4 unused files, 2 unused dependencies, and 2 unused package-script binaries; Tailwind was retained as calibrated build dependency.
- Mode: report-only; cleanup and baselining pending before blocking gate activation.

## 2026-05-17 - Periphery report-only setup

- Status: EXTERNAL PENDING
- Tool: Periphery 3.7.4 through `scripts/code-hygiene-periphery.mjs`.
- Latest summary: 13 Swift packages discovered; local Periphery binary not installed on PATH, so no Swift findings have been calibrated yet.
- Retention rules: public API, SwiftUI previews, Objective-C-accessible declarations, and Codable properties retained by default.
- Mode: report-only; no automatic removal and no blocking gate yet.
