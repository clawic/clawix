---
id: macos.settings.overview
platform: macos
surface: settings
status: ready
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
  - one screenshot per settings page touched
  - confirmation dialog screenshot for destructive or sensitive flows
assertions:
  - settings sidebar selection matches page content
  - toggles and segmented controls visibly change state
  - sensitive actions present confirmation or blocked state
  - host-dependent pages distinguish unavailable, starting, running, and error states
known_risks:
  - feature flags can hide experimental pages in release builds
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
- Host-dependent panels must show clear unavailable, running, blocked, or error states.
- Experimental pages may be hidden unless feature previews are enabled in a debug build.

## Setup

- Launch in dummy mode.
- Open Settings from a visible route or the command palette.
- Use fixture or fake services for pages that would otherwise touch real accounts.
- Do not accept real permission prompts or destructive confirmations unless explicitly requested.

## Entry Points

- Open Settings through the sidebar or visible route.
- Open Settings through the command palette.
- Navigate to a feature-specific settings page from the feature surface.
- Use menu commands where available.

## Variant Matrix

| Page | Required variants |
| --- | --- |
| General | feature previews, language, sync toggles, local reset confirmation |
| Voice to Text | permissions, language, model, filler removal, vocabulary, replacements, prompt editing, onboarding, recorder style |
| QuickAsk | enablement, shortcut, selection capture, attachments, recent chat target |
| MCP servers | create STDIO, edit STDIO, create HTTP, edit HTTP, uninstall confirmation |
| Machines | bridge unavailable, pairing flow, workspace trust modes, allowed workspace changes |
| Secrets | locked, unlocked, onboarding, import preview, export confirmation, governance, grants, audit, trash |
| Local models | unavailable runtime, install prompt, start, download, default selection, unload, delete confirmation, error state |
| Memory | list settings, injection state, graph launch path, unavailable service |
| ClawJS | idle, starting, running, running from daemon, crashed, daemon unavailable, logs |
| Telegram | disconnected, configuration form, validation error, connected fake state |
| Usage | used/remaining display, limit cards, empty or unavailable usage |
| Git | merge method, branch state, repository unavailable |
| Browser usage | permission policy, usage summary, clear or reset confirmation |

## Steps

1. Open Settings.
2. Select General and verify the page header and sections match the sidebar selection.
3. Toggle a safe fixture-backed setting and confirm visual state changes.
4. Open a destructive local reset action but stop at the confirmation dialog.
5. Navigate to Voice to Text and inspect permission, model, language, replacement, and prompt-editing states.
6. Navigate to MCP servers and open a create sheet for STDIO; cancel without saving.
7. Open the HTTP MCP variant and verify URL/header fields are visible; cancel without saving.
8. Navigate to Machines and verify bridge state is explicit.
9. Navigate to Secrets and verify locked, onboarding, or fake unlocked state without exposing values.
10. Navigate to Local models and verify install/runtime/download states are explicit without downloading.

Alternate passes:

1. Enable feature previews in an isolated debug build and confirm experimental settings pages appear.
2. Exercise QuickAsk settings and verify shortcut and capture choices update visually.
3. Exercise Memory, ClawJS, Telegram, Usage, Git, and Browser Usage pages as navigable pages with visible state.
4. For host validation, repeat only the page relevant to the bug in the real host mode and capture the same page state.

## Expected Results

- Each settings page renders a clear header and relevant controls.
- Sidebar selection and content stay synchronized.
- Safe toggles and selectors visibly update.
- Sensitive or destructive operations show a confirmation or blocked state.
- Host-dependent pages report real runtime state without pretending success.
- Secrets screens never reveal secret values.

## Failure Signals

- Sidebar selection changes but page content does not.
- A settings page opens blank.
- A destructive action executes without confirmation.
- A real external connection, download, prompt, or production write starts without confirmation.
- Secrets values are visible in UI, logs, screenshots, or copied text.
- Host-dependent state is marked fixed with only hermetic validation.

## Screenshot Checklist

- General page.
- Feature previews or hidden experimental state.
- Voice to Text page.
- MCP create sheet for STDIO and HTTP.
- Machines page showing bridge state.
- Secrets locked/onboarding/fake unlocked state without values.
- Local models unavailable or install state.
- Any additional page changed by the task.

## Notes for Future Automation

- A future runner should treat settings pages as route targets plus page-specific variants.
- Sensitive pages need redaction checks before artifacts are saved or shared.
- Host validation should record whether it used dummy, fake local service, real local daemon, or real external account.
