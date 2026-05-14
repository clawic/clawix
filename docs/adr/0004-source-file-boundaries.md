# ADR 0004: Source file boundaries

Status: accepted

Date: 2026-05-14

## Context

Several Clawix app files reached thousands of lines before being split, and
ClawJS has the same risk in public CLI, SDK, runtime, and service surfaces. A
single file that mixes routing, state, UI, runtime effects, bridge contracts,
and product behavior becomes hard for contributors and agents to review safely.

This ADR defines a shared maintainability contract for hand-authored source
files. It does not require immediate cleanup of every existing oversized file.
It prevents new monoliths and makes existing large files visible debt.

## Decision

Hand-authored source files use these size bands:

- `<800` lines: normal.
- `800-1200` lines: acceptable only when the file has one clear
  responsibility.
- `1200-2000` lines: requires a split plan or a documented baseline exception.
- `>2000` lines: blocked for new or materially expanded hand-authored source
  unless generated, vendored, fixture-like, or explicitly exempted.
- `>5000` lines: emergency debt. Do not expand except for mechanical
  extraction, deletion, or compatibility-preserving split work.

The boundary is responsibility first, file size second. When a source file mixes
two or more of routing, public contract, state, persistence, UI layout,
interaction handlers, runtime effects, migrations, fixtures, or product
behavior, split it before adding more behavior even if it has not reached the
numeric threshold.

Clawix app views split root layout, subviews, interactions, data adapters, state
transforms, and platform helpers. State stores split models, persistence,
reducers/actions, effects, and derived projections. Bridge protocol and schema
files may be larger only when they are canonical contract surfaces; docs,
fixtures, codecs, migrations, and tests still split out.

The `clawix` CLI remains host/bridge/install/diagnostic only. If it grows, its
entrypoint should only parse globals, dispatch, and handle top-level errors;
command behavior belongs in command modules.

## Guardrail

`scripts/source-size-check.mjs` audits hand-authored source files. It ignores
generated, build, cache, vendor, and fixture-like paths. The check warns at 800
lines, requires entries in `docs/source-size-baseline.json` at 1200 lines, and
fails if a baselined file grows beyond its recorded line count.

Existing oversized files are listed in `docs/source-size-baseline.json` with a
reason. Updating that baseline is a deliberate architecture decision, not a
routine way to bypass the contract.

## Consequences

New app, bridge, protocol, runtime, or CLI behavior should add modules at the
capability boundary instead of appending to a convenient large file. Large-file
cleanup may be incremental, but any material change in an oversized file should
prefer extraction before behavior growth.

This ADR mirrors the ClawJS source file boundary ADR so both projects use the
same vocabulary and thresholds.
