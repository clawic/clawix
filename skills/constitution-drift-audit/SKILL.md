---
name: constitution-drift-audit
description: Audit code, docs, tests, and registries against the Constitution, ADRs, and decision map without making broad repairs. Use when checking whether the repository is drifting away from accepted architecture.
keywords: [constitution, adr, drift, audit, architecture, guardrails]
---

# constitution-drift-audit

Find drift between the implemented repository and the accepted ClawJS/Clawix canon.

## Procedure

1. Start with `docs/decision-map.md`; use it to identify the canonical docs and checks for the topic.
2. Read only the relevant Constitution sections, ADRs, docs, registries, and guard scripts.
3. Prefer `claw search <topic> --json` and `claw inspect ... --json` before source reads when the CLI is available.
4. Inspect implementation, docs, tests, generated manifests, and public instructions for contradiction, missing enforcement, or stale naming.
5. Classify each finding as `confirmed_drift`, `probable_drift`, `missing_guardrail`, `doc_only_drift`, or `needs_decision`.
6. Report a small repair batch for confirmed items and leave wider changes as explicit debt.

## Constraints

- Do not rewrite architecture while auditing.
- Do not treat a private workspace preference as public canon unless it has a redacted public source.
- If Constitution, ADR, and decision map disagree, record the conflict instead of guessing.
