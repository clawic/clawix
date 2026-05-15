---
name: host-boundary-review
description: Review framework vs host ownership for permissions, approvals, grants, native execution, storage, daemons, and Clawix integration.
keywords: [host, boundary, permissions, approvals, daemon, clawix, clawhostkit]
---

# host-boundary-review

Preserve the ClawJS/Claw framework and signed-host boundary.

## Procedure

1. Read host ownership, data-storage boundary, framework-host ADR, and relevant platform playbooks.
2. Identify whether the capability belongs to framework contracts, domain APIs, storage, CLI, host-native approvals, GUI state, or host operational state.
3. Keep sensitive native permissions, grants, approvals, audit, LaunchAgents, Mach services, and native execution under the active signed host.
4. Ensure clients consume daemon/host contracts before adding duplicated UI-owned backends.
5. For Clawix, keep native UI and host identity separate from canonical framework storage.
6. Validate host-dependent paths with signed-host or host-equivalent validation when feasible.

## Constraints

- Node must not request sensitive native permissions directly.
- Do not create a second GUI-owned bridge/backend when daemon mode owns runtime.
- Public docs must use safe placeholders, not real local identities.
