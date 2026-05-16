---
name: surface-route-work
description: Work from a registered surface or transverse route by inspecting nodes, neighbors, edges, contracts, owners, tests, and gaps before editing.
keywords: [surface, route, graph, relay, bridge, runtime, ownership]
---

# surface-route-work

Use this when a task touches connected ClawJS/Clawix surfaces, runtime-critical
paths, bridge/Relay behavior, CLI/MCP/API contracts, storage ownership,
permissions, grants, approvals, audit, or agent chat routes.

## Procedure

1. Run `claw search <topic> --json` first. If `claw` is not on PATH, use the
   local repo binary (`node packages/clawjs/bin/claw.mjs`) and note the fallback.
2. Resolve the working node or route with:
   - `claw inspect show <surface> --json`
   - `claw inspect neighbors <surface> --json`
   - `claw inspect routes --json`
   - `claw inspect route <route-id> --json`
3. Read the ADRs, docs, tests, and source files named by the inspection output.
4. Choose the work mode explicitly:
   - surface-first: start at one node and inspect adjacent ingress/egress;
   - route-first: follow every explicit step in the registered route.
5. Keep ownership intact. Framework contracts, schemas, storage, SDK, CLI, MCP,
   service APIs, and Relay contracts stay in ClawJS/Claw. Clawix owns native UI,
   host identity, visual state, and host operational state.
6. Update the registry graph when a stable node, edge, route, transport,
   contract, owner, validation, or gap changes.
7. Validate with the route's listed tests or add a focused fixture/E2E when the
   route did not have one. Mark unavailable physical/provider validation as
   `EXTERNAL PENDING`, separate from defects.

## Constraints

- Do not rely on a hand-drawn diagram as source of truth.
- Do not touch adjacent owners just because they are connected; inspect the
  edge type and contract first.
- Relay is a critical remote-safe surface, not the canonical local API.
- A route is incomplete if any step lacks a registered node, contract,
  validation, or explicit gap.
