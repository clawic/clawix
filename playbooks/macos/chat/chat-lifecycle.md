---
id: macos.chat.lifecycle
platform: macos
surface: chat
status: ready
intent: "Validate lifecycle operations for existing conversations: open, rename, edit, fork, copy, pin, archive, unarchive, unread completion, active turn interruption, and scroll restoration."
entrypoints:
  - sidebar-row
  - chat-title-menu
  - context-menu
  - message-actions
  - archived-section
  - active-turn-controls
variants:
  - rename-chat
  - edit-user-message
  - fork-conversation
  - copy-response
  - pin-unpin
  - archive-unarchive
  - unread-completion
  - stop-active-turn
  - scroll-away-and-return
required_state:
  app_mode: dummy
  data: fixture chats with messages, code block, archived item, active-turn item, and pinned candidate
  backend: fake or intercepted for mutations
  window: main macOS app window visible and focused
safety:
  default: isolated
  requires_explicit_confirmation:
    - real runtime archive mutation
    - real prompt retry or edit send
    - clipboard assertions containing private content
execution_mode:
  hermetic: required for fake lifecycle behavior
  host: required for clipboard, menu, active turn, and scroll restoration validation
artifacts:
  - before and after screenshots for lifecycle mutation
  - focused screenshot of any confirmation or edit sheet
assertions:
  - selected chat remains coherent after mutation
  - sidebar state matches pin/archive/rename changes
  - transcript state matches edit/fork/copy actions
  - active turn stop control changes back to send control
known_risks:
  - archive sync may differ between local and runtime modes
  - generated titles may update after manual title changes
  - clipboard checks are host-dependent
---

## Goal

Verify that existing conversations can be managed visually without losing selection, duplicating rows, or showing stale transcript state.

## Invariants

- Opening a chat from the sidebar must show the matching transcript.
- Rename must update the visible title and sidebar row.
- Pinning must move or mark the chat in the pinned area.
- Archiving must remove the chat from normal lists and make it available in archived state.
- Unarchiving must restore the chat to normal browsing.
- Editing or forking must not mutate unrelated chats.
- Stopping an active turn must return the composer to a send-ready state.

## Setup

- Launch in dummy mode with fixture chats.
- Include at least one long transcript for scroll checks.
- Include at least one chat with code content for copy checks.
- Include one archived chat and one active-turn chat.

## Entry Points

- Click a sidebar chat row.
- Open the sidebar row context menu.
- Use visible message action buttons.
- Use chat title actions.
- Expand the archived section.
- Use the stop-response control during an active turn.

## Variant Matrix

| Dimension | Variants |
| --- | --- |
| Operation | open, rename, edit, fork, copy, pin, archive, unarchive, stop |
| Source | sidebar context menu, title action, message action, archived section |
| Chat state | normal, pinned, archived, active turn, long transcript |
| Validation | visual only, fake mutation, host clipboard |

## Steps

1. Open a fixture chat from the sidebar.
2. Confirm the visible transcript matches the selected row.
3. Rename the chat with a public fixture title.
4. Confirm the title and row update.
5. Pin the chat and confirm it appears in the pinned section.
6. Unpin the chat and confirm the pinned state clears.
7. Archive the chat and confirm it leaves the normal list.
8. Open the archived section and unarchive the chat.
9. Confirm the chat returns to the normal list.

Alternate passes:

1. Edit a prior user message and verify the edited text appears without changing unrelated messages.
2. Fork a conversation and verify a new related chat opens with a fork banner or equivalent relation.
3. Copy a response or code block and verify the visible copied feedback appears.
4. Stop an active fake turn and verify the stop button returns to send.
5. Scroll deep in a transcript, switch away, return, and verify scroll restoration behavior.

## Expected Results

- Lifecycle changes are visible immediately in the relevant surface.
- The selected chat does not unexpectedly change except for archive flows that return home.
- Archived and pinned sections stay internally consistent.
- Message-level actions show visible feedback.
- Scroll position behavior is stable and intentional.

## Failure Signals

- Rename updates only the header or only the sidebar, not both.
- Pin/unpin creates duplicate sidebar rows.
- Archive hides a chat permanently with no archived access.
- Edit or fork changes the wrong chat.
- Stop response leaves the UI in active-turn state.
- Copy feedback appears without copying, or no feedback appears.

## Screenshot Checklist

- Selected existing chat before mutation.
- Rename sheet or renamed state.
- Pinned state.
- Archived section with the chat present.
- Edited message or forked conversation state.
- Active turn before and after stop.

## Notes for Future Automation

- Use stable fixture IDs for chats so automation can detect duplicates.
- Clipboard verification should use a known public fixture string.
- Archive tests must distinguish local dummy behavior from real runtime sync.
