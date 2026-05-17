# Pattern registry

Each pattern has a machine-readable manifest in `patterns/<id>.pattern.json` and may
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
- performance contract and critical-flow ownership;
- validation commands or private baseline references;
- whether component extraction is required, allowed, or forbidden.

`scripts/ui_geometry_contract_check.mjs` validates that every geometry clause is
either measured with finite non-negative numbers or explicitly pending with a
reason. When geometry is platform-specific, every platform declared by the
pattern must have either measured values or its own pending source clause. It
does not approve a new visual direction. Private rendered geometry evidence
must include `measurements`, `geometryHash`, `captureCommand`,
`approvedByUserAt`, and `approvedScope` before a pending clause can be replaced
with measured contract values.
