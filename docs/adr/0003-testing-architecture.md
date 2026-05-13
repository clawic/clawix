# ADR 0003: Testing architecture

Status: Accepted

Date: 2026-05-14

## Context

ClawJS/Claw and Clawix have broad test coverage, but the suites grew by
tooling, package, and incident instead of by product boundary. That makes it
unclear which gate protects a change, when a signed host is required, and which
checks are safe to run automatically. The reference project OpenClaw is useful
for its lane-based testing model, changed gates, scenario documents, and
agent-friendly runner conventions, but ClawJS and Clawix keep their own stack
choices.

## Decision

- ClawJS and Clawix share one testing policy and keep synchronized ADRs.
- Test ownership follows real boundaries: framework, protocol, CLI, daemon,
  bridge, host, UI, device, and live integrations.
- The official lane names are `fast`, `changed`, `integration`, `e2e`, `host`,
  `device`, `live`, and `release`.
- A normal blocking check uses the `changed` lane. Release uses the `release`
  lane.
- `live` tests are strict opt-in and must never spend money, send real prompts,
  mutate production data, or contact real services unless the operator sets an
  explicit environment variable for that lane.
- Real signed-host validation is required only for host-dependent behavior:
  native permissions, app identity, approvals, grants, TCC, LaunchAgents, local
  helpers, app windows, and bridge ownership.
- Non-physical or unavailable validations are recorded as `EXTERNAL PENDING`
  only when a hermetic/local test and a QA scenario cover the expected contract.
- Test outcomes use these states: `PASS`, `FAIL`, `PARTIAL`, `EXTERNAL PENDING`,
  and `QUARANTINED`.
- Quarantined tests require an owner, reason, expiry, and repair path. Expired
  quarantines fail the relevant gate.
- Coverage is budgeted per lane and boundary, not by a single global 100%
  target.
- Secrets and privacy hygiene are mandatory gates. Test artifacts are ignored
  or redacted by default.
- `qa/scenarios` is the canonical home for agentic/manual/live validation
  scenarios that cannot be fully automated.

## ClawJS runner policy

- ClawJS uses Vitest for TypeScript unit and integration tests.
- Playwright remains the browser and web workflow E2E runner.
- The public command surface is `npm run test:<lane>`.
- Root package tests may remain colocated with source when they are pure unit
  tests. Cross-package, protocol, CLI, storage, daemon, and browser tests live
  under lane-specific test roots.
- The framework owns canonical fixtures for contracts, schemas, CLI behavior,
  storage resolution, and domain APIs.

## Clawix runner policy

- Clawix exposes a public-safe `scripts/test.sh` lane runner.
- SwiftPM/XCTest remains the runner for Swift logic packages and macOS logic.
- Python and shell scripts remain valid for daemon, bridge, and host fixture
  tests.
- Gradle owns Android JVM/device tests.
- Vitest is limited to the web surface.
- Private signing identity, Team ID, bundle id, local paths, and secrets are not
  committed or printed by the public runner. Private launchers may be used only
  through environment-mediated hooks outside the public repo.

## Domain completeness

A domain is considered fully tested only when:

- the right real boundary is covered;
- hermetic/local tests protect the normal changed gate;
- public docs and fixtures explain the behavior;
- non-automatable checks have QA scenarios;
- any physical dependency is explicitly marked `EXTERNAL PENDING`; and
- no expired quarantine remains.

## Consequences

Adding behavior without tests means adding the missing lane coverage in the
same change. Adding a new public surface requires a CLI/API or UI test, a
fixture when data is involved, and release-lane coverage. Adding host behavior
requires either a real signed-host scenario or an `EXTERNAL PENDING` record with
clear missing physical prerequisites.
