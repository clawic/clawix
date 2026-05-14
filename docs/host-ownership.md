# ClawJS, Claw.app, and Clawix ownership

This document defines the canonical ownership boundary for the ClawJS/Clawix
refactor. Data placement is defined in `docs/data-storage-boundary.md`.

## Ownership rule

ClawJS/Claw is the framework. It owns public contracts, v1 schemas, fixtures,
domain APIs, storage resolution, command routing, and any capability that
another application could reasonably call through the public CLI.

`claw` is the single public CLI. Public docs must not introduce a parallel
public `clawjs`, `clawix`, or `commander` command surface for new work.
Pre-public accidental commands are retired instead of carried as public
compatibility paths unless an ADR explicitly grants a temporary exception.

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
~/.claw
```

Canonical workspace data lives in:

```text
.claw/
```

Clawix host-operational state lives in:

```text
~/.clawix
```

Host GUI-only app state may use platform-native app data when it is not
framework state.

`.clawjs` is a retired pre-public path. New canonical workspace writes must use
`.claw/`, and framework or host code must not add new `.clawjs` readers or
migrations unless an ADR explicitly grants a bounded removal exception.

The detailed database and sidecar split is defined in
`docs/data-storage-boundary.md`. In short: user-facing structured records go to
`core.sqlite`; high-churn service/runtime/search/blob state uses named sidecars;
plaintext secrets never live in the main database.

## Host boundary

Sensitive actions never request macOS permissions from Node. The active signed
host performs those actions:

- `Claw.app` when using the standalone framework host.
- Clawix when using the embedded Clawix host.

The transport contract is the v1 host command contract. XPC is the final macOS
transport. Unix socket and HTTP transports are allowed for development, tests,
fixtures, and fallback behavior.

Secrets has an additional Mac V1 boundary because it handles vault unlock and
human reveal. Clawix bootstraps Secrets admin, signed-host, platform KEK, and
host-assertion material through anonymous stdin only. Sensitive Secrets
requests carry the signed-host token plus a per-request assertion issued by
the bundled Secrets-only macOS XPC service over method, path, timestamp, and
nonce. The XPC service verifies the caller code-signing identifier against the
enclosing Clawix bundle identifier before issuing assertions. Password unlock
uses password + Secret Key; local biometric unlock uses native LAContext
reauthentication plus the host `platformKeyWrap`, with password unlock as
fallback when biometrics are unavailable.

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
