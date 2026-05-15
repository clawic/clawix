# ADR 0008: CLI just-in-time guidance, actor assertions, and resource registry

## Status

Accepted.

## Context

Clawix is the human app and embedded signed host for the Claw framework. Agents
operate primarily through the `claw` CLI, so the CLI is the right surface for
compact just-in-time instructions when a command attempt touches a server,
secret reference, project, workspace, or registered resource with special
guidance.

Clawix also has project/sidebar state that must survive folder renames and
moves. Path-derived identity is brittle for that job.

## Decision

ClawJS owns the `guidance` and `resources` framework domains. `guidance`
returns compact CLI hints through JSON `meta.guidance`; `resources` registers
explicit resources using opaque `res_*` ids and mutable locators. Actor
assertions classify caller identity when signed by an authorized host/runtime;
missing or invalid assertions become `unknown`, and env/flag hints are
`untrusted`.

Clawix consumes these contracts. Project and sidebar identity must migrate to
resource-backed `resourceId/projectId`, while `project_path` remains a mutable
locator. Clawix may show a minimal human surface for registered resources,
guidance, and status using existing visual patterns.

ClawJS ADR 0007 defines the operational discovery protocol: agents use `claw`
search and inspect surfaces before treating source files as the primary map for
non-trivial framework questions, with `claw collections` and `claw db` as the
agent-facing local data catalog.

## Rules

- Agents working in Clawix follow the ClawJS CLI discovery protocol whenever a
  change or question crosses into framework contracts, storage, data models,
  host integration, permissions, grants, approvals, or audit.
- Guidance never grants permissions and never bypasses signed-host approvals,
  grants, policies, audit, native permission prompts, or secret brokering.
- Compact hints do not contain long documents, plaintext secrets, or private
  full paths unless the user explicitly expands them.
- Resources are registered explicitly; Clawix must not trigger a global scan of
  the user's filesystem.
- Human-facing guidance is minimal by default.

## Consequences

Clawix can preserve user-visible project state across path changes and can
surface relevant guidance without flooding chat or CLI context. The signed
host boundary remains unchanged: native-sensitive work still belongs to
Clawix/Claw.app, not Node.
