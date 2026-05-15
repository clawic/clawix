# Pattern registry

Each pattern has a machine-readable manifest in `patterns/<id>.json` and may
have short Markdown notes when prose is needed.

Pattern manifests are contracts for agents and checks. They are not design
brainstorming documents.

Every visible UI surface must map to one of:

- a registry pattern;
- a frozen protected surface;
- a debt-baseline entry;
- an exception with expiry/review date.

## Manifest requirements

Each pattern declares:

- `id`, `status`, `platforms`, and `mutationClass`;
- canonical source references;
- allowed states;
- geometry contract;
- copy contract;
- performance contract if relevant;
- validation commands or private baseline references;
- whether component extraction is required, allowed, or forbidden.
