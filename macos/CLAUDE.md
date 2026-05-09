# Clawix · macOS app

This file is the macOS-specific anchor for any agent (Claude Code,
another Claude, a human contributor) working under
`macos/`. The repo-root `clawix/CLAUDE.md` owns project-wide
conventions; this one only adds what is specific to the macOS target.

## Scope

- The macOS target lives at `macos/`. Sources at
  `macos/Sources/Clawix/`. Build via `bash dev.sh` from the repo
  root (or workspace root when developing locally — see the workspace
  `CLAUDE.md` for the wrapper that injects `SIGN_IDENTITY` and
  `BUNDLE_ID`).
- Cross-platform code shared with iOS lives at
  `packages/`. Edit there only when the change applies to both
  platforms.
- Do NOT touch `ios/` from a macOS task unless the change is
  genuinely cross-platform (a shared protocol, a wire-type fix that
  breaks iOS too). Indicate it explicitly in the proposal.

## Performance investigations

When the user reports any performance issue ("X feels slow",
"frames drop", "RAM keeps growing", "the sidebar is laggy", "this
feels like it freezes"), the workflow is fixed:

1. Read `macos/PERF.md`. Find the symptom in the table.
2. Run the capture for the matching template:
   ```
   bash macos/scripts/perf-capture.sh --template "<template>" --name <slug>
   ```
   (The user reproduces the symptom inside the launched app, then
   quits / Ctrl-C the script.)
3. Open `trace.trace` from the printed directory in Instruments.
   Cross-reference with `console.ndjson`, `clawix-renders.log`, and
   `Diagnostics-*/` in the same directory.
4. Only then propose a fix, citing what the trace showed.

Never start optimizing without a trace. Static-reading hot paths in
this codebase is wrong often enough that a single capture pays for
itself.

The diagnostic stack (RenderProbe, PerfSignpost taxonomy,
ResourceSampler, HangDetector, MetricKitObserver) is documented in
`macos/PERF.md`. New signposts go through
`Sources/Clawix/Diagnostics/Signposts.swift`, not ad-hoc
`os_signpost`. New symptoms or moved hot paths get a row in PERF.md.

Environment switches the diagnostic stack honours:

- `CLAWIX_DISABLE_SIGNPOSTS=1` — suppress all `PerfSignpost` traffic
  (release-build escape hatch).
- `CLAWIX_FORCE_HANG_DETECTOR=1` — enable `HangDetector` in a release
  build (DEBUG-only by default).
- `CLAWIX_HANG_MS=<ms>` — override the hang threshold (default 250).
- `CLAWIX_DEV_NOLAUNCH=1` — `dev.sh` builds without launching the
  app. Used by `perf-capture.sh` so xctrace owns the launch.

## ClawJS pinning

Every Clawix build is pinned to one exact `@clawjs/cli` release. The
pin lives in `macos/CLAWJS_VERSION` (one line, semver). The build
pipeline reads it via `macos/scripts/_emit_version.sh`, exports
`CLAWJS_VERSION`, and interpolates it into the generated Info.plist as
`ClawJSVersion`. Swift code reads it through
`ClawJSRuntime.expectedVersion`; never hardcode the version inline.

Bumping the pin is a deliberate, coordinated act:

1. The ClawJS team cuts a release of `@clawjs/cli` (lockstep with the
   rest of the `@clawjs/*` packages).
2. We update `macos/CLAWJS_VERSION` in a single commit, with a
   message that names the new version and links the upstream changeset.
3. Phase 1 (when it lands) re-runs `bundle_clawjs.sh` so the bundled
   `Contents/Helpers/clawjs/package.json` matches the pin. The release
   pipeline rejects mismatches.

Framework changes (anything that requires editing `~/Desktop/clawjs/`)
are filed as requests against the ClawJS repo, not implemented in this
tree. The macOS app only consumes the published `@clawjs/cli` and the
contracts documented in this CLAUDE.md.
