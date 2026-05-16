---
name: code-hygiene-cleanup
description: Execute a bounded ClawJS/Clawix code hygiene cleanup campaign from an audit report, one category and repo at a time.
keywords: [code-hygiene, cleanup, dead-code, unused, refactor, validation]
---

# code-hygiene-cleanup

Use this skill when the user explicitly asks to clean code hygiene findings or continue the code hygiene goal.

## Procedure

1. Start from a current `code-hygiene-audit` report and the 33-decision checklist.
2. Choose exactly one repo and one category for the batch: dependencies, orphan files, private exports/types, tests/fixtures, assets/SVG, Swift report-only review, TODOs, or duplicates.
3. Re-run or inspect scanner output after entrypoint calibration. For Knip, separate clear private debt from public API/protocol/UI/icon barrels and framework route/config false positives.
4. Preserve public API, package entrypoints, CLI/router/registry/protocol surfaces, canonical docs, fixtures, stable registries, and compatibility names unless an explicit removal decision exists.
5. Make the smallest cleanup that removes proven debt. Future intent must move to issue/backlog/ADR rather than dormant code.
6. When retaining a finding, add or update a baseline entry with reason, owner area, reference, and expiry; never hide a real bug behind `EXTERNAL_PENDING`.
7. Run the relevant checks for the batch before moving on. Record validation and baseline removals/additions in the ledger.

## Constraints

- Autofix is suggestion-only by default; do not run destructive fixes or remove files without explicit task scope.
- Keep enum members, Swift dynamic-use findings, and duplicates report-only until reviewed.
- Do not batch unrelated cleanup categories together.
- Do not modify unrelated dirty work while cleaning; record it separately if it affects validation.
