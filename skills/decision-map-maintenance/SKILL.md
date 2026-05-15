---
name: decision-map-maintenance
description: Keep decision maps as concise routers from decisions to canonical documents and validation guardrails.
keywords: [decision-map, docs, adr, routing, guardrails]
---

# decision-map-maintenance

Maintain the decision map as an index, not a duplicate source of truth.

## Procedure

1. Identify the durable decision being added, changed, or retired.
2. Update the canonical document first: Constitution, ADR, ownership doc, storage boundary, naming guide, catalog guide, or interface matrix.
3. Add or update the decision-map row with: decision, canonical document, and guardrail or validation.
4. Remove stale rows only when the canonical source has been retired or superseded.
5. Run docs alignment checks or add a guard if the map should enforce a snippet.

## Constraints

- Keep rows short and factual.
- Do not copy long ADR rationale into the map.
- Every row should help an agent choose what to read next.
