---
name: code-hygiene-audit
description: Audit ClawJS/Clawix code hygiene without editing code, producing categorized findings, baseline status, and validation evidence.
keywords: [code-hygiene, dead-code, unused, audit, baseline, cleanup]
---

# code-hygiene-audit

Use this skill for recurring code hygiene audits, pre-release hygiene review, or cleanup campaign preparation.

## Procedure

1. Read the code hygiene ADR, decision map entry, decision checklist, baseline, ledger, and latest JSON/Markdown report.
2. Confirm the source conversation id `019e2bee-b635-7c51-b569-bd31b3cca875` and inspect every recorded decision before classifying findings.
3. Run the non-mutating hygiene checks and scanners that are available: local unused checks, Knip for TS/JS, Periphery report-only for Swift, asset reference scans, TODO scans, and duplicate grouping.
4. Classify findings as `FAIL`, `REPORT_ONLY`, `BASELINED`, or `EXTERNAL_PENDING`. Keep enum members, Swift dynamic-use findings, public APIs, and duplicates report-only unless a canon review proves removal is safe.
5. Update or propose updates to the JSON/Markdown report and ledger; do not edit source code.

## Constraints

- Do not delete or rewrite code while auditing.
- Do not treat a public/canonical surface as dead because it lacks an internal consumer.
- Do not use `EXTERNAL_PENDING` for ordinary bugs or missing local implementation.
