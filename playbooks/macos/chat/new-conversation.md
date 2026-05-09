---
id: macos.chat.new-conversation
platform: macos
surface: chat
status: reference
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
- If plan mode is enabled before send, the plan mode state must be visible before submission and represented in the resulting flow.

## Setup

- Launch the macOS app in dummy or fixture-backed mode.
- Use a data set with at least one existing chat, one project, and an empty home/new-chat state.
- Keep the main app window focused.
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
| Start path | keyboard, menu, sidebar button, command palette, project action, empty state, bridge |
| Input method | typed short text, typed multiline text, pasted long text, slash command |
| Content | text only, attachment only, text plus attachment |
| Configuration | default model, changed model, changed permission mode, plan mode on |
| Project scope | no project, selected project, project action |
| Runtime | hermetic fake backend, host-local daemon, real backend only with confirmation |

## Steps

1. Start from the home or current chat surface.
2. Invoke one entrypoint, beginning with Command-N for the reference path.
3. Confirm the new conversation surface appears and the composer is focused.
4. Type `Summarize the fixture project status in one sentence.`
5. Confirm the send button becomes enabled.
6. Send the message.
7. Wait for the user message to appear.
8. Confirm the sidebar shows one new selected chat row.
9. Confirm the composer is empty and ready for another message.

Alternate entrypoint passes:

1. Repeat the same happy path through File -> New Chat.
2. Repeat through the sidebar new-chat button.
3. Repeat through the command palette.
4. Repeat through a project row and confirm the project pill or project grouping reflects the selected project.
5. Repeat from an empty state.
6. Repeat through a bridge-originated fake new-chat request.

Composition variants:

1. Use a three-line prompt and verify line wrapping does not obscure toolbar controls.
2. Paste a long multi-paragraph prompt and verify the composer grows up to its limit while remaining scrollable.
3. Type `/` and select the plan command; verify plan mode turns on and the command text is removed.
4. Type a sentence containing `plan`; accept the plan suggestion and verify the plan mode pill appears.
5. Stage a fixture image and send text plus image.
6. Stage only a fixture attachment and verify send enables without text.
7. Change permission mode before send and verify the pill updates before submission.
8. Change model or reasoning before send and verify the model picker label updates before submission.

## Expected Results

- The visual transition lands on a clean new-chat composer without stale text.
- Keyboard focus is in the composer for keyboard, menu, sidebar, command palette, and project entrypoints.
- The user message appears once in the transcript.
- The sidebar selects the newly created chat and does not create duplicates.
- Attachment previews or chips appear before send and are represented in the user message after send.
- Plan mode is visible before send when enabled.
- Project-scoped creation leaves the chat under the expected project grouping.
- No real network, cost, secret, or production write occurs in isolated mode.

## Failure Signals

- Composer does not focus after starting a new chat.
- Send remains disabled with valid text or attachment content.
- Send enables for an empty composer with no attachment.
- A stale draft from a previous chat remains.
- The new chat appears twice in the sidebar.
- The chat is created outside the selected project.
- Attachments disappear before send or are not represented after send.
- A real prompt is sent without explicit confirmation.

## Screenshot Checklist

- New conversation composer focused before typing.
- Composer with a long multiline draft.
- Composer with plan mode visible.
- Composer with fixture attachment staged.
- Transcript after send with the new sidebar row selected.
- Project-scoped new chat after send.

## Notes for Future Automation

- Prefer accessibility labels for New Chat, Composer text field, Send message, Add, Change model, Change permissions, and Turn off plan mode.
- Future automation should model entrypoints and content variants separately so failures identify the broken path.
- Title assertions should allow asynchronous title generation; assert row existence and uniqueness before exact title text.
- Bridge-originated variants need a local fake daemon or intercepted bridge frame.
