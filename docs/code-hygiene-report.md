# Code Hygiene Report

Status: PARTIAL bootstrap.

- Blocking findings: 0 recorded in bootstrap report.
- Report-only findings: 52 in the latest local audit summary.
- Baselined findings: 0.
- Full cleanup campaign: pending.
- Report-only audit command: `node scripts/code-hygiene-audit.mjs`.
- Report-only Knip command: `node scripts/code-hygiene-knip.mjs`.
- Report-only Periphery command: `node scripts/code-hygiene-periphery.mjs`.
- Latest audit summary: 1,801 files scanned; 24 TODO/FIXME/HACK/XXX findings; 7 duplicate asset groups covering 14 files; 21 unreferenced asset candidates.
- Latest Knip summary: 28 files with issues; 209 total export/type findings after removing 4 unused web files, 2 unused dependencies, 2 unused package-script binaries, and calibrating Tailwind as a build dependency.
- Latest Periphery summary: external pending; 13 Swift packages discovered; Periphery 3.7.4 binary not installed on PATH.

This report is the human-readable pair for `docs/code-hygiene-report.json`.
