# ADR 0007: Dual human and programmatic surfaces

Status: Accepted

Date: 2026-05-14

## Context

ClawJS persists the user's accumulated value: data, sessions, skills,
decisions, secrets references, connections, workflows, validations, and audit
records. That value must outlive any single model, provider, session, app, or
device. If a capability is reachable only through one interface, the user is
locked into that interface even when the underlying data remains portable.

The project already has several surfaces: Clawix UI, the `@clawjs/claw` SDK,
the `claw` CLI, service HTTP/event APIs, MCP servers, Relay, and open
filesystem/SQLite persistence. This ADR defines their roles and makes surface
parity part of capability completeness.

## Decision

Important capabilities must have both:

- a human surface, normally Clawix or another UI built on the SDK; and
- a programmatic surface, normally SDK, CLI, service API, MCP, or Relay.

The surfaces have distinct roles:

- **SDK**: canonical build-on-top surface for applications, hosts, services,
  and third-party products. Clawix is one reference consumer, not the only
  valid UI.
- **CLI**: shell-native surface for agents, humans, scripts, automation,
  inspection, validation, and local operations.
- **Service API**: HTTP/event/process contract for cross-language,
  cross-process, native, web, and device clients. "API" in ClawJS docs means
  this service contract unless explicitly qualified.
- **MCP**: first-class model-native surface for LLM hosts. ClawJS MCP servers
  expose tools for model-invoked actions, resources for context/data, and
  prompts for user-invoked workflows. MCP derives from the same framework
  contracts as the SDK and service APIs; it is not a separate source of truth.
- **Relay**: remote access and control plane. Relay carries selected
  remote-safe service APIs outside the local machine, but it is not the whole
  API concept.
- **Filesystem/SQLite**: durable persistence and portability contract. It must
  be readable without ClawJS, but normal mutations should prefer SDK, CLI,
  service API, MCP, or Relay so validation, permissions, audit, and events run.
- **UI**: human-facing surface for review, action, configuration, approval,
  validation status, recovery, and consumption.

Surface gaps use these classifications:

- `required`: must be added before the capability is complete.
- `optional`: useful but not required for v1 completeness.
- `local-only`: valid locally and intentionally not remote-safe.
- `remote-safe`: valid to expose through Relay or remote service API.
- `blocked`: desirable but blocked by security, physical dependency, provider
  constraints, cost, or missing host support.
- `not applicable`: the surface does not make sense for the capability.

Every new stable capability, ADR, public CLI group, service route, MCP tool,
SDK namespace, or durable user-facing data domain must declare its surface
coverage. If a capability is intentionally one-sided, the ADR must state why
and classify the missing surface.

## Enforcement

- `docs/interface-matrix.md` is the human-readable coverage matrix.
- The stable surface registry records which human and programmatic surfaces
  expose registered capabilities.
- `claw inspect` renders surface coverage alongside CLI, API, protocol,
  schema, event, persistence, and ID registry nodes.
- ADRs include a surface-parity section before acceptance.
- Tests and validation cover at least one human path and one programmatic path
  for important capabilities. Where a physical or external dependency prevents
  full coverage, the report uses `PARTIAL`, `EXTERNAL PENDING`, `blocked`, or
  `not applicable`.

## Consequences

UI-only features are incomplete until a programmatic surface exists or an ADR
records the exception. Programmatic-only features are incomplete until a human
can discover, review, configure, or consume them through an appropriate UI or
documented human workflow. Service APIs and MCP tools must not fork business
logic from the SDK; they should adapt the same domain contracts. Relay exposes
only the remote-safe subset and must not become the canonical local API.
