# ClawJS, Claw.app, and Clawix ownership

This document defines the canonical ownership boundary for the ClawJS/Clawix
refactor.

## Ownership rule

ClawJS/Claw is the framework. It owns public contracts, v1 schemas, fixtures,
domain APIs, storage resolution, command routing, and any capability that
another application could reasonably call through the public CLI.

`claw` is the single public CLI. Public docs must not introduce a parallel
public `clawjs`, `clawix`, or `commander` command surface for new work. Legacy
commands may exist only as compatibility paths and must be labelled that way.

`Claw.app` is the standalone signed macOS host for the framework. It owns native
permission prompts, LaunchAgents, Mach services, host audit logs, grants,
approvals, and native adapters when running under the Claw identity.

Clawix is the human interface and an embedded signed host. It embeds
`ClawHostKit` and executes host work under the Clawix identity. Clawix owns
layout, sidebars, selection, visual pins and filters, shortcuts, QuickAsk,
overlays, previews, WebView UI, terminal UI, interface settings, and visual
caches. For migrated domains, Clawix must not keep a second canonical store.

## Storage roots

Framework global data lives in:

```text
~/Library/Application Support/Claw
```

Canonical workspace data lives in:

```text
.claw/
```

Host-local state lives in:

```text
~/Library/Application Support/<Host>
```

`.clawjs` is legacy compatibility only. New canonical workspace writes must use
`.claw/`. Reads from `.clawjs` are allowed only inside explicit migration,
compatibility, or removal code.

## Host boundary

Sensitive actions never request macOS permissions from Node. The active signed
host performs those actions:

- `Claw.app` when using the standalone framework host.
- Clawix when using the embedded Clawix host.

The transport contract is the v1 host command contract. XPC is the final macOS
transport. Unix socket and HTTP transports are allowed for development, tests,
fixtures, and fallback behavior.

Approvals, destructive grants, cost-bearing decisions, native secrets, and host
audit logs live in the active host. Framework APIs define the request and policy
shape; the signed host owns the native execution identity.

## Codex source safety

Codex is an external read-only source by default. `~/.codex` may be read,
mirrored, or indexed. It must not be deleted, moved, overwritten, recursively
chmodded, or used as a write target. `AGENTS.md` writes into Codex-owned sources
require an explicit, brokered, reversible opt-in.

## Acceptance per domain

A domain is done only when all of these are true:

- It works through `claw` plus `Claw.app`.
- It works inside Clawix through embedded `ClawHostKit`.
- It uses the same v1 contracts and fixtures.
- Grants and audit logs are host-specific.
- Clawix has no duplicated canonical store for that domain.
- Any sensitive permission path has real signed-host validation; dry-run counts
  only as partial validation.

## Public repository hygiene

Public repositories contain only safe placeholders for bundle ids, signing,
Team IDs, launch labels, Mach services, and host branding. Real signing
identities, secrets, private paths, release credentials, and maintainer-specific
configuration stay outside public repos.
