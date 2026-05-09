---
id: macos.local-models
platform: macos
surface: settings
status: ready
priority: P2
tags:
  - regression
  - host
  - settings
  - models
  - services
intent: "Validate Local models settings, runtime availability, install/start prompts, catalog, pull progress, default selection, unload, delete confirmation, and error states."
entrypoints:
  - settings-local-models
  - composer-model-picker
  - catalog-sheet
  - manual-model-entry
variants:
  - runtime-unavailable
  - install-prompt
  - service-starting
  - installed-model-list
  - catalog-open
  - pull-progress
  - default-model
  - unload-model
  - delete-confirmation
  - download-error
required_state:
  app_mode: dummy
  data: fixture model catalog and service states
  backend: fake local models service unless host validation is explicit
  window: Local models settings visible
safety:
  level: host_local
  default: fake service state
  requires_explicit_confirmation:
    - downloading a real model
    - installing or starting a real daemon
    - deleting real local model files
execution_mode:
  hermetic: required for settings and fake service states
  host: required for real daemon, disk, download, and model picker integration
artifacts:
  - Local models settings screenshot
  - catalog or pull state screenshot
  - delete/error confirmation screenshot
assertions:
  - runtime state is explicit
  - model list and default state are visible
  - destructive/download actions stop or show progress clearly
  - composer picker reflects available local model only in validated mode
known_risks:
  - downloads can be large and costly in time/disk
  - daemon state is host-dependent
  - installed model names may reveal local setup
---

## Goal

Verify Local models as a settings and composer capability without downloading, deleting, or starting real services by default.

## Invariants

- Runtime availability must be explicit.
- Real downloads and deletes require confirmation.
- Fake model state is acceptable for default visual validation.
- Composer model picker integration is host-dependent unless fixture-backed.

## Setup

- Open Settings -> Local models.
- Use fake service states for unavailable, starting, running, list, progress, and error.
- Do not start real daemons or downloads without confirmation.

## Entry Points

- Open Local models settings.
- Open model catalog.
- Enter a model name manually.
- Open composer model picker where local models are expected.

## Variant Matrix

| Dimension | Variants |
| --- | --- |
| Runtime | unavailable, starting, running, error |
| Models | none, installed list, default selected |
| Action | catalog, pull, unload, delete, dismiss error |
| Integration | settings only, composer picker |

## Critical Cases

- `P2-runtime-state`: unavailable/starting/running/error states are readable.
- `P2-catalog-no-download`: catalog opens without pulling a real model.
- `P2-delete-confirmation`: delete stops at confirmation.
- `P2-composer-picker`: local model option appears only when validated.

## Steps

1. Open Local models settings.
2. Confirm runtime state is visible.
3. Open catalog and cancel without download.
4. Show fake installed model list and select a default.
5. Show fake pull progress or error state.
6. Open unload/delete paths and stop before destructive action.
7. Optionally validate composer picker in host mode.

## Expected Results

- The page makes service state and next action clear.
- Catalog and manual entry are visible.
- Download/progress/error states are distinguishable.
- Delete and destructive actions are gated.

## Failure Signals

- Runtime state is blank or stale.
- A real download starts without confirmation.
- Delete executes in default mode.
- Composer shows local model state that was not validated.
- Error state cannot be dismissed or understood.

## Evidence Checklist

| Check | Result |
| --- | --- |
| Runtime state checked | pass/fail/no-run |
| Catalog/manual entry checked | pass/fail/no-run |
| Progress/error state checked | pass/fail/no-run |
| Destructive actions stopped at confirmation | pass/fail/no-run |
| Composer integration checked or marked no-run | pass/fail/no-run |

## Screenshot Checklist

- Local models settings.
- Catalog sheet.
- Installed model list or empty state.
- Progress or error state.
- Delete confirmation.

## Notes for Future Automation

- Model service checks must distinguish fake state from real host state.
- Never pull a real model in default validation.
- Avoid screenshots that reveal local model inventory unless approved.
