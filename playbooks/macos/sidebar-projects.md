---
id: macos.sidebar.projects
platform: macos
surface: sidebar
status: ready
intent: "Validate sidebar organization, pinned and archived sections, project grouping, project actions, filters, and drag-and-drop reassignment."
entrypoints:
  - sidebar
  - organize-menu
  - project-row-menu
  - pinned-section
  - archived-section
  - drag-and-drop
variants:
  - grouped-view
  - chronological-view
  - project-sort-recent
  - project-sort-name
  - project-sort-custom
  - project-expand-collapse
  - show-more
  - view-all
  - create-rename-delete-project
  - drag-chat-to-project
  - pinned-filter
  - archived-browse
required_state:
  app_mode: dummy
  data: fixture set with multiple projects, projectless chats, pinned chats, and archived chats
  backend: fake or intercepted for project and archive mutations
  window: main macOS app window visible and focused
safety:
  default: isolated
  requires_explicit_confirmation:
    - real workspace root creation
    - real project sync to external state
    - destructive project deletion affecting real data
execution_mode:
  hermetic: required for list organization and fake mutations
  host: required for drag-and-drop and file/folder picker flows
artifacts:
  - sidebar screenshot for each organization mode
  - before and after screenshot for drag or project mutation
assertions:
  - sections expand and collapse without losing rows
  - project sort mode changes visible order
  - pinned and archived states are visually distinct
  - chat reassignment moves the row to the expected project
known_risks:
  - real workspace labels can come from external state
  - custom ordering is sensitive to drag target precision
  - archived runtime sync may lag behind local UI
---

## Goal

Verify that the sidebar helps users find, group, reorder, filter, and manage conversations across projects without row duplication or lost state.

## Invariants

- Pinned chats are visible in the pinned section when enabled.
- Archived chats are hidden from normal sections and visible in archived browsing.
- Grouped and chronological modes preserve chat selection.
- Project expand/collapse must not change chat assignment.
- Dragging a chat into a project must visibly move it and remove incompatible pinned placement when appropriate.
- Project deletion in isolated mode must not touch real workspace folders.

## Setup

- Launch with fixture data containing at least three projects.
- Include projectless, pinned, archived, and recent chats.
- Use dummy mode and fake persistence.
- Use synthetic project names and local temporary paths only.

## Entry Points

- Open the sidebar organize menu.
- Expand and collapse project rows.
- Use project row actions.
- Use pinned and archived section actions.
- Drag fixture chat rows between sections where supported.

## Variant Matrix

| Dimension | Variants |
| --- | --- |
| Layout | grouped, chronological |
| Sort | recent, creation, name, custom |
| Section | pinned, projects, no project, archived, tools |
| Project action | create, rename, delete, new chat, view all |
| Drag | chat to project, chat to no-project bucket, project reorder |
| Filter | pinned project filter, chronological project filter |

## Steps

1. Start in grouped mode.
2. Confirm projects, pinned chats, projectless chats, and archived entry points are visible as expected.
3. Expand and collapse a project.
4. Use Show more and View all on a project with enough chats.
5. Switch to chronological mode and confirm chats remain visible in recency order.
6. Switch project sorting and confirm project order changes.
7. Pin and unpin a fixture chat.
8. Archive and unarchive a fixture chat.

Alternate passes:

1. Create a synthetic project, rename it, then delete it in isolated mode.
2. Drag a chat into a project and confirm it moves.
3. Reorder projects in custom sort mode.
4. Apply pinned or chronological project filters and verify hidden projects are excluded without deleting data.

## Expected Results

- Sidebar rows remain readable and do not overlap controls.
- Organization changes are immediate and reversible.
- Project actions update visible labels and grouping.
- Drag-and-drop produces a visible before/after change.
- Archive and pin state remain visually distinct.
- Selected chat behavior remains predictable after organization changes.

## Failure Signals

- Rows duplicate after mode or sort changes.
- Project expansion loses row selection.
- Dragging a chat produces no visible change.
- Project deletion touches real files or external state.
- Filters hide every row without a visible explanation.
- Archived chats remain in normal lists.

## Screenshot Checklist

- Grouped sidebar with projects.
- Chronological sidebar.
- Organize menu open.
- Project expanded with Show more or View all.
- Pinned section before and after a pin change.
- Archived section before and after unarchive.
- Drag-and-drop before and after state in host mode.

## Notes for Future Automation

- Fixture data should contain enough chats to exercise overflow and Show more behavior.
- Sort assertions should compare visible row order by public fixture names.
- Drag automation needs host validation; hermetic mode can only validate resulting state.
