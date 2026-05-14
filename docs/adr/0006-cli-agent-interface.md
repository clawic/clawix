# ADR 0006: CLI agent interface

## Status

Accepted.

## Context

Clawix is the human interface and embedded signed host for the same product
whose framework side is ClawJS. Agents should interact with reusable framework
logic through the public `claw` CLI, not through Clawix UI internals or
duplicated app-local stores. The ClawJS decision thread
`019e26ab-3d52-72b2-8653-08569db30681` and active goal
`019e26b6-1bbd-7d10-b68c-84d815b655e2` define the CLI as the complete,
discoverable, registry-driven, test-enforced agent interface.

This ADR mirrors the ClawJS decision so Clawix does not grow a competing
agent-facing command surface.

## Decision

`claw` is the canonical CLI for agents. Clawix consumes the framework,
embeds `ClawHostKit`, and may broker signed-host work under the Clawix
identity, but it does not define a parallel public framework CLI.

Any framework capability that an agent could need belongs in ClawJS and must be
represented through the ClawJS CLI registry, help, inspection, search, docs,
and tests. Clawix-specific UI behavior remains app-owned, but migrated domains
must remain available through `claw` plus the active signed host.

Clawix host surfaces that matter to framework inspection are exported as static
manifests compatible with the ClawJS inspection node contract. They may be fused
by `claw inspect --manifest <path>` or by generated workspace manifests. Codex
and other external sources stay read-only unless the user explicitly grants a
bounded, reversible opt-in.

Sensitive native permissions, destructive grants, approvals, audit logs,
secrets, and cost-bearing actions are brokered by the active signed host. Node
does not prompt for native permissions directly.

## Rules

- Public framework command work belongs in ClawJS `claw`, not a Clawix CLI.
- If Clawix adds or changes host-owned stable surfaces, it must keep the
  inspection manifest aligned with the ClawJS registry contract.
- Clawix and ClawJS Constitution copies stay synchronized when this principle
  changes.
- Physical signed-host validation gaps are recorded as `EXTERNAL PENDING`, not
  hidden as passing tests.

## Consequences

Agents get one framework command surface, while humans get Clawix as the native
interface. Clawix can expose and broker host capabilities, but the stable
agent-facing vocabulary, schemas, aliases, and discoverability remain owned by
ClawJS/Claw.
