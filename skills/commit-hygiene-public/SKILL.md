---
name: commit-hygiene-public
description: Apply public, contributor-safe commit hygiene without maintainer-private automation, timestamps, ledger rules, or push policy.
keywords: [commits, conventional-commits, changesets, privacy, public]
---

# commit-hygiene-public

Use public commit hygiene only.

## Procedure

1. Scope each commit to one user-visible behavior, fix, doc update, test update, or mechanical refactor.
2. Use Conventional Commits: `type(scope): description`.
3. Do not sweep unrelated edits from a dirty worktree.
4. Commit `.changeset/*.md` with the functional change it documents when a published package surface changes.
5. Run relevant validation before proposing merge or release.
6. Treat push, publish, upload, tag creation, and release actions as explicit separate approvals.

## Constraints

- Do not include maintainer-private `commit de todo`, ledger, timestamp, Claude-context, or automation procedures.
- Do not publish secrets, local paths, signing identities, bundle IDs, Team IDs, or private workflow details in commits.
- Do not rewrite public history unless the project's public contribution docs explicitly allow it.
