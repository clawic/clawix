# ADR 0010: Interface governance and visual mutation boundary

Status: accepted

## Context

Clawix already has a visual canon in `STYLE.md`, release correctness checks in
`STANDARDS.md`, and performance investigation procedures in `macos/PERF.md`.
Those documents describe the desired interface, but they do not by themselves
prevent agents from drifting away from approved UI while implementing unrelated
work.

UI differs from framework contracts: tests can verify behavior, but they cannot
fully verify taste, composition, visual hierarchy, or whether a model made a
poor design choice while satisfying mechanical checks. Approved UI therefore
needs protection, not just more tests.

## Decision

Clawix interface work is governed by a cross-platform Interface Governance
System. The system applies to macOS, iOS, Android, and Web from day one.

The canonical interface source is a pattern registry plus references and
contracts under `docs/ui/`. `STYLE.md` remains the prose style canon, while the
registry is the machine-readable contract surface for agents and checks.

Existing visual drift is recorded in `docs/ui/debt-baseline.json`. New or
touched code must not expand that baseline. Approved visual surfaces are frozen
in `docs/ui/protected-surfaces.json`; only the user can declare a surface
approved/frozen.

UI work is classified into four mutation classes:

- `functional-ui`: state, data, loading/error behavior, actions, accessibility
  behavior, and wiring that does not change presentation.
- `visual-ui`: color, spacing, sizing, icon choice or size, typography,
  animation, placement, layout, hierarchy, and other presentation choices.
- `copy-ui`: visible labels, tooltips, names, microcopy, empty/loading/error
  text, and copy hierarchy.
- `mechanical-equivalent-refactor`: code extraction or cleanup that proves the
  rendered output is equivalent.

Only explicitly authorized visual lanes may make `visual-ui` or `copy-ui`
decisions. The concrete authorization assignment lives outside the public repo.
Non-authorized agents may implement `functional-ui` and governance/tooling, but
when they find visual drift they must report and list it instead of repairing it.

Mechanical refactors of UI are allowed only when equivalence is proven by
before/after geometry plus visual baseline checks, with no token or copy change.

## Component extraction rule

Clawix does not pursue abstraction for its own sake. Extract reusable components only when repeated UI carries risk: at least two call sites plus state, interaction, geometry, accessibility, or performance behavior.

Extracted components prefer limited named slots over large prop bags.
Components own structure and measurement contracts; callers fill named content
slots. One-off screen composition may remain local when the parent context is
important, provided it uses canonical patterns and tokens.

## Enforcement

The fast test lane runs the public interface governance guard. Public checks
validate manifests, registry completeness, geometry contracts, model
authorization signals, exceptions, and safe source patterns. Private screenshot
baselines remain outside the public repo; public manifests store only safe
metadata, references, tolerances, and commands.

Performance budgets are defined by critical flow, starting from approved
measured baselines. Static reading alone is not enough to optimize a perceived
performance issue.

## Consequences

- Visual checks are alarms and contracts, not permission to redesign.
- Out-of-scope visual debt is tracked, not opportunistically fixed.
- New visible UI must map to a pattern, a debt entry, an exception, or a
  protected surface.
- Agents that are not visual-authorized must stop at a conceptual proposal for
  visual or copy changes.
- Critical visual cleanup is reserved for an explicitly authorized visual lane
  and explicit user-approved scope.
