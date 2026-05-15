---
name: host-dependent-validation
description: Validate bugs and features that depend on local hosts, localhost, filesystem home state, auth, polling, installed apps, or signed native helpers.
keywords: [validation, host, localhost, signed-host, e2e, external-pending]
---

# host-dependent-validation

Validate behavior in the mode where the user experiences it.

## Procedure

1. Identify why the path is host-dependent: localhost, installed app, signed helper, auth, filesystem home, PATH, polling, native permission, or device.
2. Run hermetic checks first when they are useful, but mark them partial for host-dependent claims.
3. Use the project-approved launcher or host-equivalent path for final validation when feasible.
4. Keep real prompts, paid APIs, production data, destructive actions, and secrets behind explicit approval.
5. Capture what was actually validated and what remains `EXTERNAL PENDING`.
6. Separate physical validation gaps from reproducible bugs.

## Constraints

- Do not claim a host-dependent bug is fixed from hermetic E2E alone.
- Screenshots or logs must come from the mode actually validated.
- Do not bypass host signing or permissions to make validation easier.
