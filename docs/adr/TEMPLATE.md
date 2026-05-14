# ADR NNNN: Title

Status: Proposed

Date: YYYY-MM-DD

## Context

Describe the decision pressure, existing behavior, and constraints.

## Decision

State the decision in implementation-neutral terms.

## Surface Parity

Every accepted ADR that adds or changes an important capability must answer:

- **Human surface**: which UI, human workflow, or review/approval surface lets a
  person discover, configure, consume, or operate the capability?
- **Programmatic surface**: which SDK, CLI, service API, MCP, or Relay surface
  lets agents, scripts, apps, or other programs consume it?
- **Persistence**: which filesystem, SQLite, schema, or registry contract makes
  the user's accumulated value portable?
- **Gaps**: classify missing surfaces as `required`, `optional`, `local-only`,
  `remote-safe`, `blocked`, or `not applicable`.
- **Validation**: name at least one human-path validation and one programmatic
  validation, or record `PARTIAL` / `EXTERNAL PENDING` with the missing physical
  dependency.

## Consequences

List the practical tradeoffs, migration impact, and follow-up enforcement.
