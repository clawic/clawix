---
name: secrets-boundary-review
description: Review secret handling, brokered execution, redaction, vault boundaries, host approval, and public hygiene.
keywords: [secrets, vault, broker, redaction, approval, security]
---

# secrets-boundary-review

Keep secrets out of public repos, logs, databases, and ordinary agent context.

## Procedure

1. Read security docs, secrets ADRs, host ownership, and public hygiene rules.
2. Inventory secret references, secret values, logs, screenshots, fixtures, environment variables, and generated assets touched by the change.
3. Use secret references, leases, brokered execution, host approval, and redaction instead of plaintext values.
4. Verify agents, CLI, connectors, and tests do not print or persist raw secret material.
5. Add or update public hygiene checks when a new leak class is discovered.
6. Document `EXTERNAL PENDING` when real credentials or provider access are required.

## Constraints

- Never commit real credentials, signing identities, Team IDs, bundle IDs, SKUs, private URLs, or local maintainer paths.
- Do not put plaintext secrets in `core.sqlite`.
- Do not ask the user to paste secrets into chat when a vault/proxy path exists.
