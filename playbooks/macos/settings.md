---
id: macos.settings.overview
platform: macos
surface: settings
status: ready
priority: P1
tags:
  - regression
  - dummy
  - host
  - settings
  - sensitive
  - confirmation
intent: "Validate macOS settings pages, configuration changes, confirmations, host-dependent panels, and sensitive flows without performing real destructive or paid operations by default."
entrypoints:
  - settings-sidebar
  - command-palette-settings
  - route-from-feature
  - menu-command
variants:
  - general-feature-previews
  - language-change
  - sync-toggles
  - local-reset-confirmation
  - voice-to-text
  - quickask
  - mcp-stdio
  - mcp-http
  - machines-bridge
  - secrets-vault
  - local-models
  - memory
  - clawjs
  - telegram
  - usage
  - git
  - browser-usage
required_state:
  app_mode: dummy
  data: fixture-backed settings where possible
  backend: fake or isolated local services
  window: settings route visible in the main macOS app window
safety:
  level: confirmation_required
  default: isolated
  requires_explicit_confirmation:
    - real prompt submission
    - real secret creation or reveal
    - real external account connection
    - real local model download
    - real daemon install or login item mutation
    - destructive reset
    - production service write
    - paid API call
  forbidden_without_confirmation:
    - revealing secret values
    - deleting real user data
    - publishing or uploading anything
execution_mode:
  hermetic: required for settings navigation and fake state changes
  host: required for permissions, bridge pairing, local models daemon, ClawJS services, browser permissions, and secrets vault host behavior
artifacts:
  - settings index screenshot
  - screenshot for each page touched
  - confirmation dialog screenshot for destructive or sensitive flows
assertions:
  - settings sidebar selection matches page content
  - toggles and segmented controls visibly change state
  - sensitive actions present confirmation or blocked state
  - host-dependent pages distinguish unavailable, starting, running, and error states
known_risks:
  - feature flags can hide dev-only pages in release builds
  - host permissions depend on macOS state
  - local services may already be running
  - secrets flows must never expose secret values
---

## Goal

Verify that settings pages are navigable, visually coherent, and explicit about state changes, sensitive operations, and host-dependent runtime conditions.

## Invariants

- Settings sidebar selection must match the visible page.
- A toggle or selector must provide visible feedback after change.
- Destructive actions must require confirmation.
- Real secrets must never be displayed, copied, logged, or included in screenshots.
- Host-dependent panels must show unavailable, running, blocked, or error states.

## Setup

- Launch in dummy mode.
- Use fixture or fake services for pages that would otherwise touch real accounts.
- Do not accept real permission prompts or destructive confirmations unless explicitly requested.

## Entry Points

- Open Settings through the sidebar, visible route, or command palette.
- Navigate to a feature-specific settings page from the feature surface.
- Use menu commands where available.

## Variant Matrix

| Page | Required variants |
| --- | --- |
| General | developer surfaces, language, sync toggles, local reset confirmation |
| Voice to Text | permissions, language, model, cleanup, vocabulary, replacements, prompt editing |
| QuickAsk | enablement, shortcut, capture, attachments, recent chat target |
| MCP servers | create STDIO, edit STDIO, create HTTP, edit HTTP, uninstall confirmation |
| Machines | bridge unavailable, pairing flow, workspace trust modes, allowed workspace changes |
| Secrets | locked, unlocked, onboarding, import/export confirmation, governance, grants, audit |
| Local models | runtime state, install prompt, download, default, unload, delete confirmation |
| Memory | list settings, injection state, graph launch path, unavailable service |
| ClawJS | idle, starting, running, running from daemon, crashed, daemon unavailable, logs |
| Telegram | disconnected, configuration form, validation error, connected fake state |
| Usage | used/remaining display, limit cards, empty or unavailable usage |
| Git | merge method, branch state, repository unavailable |
| Browser usage | permission policy, usage summary, clear or reset confirmation |

## Critical Cases

- `P1-general-settings`: General page renders and safe toggles visibly change.
- `P1-sensitive-confirmation`: destructive or sensitive controls stop at confirmation.
- `P1-runtime-pages`: Machines, Local models, and ClawJS show explicit host state.
- `P1-secrets-redaction`: Secrets screens never expose secret values.

## Steps

1. Open Settings.
2. Select General and verify the page header and sections match the sidebar selection.
3. Toggle a safe fixture-backed setting and confirm visible change.
4. Open a destructive reset action and stop at confirmation.
5. Inspect Voice to Text and MCP STDIO/HTTP create states; cancel without saving.
6. Verify runtime and sensitive pages expose state without real actions.

Alternate passes:

1. Enable developer surfaces in an isolated debug build and inspect dev-only pages.
2. Exercise secondary pages as navigable pages.
3. For host validation, repeat only the relevant page in real host mode.

## Expected Results

- Each page renders a clear header and relevant controls.
- Safe toggles and selectors visibly update.
- Sensitive operations show a confirmation or blocked state.
- Host-dependent pages report real runtime state without pretending success.
- Secrets screens never reveal secret values.

## Failure Signals

- Sidebar selection changes but page content does not.
- A settings page opens blank.
- A destructive action executes without confirmation.
- A real external connection, download, prompt, or production write starts without confirmation.
- Secrets values are visible in UI, logs, screenshots, or clipboard.
- Host-dependent state is marked fixed with only hermetic validation.

## Evidence Checklist

| Check | Result |
| --- | --- |
| Settings sidebar and page selection matched | pass/fail/no-run |
| Safe toggle or selector changed visibly | pass/fail/no-run |
| Sensitive actions stopped at confirmation | pass/fail/no-run |
| Host-dependent page state was explicit | pass/fail/no-run |
| Secrets redaction was respected | pass/fail/no-run |
| Required screenshots captured | pass/fail/no-run |

## Screenshot Checklist

- General, feature-preview, Voice to Text, and MCP STDIO/HTTP create states.
- Machines, Secrets without values, and Local models state.
- Any page changed by the task.

## Notes for Future Automation

- A future runner should treat settings pages as route targets plus page-specific variants.
- Sensitive pages need redaction checks before artifacts are saved or shared.
- Host validation should record whether it used dummy, fake local service, real local daemon, or real external account.
