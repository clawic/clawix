# ADR 0005: Integration QA Lab

Status: Accepted

Date: 2026-05-14

## Context

Clawix consumes framework integrations through ClawJS/Claw and the active
signed host. The app can help a human approve live checks, see validation
state, or provide physical prerequisites, but it must not redefine connector
completeness locally.

Live provider validation can require API keys, bot tokens, phones, public
webhooks, payments, administrator roles, or destructive provider state. Those
flows must stay outside default tests and must not expose plaintext secrets to
ordinary Node connector runtimes.

## Decision

Clawix follows the ClawJS Integration QA Lab standard for external connectors.
For each integration surfaced in the app:

1. The canonical official provider surface and coverage matrix live in ClawJS.
2. Clawix may display the matrix, scenario state, or required approvals, but
   must treat ClawJS as the source of truth.
3. Live validation requires explicit operator approval, brokered credential
   leases, disposable provider state where possible, and signed-host-owned
   approval/audit handling.
4. Physical, paid, public-delivery, destructive, account-mutating, or
   provider-role-dependent checks remain manual scenarios until safely
   brokered.
5. Unavailable external prerequisites are reported as `EXTERNAL PENDING`, not
   as a pass.

Telegram is the pilot integration. Clawix references the Telegram QA scenario
and must not run a Telegram live check directly from UI code without going
through the framework/host boundary.

## Consequences

- Clawix connector UI cannot claim "complete" from local UI wiring alone.
- Host approval surfaces must distinguish hermetic pass, brokered live pass,
  manual pending, and policy-blocked rows.
- Any future Clawix integration panel must preserve the framework-owned
  coverage matrix and avoid raw-token handling in app logic.
