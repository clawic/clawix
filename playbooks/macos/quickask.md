---
id: macos.quickask
platform: macos
surface: quickask
status: ready
priority: P1
tags:
  - regression
  - dummy
  - host
  - composer
  - attachments
intent: "Validate QuickAsk invocation, target selection, captured context, attachments, recent chat routing, and safe fake submission behavior."
entrypoints:
  - global-shortcut
  - settings-quickask
  - selection-capture
  - recent-chat-picker
variants:
  - no-selection
  - text-selection
  - screenshot-attachment
  - recent-chat-target
  - new-chat-target
  - disabled-feature
required_state:
  app_mode: dummy
  data: fixture chats and public selected text
  backend: fake or intercepted send
  window: QuickAsk panel visible over macOS
safety:
  level: host_local
  default: isolated panel and fake send
  requires_explicit_confirmation:
    - capturing private screen content
    - sending selected text to a real backend
    - attaching private files or screenshots
execution_mode:
  hermetic: required for settings and fake panel state
  host: required for global shortcut, selection capture, and screen capture behavior
artifacts:
  - QuickAsk panel screenshot
  - settings screenshot
  - routed result screenshot
assertions:
  - panel appears with expected focus
  - selected target is visible
  - captured context is represented without leaking private data
  - fake send routes to the expected chat or new conversation
known_risks:
  - global shortcuts depend on host permissions
  - selection and screenshot capture can expose private content
  - recent chat lists can be stale in real mode
---

## Goal

Verify QuickAsk as a fast capture and routing surface while keeping default execution isolated from private selection, screenshots, and real prompt submission.

## Invariants

- The panel must open focused and dismiss predictably.
- Target chat or new-chat destination must be visible before send.
- Captured text or attachments must be public fixtures by default.
- Real screen or selection capture requires explicit confirmation.

## Setup

- Enable QuickAsk only in an isolated debug/dummy context.
- Seed fixture chats for recent target selection.
- Use public selected text for host validation.
- Use fake backend submission.

## Entry Points

- Invoke the global QuickAsk shortcut.
- Open QuickAsk settings.
- Capture selected text in host mode.
- Choose a recent chat target.

## Variant Matrix

| Dimension | Variants |
| --- | --- |
| Invocation | shortcut, settings preview, feature route |
| Context | none, selected text, screenshot, attachment |
| Target | new chat, existing recent chat |
| Send | fake submit, blocked real submit |
| Feature state | disabled, enabled |

## Critical Cases

- `P1-open-panel`: shortcut opens focused panel.
- `P1-target-route`: selected recent chat receives fake prompt.
- `P1-context-redaction`: fixture context is shown without private data.
- `P2-disabled-state`: disabled QuickAsk has clear settings state.

## Steps

1. Open QuickAsk settings and confirm enablement/shortcut state.
2. Invoke QuickAsk through the shortcut or visible route.
3. Confirm the prompt field is focused.
4. Select a recent fixture chat target.
5. Add public fixture context or leave context empty.
6. Submit through fake backend.
7. Confirm the destination surface reflects the fake prompt.

## Expected Results

- The panel opens quickly and is visually distinct from the main composer.
- Target selection is visible and reversible.
- Fixture context appears as chips or preview.
- Fake submission closes or routes according to the selected target.

## Failure Signals

- Panel opens without focus.
- Target is ambiguous before send.
- Private content is captured without confirmation.
- Fake send creates duplicate chats or routes to the wrong chat.
- Disabled feature can still be invoked.

## Evidence Checklist

| Check | Result |
| --- | --- |
| QuickAsk settings checked | pass/fail/no-run |
| Panel open/focus checked | pass/fail/no-run |
| Target selection checked | pass/fail/no-run |
| Context capture classified safe or no-run | pass/fail/no-run |
| Fake route result checked | pass/fail/no-run |

## Screenshot Checklist

- QuickAsk settings.
- Empty focused panel.
- Panel with target selected.
- Panel with fixture context.
- Destination chat after fake send.

## Notes for Future Automation

- Keep host context capture separate from dummy panel rendering.
- Use public fixture text for selection tests.
- Do not persist screenshots captured from a real desktop unless explicitly approved.
