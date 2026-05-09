---
id: macos.memory
platform: macos
surface: memory
status: ready
priority: P2
tags:
  - regression
  - dummy
  - host
  - memory
  - services
intent: "Validate Memory navigation, capture list, detail pane, settings, injection state, graph launch path, and service availability messaging."
entrypoints:
  - memory-sidebar
  - memory-settings
  - memory-detail
  - graph-link
variants:
  - empty-memory
  - populated-list
  - detail-pane
  - edit-sheet
  - injection-enabled
  - injection-disabled
  - graph-unavailable
  - graph-local-open
required_state:
  app_mode: dummy
  data: fixture memory captures and settings
  backend: fake or local ClawJS memory service
  window: Memory surface visible
safety:
  level: safe_dummy
  default: fixture memory data
  requires_explicit_confirmation:
    - opening real memory graph with private data
    - writing real memory captures
execution_mode:
  hermetic: required for list/detail/settings state
  host: required for graph localhost and service availability checks
artifacts:
  - Memory list screenshot
  - detail or edit screenshot
  - settings/service state screenshot
assertions:
  - list and detail state match selected capture
  - empty state is explicit
  - injection setting is visible
  - graph/service availability is clear
known_risks:
  - real memory data can be private
  - graph runs outside the main app surface
  - service state may be daemon-owned
---

## Goal

Verify Memory as a user-facing knowledge surface while keeping default validation on fixture captures and explicit service state.

## Invariants

- Fixture memory content must be non-sensitive.
- Empty and populated states must both be legible.
- Selecting a capture must update the detail pane.
- Graph launch must be local-only by default.

## Setup

- Launch with fixture memory data or an empty fixture state.
- Open the Memory surface and Memory settings.
- Use fake or isolated local service state.
- Do not open real private memory graphs without confirmation.

## Entry Points

- Open Memory from the sidebar.
- Open Memory settings.
- Select a capture row.
- Use the graph launch affordance.

## Variant Matrix

| Dimension | Variants |
| --- | --- |
| Data | empty, populated fixture |
| Selection | none, capture selected, edit sheet |
| Settings | injection enabled, injection disabled |
| Service | unavailable, local running, graph link |

## Critical Cases

- `P2-memory-list`: empty and populated fixture states render clearly.
- `P2-memory-detail`: selecting a capture updates the detail pane.
- `P2-injection-setting`: injection state is visible and reversible.
- `P2-graph-state`: graph link shows local availability or unavailable state.

## Steps

1. Open Memory.
2. Verify empty or populated fixture state.
3. Select a capture and inspect detail pane.
4. Open edit or settings surface without saving real data.
5. Toggle fixture injection state and confirm visible update.
6. Inspect graph link/service state without opening private data.

## Expected Results

- Memory list and detail are synchronized.
- Empty state is explicit.
- Settings show injection and service state.
- Graph availability is clear and local.

## Failure Signals

- Detail pane does not match selected row.
- Empty state is blank.
- Real private memory content appears.
- Graph opens a real private page without confirmation.
- Service state pretends success when unavailable.

## Evidence Checklist

| Check | Result |
| --- | --- |
| Empty/populated state checked | pass/fail/no-run |
| Selection/detail sync checked | pass/fail/no-run |
| Settings state checked | pass/fail/no-run |
| Graph/service state classified | pass/fail/no-run |
| Required screenshots captured | pass/fail/no-run |

## Screenshot Checklist

- Memory list.
- Memory detail pane.
- Empty state when applicable.
- Memory settings.
- Graph unavailable or local state.

## Notes for Future Automation

- Use fixture capture IDs for deterministic selection.
- Do not validate graph content unless it is fixture-backed.
- Treat service state as host-dependent.
