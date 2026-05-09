---
id: macos.daemon-bridge
platform: macos
surface: settings
status: ready
priority: P0
tags:
  - smoke
  - regression
  - host
  - runtime
  - bridge
  - settings
intent: "Validate background bridge and Machines flows: daemon reachability, pairing, QR/code visibility, trust modes, allowed workspaces, unavailable states, and host/local distinction."
entrypoints:
  - settings-machines
  - bridge-status
  - pair-window
  - remote-job-card
variants:
  - daemon-unavailable
  - daemon-running
  - pairing-window
  - auth-failure
  - scoped-trust
  - full-trust
  - ask-per-task
  - allowed-workspace-add
  - remote-job-denied
required_state:
  app_mode: dummy
  data: fake daemon and machine states
  backend: fake or isolated local daemon
  window: Machines or pairing surface visible
safety:
  level: host_local
  default: fake daemon state
  requires_explicit_confirmation:
    - installing or mutating real login items
    - pairing a real device
    - granting real workspace trust
    - sending real remote tasks
execution_mode:
  hermetic: required for fake status and UI routing
  host: required for daemon reachability, localhost polling, pairing, trust, and workspace permissions
artifacts:
  - Machines page screenshot
  - pairing window screenshot with safe fixture payload
  - unavailable or denied state screenshot
assertions:
  - daemon state is explicit and not inferred from stale UI
  - pairing payload is visible only in safe fixture mode
  - trust mode and allowed workspaces are visible
  - real host validation is reported separately from hermetic validation
known_risks:
  - daemon and localhost state are host-dependent
  - pairing tokens are sensitive
  - workspace paths can expose private local paths
---

## Goal

Verify daemon bridge and Machines UI as host-dependent runtime surfaces while keeping fake status checks separate from real localhost validation.

## Invariants

- Daemon state must show unavailable, running, or error explicitly.
- Real pairing and workspace trust require confirmation.
- Pairing tokens and private paths must not leak into public artifacts.
- Host-dependent bugs cannot be closed with hermetic validation only.

## Setup

- Use fake daemon states for default validation.
- Use fixture machine names and synthetic workspace paths.
- Open Settings -> Machines or the pairing window.
- Do not pair a real device or grant real trust without confirmation.

## Entry Points

- Open Machines settings.
- Open bridge status from settings or runtime chrome.
- Open pairing QR/code window.
- Inspect remote job denied/allowed cards.

## Variant Matrix

| Dimension | Variants |
| --- | --- |
| Daemon | unavailable, running, auth failed, stale |
| Pairing | QR/code visible, failed auth, no endpoint |
| Trust | scoped, full trust, ask per task |
| Workspace | none, allowed fixture path, denied path |
| Validation | hermetic UI, real host localhost |

## Critical Cases

- `P0-daemon-unavailable`: unavailable state tells the user what to do.
- `P0-pairing-safe`: pairing UI renders with fixture payload only.
- `P1-trust-mode`: trust mode changes are visible and gated.
- `P1-host-validation`: real localhost validation is explicitly separated.

## Steps

1. Open Machines settings in fake daemon-unavailable state.
2. Confirm state, guidance, and disabled actions are clear.
3. Switch to fake daemon-running state.
4. Open pairing surface with fixture payload.
5. Inspect trust mode controls and allowed workspace list.
6. Inspect denied remote job guidance.
7. For host bugs, repeat against real localhost and record host result separately.

## Expected Results

- Machines page clearly communicates daemon state.
- Pairing surface is readable and safe in fixture mode.
- Trust and workspace controls expose current state.
- Denied remote jobs provide a concrete next step.

## Failure Signals

- UI says running when daemon is unreachable.
- Pairing token/path leaks into public artifacts.
- Trust change applies without confirmation where risky.
- Real host issue is reported fixed after hermetic-only validation.

## Evidence Checklist

| Check | Result |
| --- | --- |
| Hermetic daemon state checked | pass/fail/no-run |
| Pairing fixture checked | pass/fail/no-run |
| Trust/workspace state checked | pass/fail/no-run |
| Denied/error guidance checked | pass/fail/no-run |
| Real host validation separated when relevant | pass/fail/no-run |

## Screenshot Checklist

- Daemon unavailable state.
- Daemon running state.
- Pairing window with safe fixture payload.
- Trust mode controls.
- Denied remote job card.

## Notes for Future Automation

- Redact tokens and local paths before sharing artifacts.
- Host validation should use the same localhost mode the user reported.
- Keep daemon ownership assumptions aligned with runtime docs.
