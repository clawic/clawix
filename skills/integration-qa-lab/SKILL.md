---
name: integration-qa-lab
description: Build or review an external integration QA lab with official surface snapshots, coverage matrices, fixtures, opt-in live lanes, and safe credential handling.
keywords: [integration, qa, fixtures, live, provider, external-pending]
---

# integration-qa-lab

Make external integrations testable without unsafe live actions.

## Procedure

1. Read the Integration QA Lab ADR/docs and the provider-specific docs.
2. Capture or update the official provider surface snapshot with source URL, version, and date.
3. Maintain a coverage matrix classifying each capability as implemented, fixture-only, blocked, not applicable, cost-risk, auth-required, host-required, or destructive.
4. Add hermetic fixtures and dry-run/interceptor paths before live tests.
5. Keep live lanes opt-in, brokered, credential-safe, and explicit about cost/destructive risk.
6. Report unavailable physical/provider prerequisites as `EXTERNAL PENDING`.

## Constraints

- UI wiring alone does not complete an integration.
- Do not forward secrets to candidate packages until the package under test is the intended artifact.
- Do not call real providers, mutate data, or spend money without explicit approval.
