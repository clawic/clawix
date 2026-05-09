---
id: macos.secrets
platform: macos
surface: secrets
status: ready
priority: P0
tags:
  - smoke
  - regression
  - sensitive
  - confirmation
  - secrets
  - settings
intent: "Validate Secrets vault navigation, locked/unlocked states, onboarding, import/export previews, governance, audit, grants, and redaction rules without exposing real secret values."
entrypoints:
  - secrets-sidebar
  - settings-secrets
  - locked-vault
  - onboarding
variants:
  - locked
  - onboarding
  - fake-unlocked
  - import-preview
  - export-confirmation
  - governance-edit
  - audit-view
  - grants-view
  - trash-view
required_state:
  app_mode: dummy
  data: fake vault metadata only
  backend: fixture or fake vault
  window: Secrets surface visible
safety:
  level: confirmation_required
  default: fake metadata only
  requires_explicit_confirmation:
    - creating real secrets
    - importing real secrets
    - exporting secrets
    - viewing or copying secret values
  forbidden_without_confirmation:
    - revealing literal secret values
execution_mode:
  hermetic: required for fake locked/onboarding/unlocked states
  host: required only for installed Secrets Vault integration metadata, never value inspection
artifacts:
  - locked or onboarding screenshot
  - fake unlocked screenshot
  - confirmation screenshot for import/export/delete flows
assertions:
  - secret values are never visible
  - locked/onboarding/unlocked states are distinct
  - sensitive actions stop at confirmation
  - governance and audit state use metadata only
known_risks:
  - real vault state is host-dependent
  - screenshots can leak names or metadata if not fixture-backed
  - import/export flows are sensitive even in preview
---

## Goal

Verify the Secrets UI and safety gates while treating real secret values as forbidden content.

## Invariants

- Literal secret values must never appear in UI, logs, screenshots, or copied text.
- Real import/export/create/view-value actions require confirmation.
- Fake metadata is acceptable for visual validation.
- Locked, onboarding, and unlocked states must be visually distinct.

## Setup

- Use dummy mode with fake vault metadata.
- Do not connect to real 1Password, Keychain, or Secrets Vault values.
- Prepare fake records with non-sensitive names and hosts only.
- Stop at all confirmations.

## Entry Points

- Open Secrets from the main sidebar.
- Open Secrets settings.
- Start from locked vault state.
- Start from onboarding state.

## Variant Matrix

| Dimension | Variants |
| --- | --- |
| Vault state | locked, onboarding, fake unlocked |
| Action | import preview, export confirmation, governance, grants, audit, trash |
| Data | fake metadata, real metadata only with confirmation |
| Risk | safe fixture, confirmation required, forbidden value reveal |

## Critical Cases

- `P0-redaction`: no secret value is visible anywhere.
- `P0-confirmation`: import/export/delete/value actions stop before execution.
- `P1-state-navigation`: locked, onboarding, and fake unlocked states render.
- `P1-governance-audit`: permissions and audit views use metadata only.

## Steps

1. Open Secrets in fake locked or onboarding state.
2. Confirm no secret values are visible.
3. Move to fake unlocked state with fixture metadata.
4. Open detail, governance, grants, audit, and trash surfaces.
5. Open import/export/delete actions and stop at confirmation.
6. Confirm all screenshots use fake metadata only.

## Expected Results

- The surface is usable without real secrets.
- Sensitive actions are gated.
- Metadata views are readable without exposing values.
- Confirmation dialogs clearly communicate the risky operation.

## Failure Signals

- A secret value is visible or copied.
- Import/export/delete executes in default mode.
- Locked state can be bypassed silently.
- Real vault content appears in a screenshot.
- Confirmation wording is missing or ambiguous.

## Evidence Checklist

| Check | Result |
| --- | --- |
| Fake metadata source confirmed | pass/fail/no-run |
| Redaction checked | pass/fail/no-run |
| Locked/onboarding/unlocked state checked | pass/fail/no-run |
| Sensitive confirmations checked | pass/fail/no-run |
| Screenshots reviewed for leaks | pass/fail/no-run |

## Screenshot Checklist

- Locked or onboarding state.
- Fake unlocked list.
- Fake secret detail metadata.
- Governance or grants view.
- Import/export confirmation.

## Notes for Future Automation

- Redaction checks should run before saving artifacts.
- Never automate value reveal.
- Host metadata validation must use Secrets Vault proxy metadata only, not secret values.
