# ADR 0001: Claw framework and host boundary

Status: Accepted

Date: 2026-05-13

## Context

Clawix started with application-local logic that now belongs in the reusable
framework. The target architecture is a framework that other applications can
call through a stable CLI, plus signed hosts that own native permissions and
human approvals. macOS permission prompts must come from the signed host
identity, never from Node.

## Decision

- ClawJS/Claw is the framework and owns contracts, schemas, fixtures, storage
  resolution, domain APIs, and the public command surface.
- `claw` is the single public CLI.
- `Claw.app` is the standalone signed macOS host.
- `ClawHostKit` is the embeddable host runtime used by Clawix and future hosts.
- Clawix embeds `ClawHostKit` and remains the human UI plus Clawix-signed host.
- A per-user host registry records available hosts and the active host.
- Framework global data lives in `~/Library/Application Support/Claw`.
- Canonical workspace data lives in `.claw/`.
- Host-local data lives in `~/Library/Application Support/<Host>`.
- `.clawjs` is legacy compatibility only.
- Sensitive permissions, approvals, grants, audit logs, LaunchAgents, Mach
  services, and native execution belong to the active signed host.
- Node code must not request macOS permissions directly.
- Codex data under `~/.codex` is an external read-only source. Mirroring and
  indexing are allowed; destructive migration, moves, rewrites, or broad chmods
  are not.
- `AGENTS.md` writes into Codex-owned sources require explicit, reversible,
  brokered opt-in.

## Consequences

Every migrated domain must work through both `claw` + `Claw.app` and Clawix +
embedded `ClawHostKit`. Clawix must remove duplicated canonical stores for
migrated domains and keep only UI projections, visual state, and host-specific
approvals. Public docs and templates must describe `Claw.app`, `ClawHostKit`,
and `claw`; legacy `commander`, `clawix`, or `.clawjs` references must be
clearly marked as compatibility content.
