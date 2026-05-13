# Testing Matrix

This matrix is the working checklist for completing the testing architecture in
ADR 0003. A row is complete only when the listed lane has real coverage,
fixtures are synthetic, and any missing physical dependency is recorded in
`qa/scenarios`.
Coverage budgets live in `qa/coverage-budgets.json` and are enforced by the
public runner policy guard.

| Boundary | Primary lane | Release lane | Evidence |
| --- | --- | --- | --- |
| Swift logic packages | `fast` | `release` | SwiftPM package tests for small logic packages |
| Web surface | `fast` | `release` | Vitest under `web/tests` |
| Bridge protocol | `fast`, `integration` | `release` | `ClawixCore` round-trip tests and bridge fixture scripts |
| Daemon and local bridge | `integration`, `e2e` | `release` | Python/shell E2E fixtures under `macos/Helpers` and `macos/scripts` |
| macOS host/app | `host` | `release` | Private signed-host hook or `EXTERNAL PENDING` scenario |
| Android/iOS device | `device` | `release` | Gradle unit tests plus private simulator/device hook |
| Live integrations | `live` | opt-in only | Requires `CLAWIX_TEST_LIVE=1` and an approved live command |

## Completion Rules

- `changed` maps to `fast` until a changed-file selector is introduced.
- `release` must include public hygiene, policy, fast, local E2E, device state,
  and host state.
- `live` is never part of default release.
- `QUARANTINED` entries must live in `qa/quarantine.json` with owner, reason,
  repair path, and expiry.
- Expired quarantines fail the public runner.
- Test artifacts must stay under ignored paths such as `test-results/`,
  `artifacts/`, `coverage/`, `.tmp/`, platform build outputs, and scratch dirs.
