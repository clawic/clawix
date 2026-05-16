## Summary

## UI governance evidence

Mutation class:

Pattern/debt/protected/exception mapping:

Touched files:

Visible surfaces:

Required interactive states:

Public UI checks:

Visual/copy/layout authorization:

Conceptual proposal:

## Checklist

- [ ] The branch name is scoped and short (`feat/*`, `fix/*`, `docs/*`, `chore/*`).
- [ ] `swift build` passes locally.
- [ ] `bash apps/macos/scripts/public_hygiene_check.sh` passes locally.
- [ ] `bash apps/macos/scripts/dev.sh` opens the app without regressions.
- [ ] Docs / `CHANGELOG.md` updated when public-facing behavior changed.
- [ ] No maintainer-specific signing values (codesign identity, Apple Team ID, real bundle id) added to the public source. Those live only in `.signing.env` outside the repo.

## Release notes

- Does this need a `CHANGELOG.md` entry? If yes, include the user-facing note here.
