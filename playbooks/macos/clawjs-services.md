---
id: macos.claw-services
platform: macos
surface: settings
status: ready
priority: P1
tags:
  - regression
  - host
  - runtime
  - services
  - settings
intent: "Validate ClawJS service state, daemon-owned service reporting, logs, probes, blocked/crashed states, and navigation into service-backed Memory, Drive, and Database surfaces."
entrypoints:
  - settings-clawjs
  - service-row
  - log-action
  - health-probe
variants:
  - idle
  - blocked
  - starting
  - running
  - running-from-daemon
  - crashed
  - daemon-unavailable
  - probe-success
  - probe-failure
required_state:
  app_mode: dummy
  data: fake ClawJS service states
  backend: fake service manager or isolated local services
  window: ClawJS settings visible
safety:
  level: host_local
  default: fake service states
  requires_explicit_confirmation:
    - starting real local services
    - opening real logs with private paths
    - probing production-backed services
execution_mode:
  hermetic: required for fake service-state UI
  host: required for real process, port, log, and probe validation
artifacts:
  - ClawJS settings screenshot
  - service state screenshot
  - probe result screenshot
assertions:
  - every service row shows explicit state
  - daemon-owned state is distinct from GUI-owned state
  - blocked/crashed/unavailable states explain next step
  - probes do not hit production services by default
known_risks:
  - local ports and logs are host-dependent
  - service names may expose local setup
  - daemon-owned runtime must not be duplicated by GUI-owned services
---

## Goal

Verify ClawJS service visibility and diagnostics without starting real services or probing production-backed endpoints by default.

## Invariants

- Service state must be explicit for idle, starting, running, blocked, crashed, and daemon-unavailable.
- Running from daemon must be visually distinct.
- Real service starts, logs, and probes require confirmation or isolated host setup.
- No GUI-owned duplicate service should be implied when daemon-owned mode is active.

## Setup

- Open Settings -> ClawJS with fake service states.
- Use fixture service names and ports.
- Keep real service start/probe paths as no-run unless confirmed.

## Entry Points

- Open ClawJS settings.
- Inspect each service row.
- Open logs or status JSON where safe.
- Run a fake health probe.

## Variant Matrix

| Dimension | Variants |
| --- | --- |
| State | idle, blocked, starting, ready, ready from daemon, crashed, daemon unavailable |
| Action | inspect, log, status JSON, health probe |
| Service | memory, drive, database, vault-backed service |
| Validation | fake UI state, isolated host process |

## Critical Cases

- `P1-state-spectrum`: each service state renders with clear label/color/guidance.
- `P1-daemon-owned`: running-from-daemon is distinct and does not imply duplicate GUI ownership.
- `P1-probe-result`: fake probe success and failure are visible.
- `P2-log-action`: log/status action does not leak private paths by default.

## Steps

1. Open ClawJS settings.
2. Render fake idle, starting, running, blocked, crashed, and daemon-unavailable states.
3. Confirm each row has readable status and next step.
4. Render running-from-daemon state and verify it is distinct.
5. Run or show fake probe success and failure.
6. Open log/status action only with safe fixture output.

## Expected Results

- Status rows are readable and distinct.
- Daemon-owned state is explicit.
- Probe results are visible and reversible.
- Unsafe real host actions are blocked or marked no-run.

## Failure Signals

- State label is missing or stale.
- Running-from-daemon looks identical to GUI-owned running.
- Crash/block state provides no next step.
- Probe hits a real production-backed service.
- Logs reveal private local paths in shared artifacts.

## Evidence Checklist

| Check | Result |
| --- | --- |
| State spectrum checked | pass/fail/no-run |
| Daemon-owned state checked | pass/fail/no-run |
| Probe success/failure checked | pass/fail/no-run |
| Log/status safety checked | pass/fail/no-run |
| Host validation separated when relevant | pass/fail/no-run |

## Screenshot Checklist

- ClawJS settings overview.
- Running-from-daemon state.
- Blocked or crashed state.
- Daemon-unavailable state.
- Probe result.

## Notes for Future Automation

- Treat process and port checks as host-dependent.
- Do not start real services in default validation.
- Service-backed feature playbooks should reference this one when failures are runtime-state related.
