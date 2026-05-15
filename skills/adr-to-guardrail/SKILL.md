---
name: adr-to-guardrail
description: Turn a new or changed ADR into implemented behavior, routing docs, tests, and guardrails rather than leaving it as standalone prose.
keywords: [adr, guardrail, decision-map, docs, tests, architecture]
---

# adr-to-guardrail

Make an ADR operational.

## Procedure

1. Read the ADR template and the closest accepted ADRs before drafting or changing a decision.
2. State the decision in implementation-neutral terms and fill surface parity: human surface, programmatic surface, persistence, gaps, and validation.
3. Update `docs/decision-map.md` or the equivalent project router with the new decision and its guardrail.
4. Update affected docs, registries, manifests, CLI inspection/search output, and tests so agents can discover and enforce the decision.
5. Refactor implementation only as far as needed to make the ADR true for the intended batch.
6. Record pending guardrails or migrations explicitly when full enforcement cannot land now.

## Constraints

- An ADR is incomplete if it is not linked from the relevant routing surface.
- Do not accept "doc only" for a decision that changes stable behavior.
- Do not preserve accidental pre-public legacy unless an ADR explicitly grants a bounded exception.
