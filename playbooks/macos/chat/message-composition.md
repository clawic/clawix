---
id: macos.chat.message-composition
platform: macos
surface: chat
status: ready
priority: P0
tags:
  - smoke
  - regression
  - dummy
  - composer
  - voice
intent: "Exercise composer text entry, model/runtime controls, permission controls, plan mode, voice entry states, and send-button enablement without relying on real model calls."
entrypoints:
  - focused-composer
  - active-chat-follow-up
  - home-new-chat-composer
  - slash-command-menu
  - voice-button
variants:
  - empty-draft
  - short-draft
  - multiline-draft
  - long-pasted-draft
  - slash-command
  - plan-suggestion
  - model-picker-change
  - permission-mode-change
  - local-model-selection
  - voice-recording-state
required_state:
  app_mode: dummy
  data: fixture-backed chat with at least one active conversation
  backend: fake or intercepted for send actions
  window: main macOS app window visible and focused
safety:
  level: safe_dummy
  default: isolated
  requires_explicit_confirmation:
    - real prompt submission
    - paid model call
    - microphone permission changes on the real host
    - local model download
execution_mode:
  hermetic: required for composer state and fake send
  host: required for keyboard focus, paste behavior, voice UI, microphone permissions, and local model runtime checks
artifacts:
  - focused composer screenshot for each control state
  - transcript screenshot after fake send
assertions:
  - send disabled for empty content
  - send enabled for valid text
  - composer expands for multiline input
  - slash menu appears only for slash input
  - visible controls reflect selected model, reasoning, permission mode, and plan state
known_risks:
  - local model availability is host-dependent
  - voice permission state depends on macOS TCC
  - long pasted text can change screenshot height
---

## Goal

Verify that the composer behaves predictably across text sizes, input methods, configuration choices, and recording states.

## Invariants

- Empty text with no attachments keeps send disabled.
- Any non-whitespace text enables send.
- Long text must not cover toolbar controls.
- Slash commands must not persist after selection.
- Configuration controls must update visibly before a message is sent.
- Voice recording and transcription states must replace the normal toolbar intentionally and then return to normal.

## Setup

- Launch the app in dummy mode.
- Open an existing fixture chat or the new-chat composer.
- Use fake backend responses for send paths.
- Avoid real microphone permission prompts unless the task is explicitly about host validation.

## Entry Points

- Click the composer field in an existing chat.
- Start a new chat and use the initial composer.
- Type `/` to open slash commands.
- Click the model picker, permission picker, plan mode control, or voice button.

## Variant Matrix

| Dimension | Variants |
| --- | --- |
| Text | empty, whitespace-only, short, multiline, long pasted |
| Send trigger | return, send button, fake bridge send |
| Mode | normal, plan mode, slash command |
| Runtime choice | default model, changed reasoning, fast mode, local model |
| Permission | default, read-only, workspace-write, approval-heavy mode |
| Voice | idle, recording, transcribing, stopped without send, stopped with send |

## Critical Cases

- `P0-empty-send-disabled`: empty and whitespace-only drafts keep send disabled.
- `P0-multiline-stability`: multiline and long pasted drafts keep toolbar controls usable.
- `P1-model-permission-state`: model and permission controls visibly update before send.
- `P1-voice-fixture`: fixture transcription moves through recording and transcribing states.

## Steps

1. Focus the composer.
2. Confirm send is disabled when the draft is empty.
3. Type a short prompt and confirm send enables.
4. Add line breaks and confirm the composer grows without hiding controls.
5. Paste a long prompt and confirm scrolling or height limits keep the UI usable.
6. Open the model picker, select a different visible option, and confirm the label changes.
7. Open the permission picker, select a different mode, and confirm the pill changes.
8. Enable plan mode and confirm the plan pill appears.
9. Send through the fake backend and confirm the draft clears.

Alternate passes:

1. Type `/`, choose a slash command, and verify the menu closes.
2. Type a sentence containing `plan`, accept the suggestion, and verify plan mode turns on.
3. Enter whitespace-only text and verify send remains disabled.
4. Start voice recording with fixture transcription and verify recording, transcribing, and final draft states.

## Expected Results

- The composer remains visually stable across all draft sizes.
- The toolbar controls remain clickable and non-overlapping.
- The selected model and permission mode are visible.
- Plan mode has a visible state and can be turned off.
- Voice UI has clear recording, stop, send, and transcribing states.
- Fake send creates a user message and clears the composer.

## Failure Signals

- Toolbar controls overlap text.
- Long pasted text pushes the composer outside the window.
- Send enables for whitespace-only content.
- Slash menu remains after selection.
- Model or permission changes do not update the visible label.
- Voice recording state gets stuck.
- Fake send leaves stale text behind.

## Evidence Checklist

| Check | Result |
| --- | --- |
| Empty composer state verified | pass/fail/no-run |
| Short, multiline, and long draft variants checked | pass/fail/no-run |
| Configuration controls updated visibly | pass/fail/no-run |
| Fake send cleared draft state | pass/fail/no-run |
| Voice state checked or marked no-run with reason | pass/fail/no-run |
| Required screenshots captured | pass/fail/no-run |

## Screenshot Checklist

- Empty focused composer.
- Multiline draft.
- Long pasted draft at maximum height.
- Slash command menu.
- Plan mode active.
- Model picker or permission picker open.
- Voice recording or transcribing state when applicable.

## Notes for Future Automation

- Keep text fixtures stable but avoid asserting exact generated titles.
- Separate composer visual assertions from backend response assertions.
- Voice tests should use fixture transcription environment variables where available.
