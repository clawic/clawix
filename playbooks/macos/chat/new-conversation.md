---
id: macos.chat.new-conversation
platform: macos
surface: chat
status: reference
priority: P0
tags:
  - smoke
  - regression
  - dummy
  - host
  - composer
intent: "Start a new conversation through every major macOS entrypoint, compose a prompt, and verify the resulting chat appears exactly once with the expected composer, sidebar, and transcript state."
entrypoints:
  - command-n
  - file-menu-new-chat
  - sidebar-new-chat-button
  - command-palette-new-chat
  - project-scoped-new-chat
  - empty-state-new-chat
  - bridge-originated-new-chat
variants:
  - short-typed-text
  - multiline-typed-text
  - pasted-long-text
  - slash-plan-command
  - plan-mode-pill
  - attachment-only
  - attachment-with-text
  - project-scoped
  - permission-mode-change
  - model-change-before-send
required_state:
  app_mode: dummy
  data: fixture-backed or local isolated chats
  backend: fake or intercepted unless real prompt submission is explicitly approved
  window: main macOS app window visible and focused
safety:
  level: safe_dummy
  default: isolated
  requires_explicit_confirmation:
    - real prompt submission
    - paid model call
    - production backend write
    - external account interaction
  forbidden_without_confirmation:
    - sending prompts to a real model
    - attaching private user files
execution_mode:
  hermetic: required for fixture-backed UI flow
  host: required when validating keyboard focus, menu shortcuts, drag-and-drop, bridge-originated chat creation, or localhost runtime behavior
artifacts:
  - focused main-window screenshot before send
  - focused main-window screenshot after send
  - optional screenshot of entrypoint-specific popup or menu
assertions:
  - new chat surface is visible
  - composer receives focus
  - send button enables only when content or attachments exist
  - sent user message appears in the transcript
  - sidebar contains exactly one new chat row for the flow
  - composer text and staged attachments reset after send
  - selected project and configuration choices are reflected in the visible chrome
known_risks:
  - title generation may be asynchronous
  - dummy response timing may differ from real streaming
  - macOS menu focus can be affected by the active application
  - bridge-originated creation is host-dependent
---

## Goal

Verify that a user can start a fresh conversation from any supported macOS entrypoint, configure the composer, submit content, and see one coherent chat created in the transcript and sidebar.

## Invariants

- A new conversation must not duplicate rows in the sidebar.
- The composer must autofocus after entering the new conversation surface.
- Empty composer state must keep send disabled unless an attachment is staged.
- Sending must create one visible user message.
- After send, composer text, slash menu state, and staged attachment chips must clear.
- If a project is selected before send, the new chat must visually belong to that project.
- Plan mode must be visible before send when enabled.

## Setup

- Launch the macOS app in dummy or fixture-backed mode.
- Use a data set with an existing chat, one project, and an empty new-chat state.
- If testing attachments, use synthetic public fixture files only.
- If testing bridge-originated creation, use a fake bridge client or local isolated daemon.

## Entry Points

- Press Command-N.
- Use File -> New Chat.
- Click the sidebar new chat button.
- Open the command palette and choose New chat.
- Open a project row and choose its new-chat action.
- Start from the empty-state call to action when no chat is selected.
- Trigger a new chat through the bridge client with fixture text and attachments.

## Variant Matrix

| Dimension | Variants |
| --- | --- |
| Start path | keyboard, menu, sidebar, command palette, project, empty state, bridge |
| Input method | short, multiline, long paste, slash command |
| Content | text only, attachment only, text plus attachment |
| Configuration | default model, changed model, changed permission mode, plan mode on |
| Project scope | no project, selected project, project action |
| Runtime | hermetic fake backend, host-local daemon, real backend only with confirmation |

## Critical Cases

- `P0-keyboard-new-chat`: Command-N opens a focused empty composer and sends through a fake backend.
- `P0-sidebar-new-chat`: sidebar button creates exactly one selected row.
- `P1-project-new-chat`: project-scoped action keeps the new chat under the selected project.
- `P1-plan-attachment`: plan mode plus fixture attachment remains visible before send and clears after send.

## Steps

1. Start from the home or current chat surface.
2. Invoke one entrypoint, beginning with Command-N for the reference path.
3. Confirm the new conversation surface appears and the composer is focused.
4. Type `Summarize the fixture project status in one sentence.`
5. Confirm send enables, submit, and wait for the user message.
6. Confirm the sidebar shows one selected row and the composer resets.

Alternate passes:

1. Repeat through File -> New Chat, sidebar button, command palette, empty state, and bridge-originated fake request.
2. Repeat through a project row and confirm project chrome or grouping reflects the selected project.
3. Exercise multiline, pasted long text, slash plan command, plan suggestion, attachment-only, and text-plus-attachment drafts.
4. Change permission mode and model/reasoning before send; confirm visible labels update before submission.

## Expected Results

- The visual transition lands on a clean focused composer without stale text.
- The user message appears once in the transcript.
- The sidebar selects the newly created chat and does not create duplicates.
- Attachment previews or chips appear before send and in the user message after send.
- Plan mode and project scope are visible when enabled.
- No real network, cost, secret, or production write occurs in isolated mode.

## Failure Signals

- Composer does not focus after starting a new chat.
- Send enablement does not match text or attachment state.
- A stale draft from a previous chat remains.
- The new chat appears twice in the sidebar.
- The chat is created outside the selected project.
- Attachments disappear before send or are not represented after send.
- A real prompt is sent without explicit confirmation.

## Evidence Checklist

| Check | Result |
| --- | --- |
| Entry point executed with dummy or fixture-backed data | pass/fail/no-run |
| Composer focused before typing | pass/fail/no-run |
| Send button enablement matched draft state | pass/fail/no-run |
| New user message appeared once | pass/fail/no-run |
| Sidebar row was unique and selected | pass/fail/no-run |
| Required screenshots captured | pass/fail/no-run |

## Screenshot Checklist

- Focused new conversation composer.
- Long or multiline draft.
- Plan mode or attachment staged.
- Transcript after send with selected sidebar row.
- Project-scoped new chat after send.

## Notes for Future Automation

- Prefer accessibility labels for New Chat, Composer text field, Send message, Add, Change model, Change permissions, and Turn off plan mode.
- Future automation should model entrypoints and content variants separately so failures identify the broken path.
- Title assertions should allow asynchronous title generation; assert row existence and uniqueness before exact title text.
- Bridge-originated variants need a local fake daemon or intercepted bridge frame.
