---
id: macos.search.navigation
platform: macos
surface: navigation
status: ready
priority: P1
tags:
  - regression
  - dummy
  - host
  - search
  - navigation
  - browser
intent: "Validate global search, project-scoped search, in-chat find, command palette navigation, browser route navigation, and settings route navigation."
entrypoints:
  - command-palette
  - search-shortcut
  - sidebar-view-all
  - in-chat-find
  - browser-menu
  - settings-sidebar
variants:
  - global-chat-search
  - project-scoped-search
  - no-results
  - in-chat-find-hit
  - in-chat-find-miss
  - command-palette-route
  - browser-new-tab
  - settings-route
required_state:
  app_mode: dummy
  data: fixture chats with searchable titles, previews, transcript text, and project grouping
  backend: fake or local fixture search
  window: main macOS app window visible and focused
safety:
  level: safe_dummy
  default: isolated
  requires_explicit_confirmation:
    - external browser navigation to non-local URLs
    - real backend search over private conversations
execution_mode:
  hermetic: required for fixture search and route navigation
  host: required for keyboard shortcuts, menu focus, and embedded browser rendering
artifacts:
  - search results screenshot
  - no-results screenshot
  - command palette screenshot
  - browser route screenshot
  - settings route screenshot
assertions:
  - search query is visible
  - matching result rows are visible
  - scoped search clearly identifies scope
  - command palette selection routes to the expected surface
  - browser and settings routes render without blank content
known_risks:
  - browser pages can load asynchronously
  - keyboard shortcuts depend on focused app
  - real search may include private user data
---

## Goal

Verify that users can move through the app and find conversations using global search, scoped search, in-chat find, command palette actions, browser navigation, and settings navigation.

## Invariants

- Search must not expose private real data in default playbook execution.
- Global search must show matching fixture chats.
- Scoped search must visibly communicate the project scope.
- In-chat find must highlight or navigate between matches inside the active transcript.
- Command palette navigation must close the palette after routing.
- Browser and settings routes must not render blank states.

## Setup

- Launch in dummy mode with fixture chats and projects.
- Include at least one query that returns multiple matches and one query that returns none.
- Include one chat transcript with repeated text for in-chat find.
- Use local or blank browser pages by default.

## Entry Points

- Use the global search shortcut or search command.
- Use a project row View all action.
- Use in-chat find from a chat.
- Open the command palette and choose route actions.
- Use browser menu commands.
- Open Settings and select pages from the settings sidebar.

## Variant Matrix

| Dimension | Variants |
| --- | --- |
| Search type | global, project-scoped, in-chat |
| Result state | multiple results, single result, no results |
| Route | chat, search, project, settings, browser |
| Trigger | keyboard, command palette, visible button, menu |
| Browser | blank tab, local URL, blocked external URL without confirmation |

## Critical Cases

- `P1-global-search`: fixture query returns matching chats and opens selected result.
- `P1-project-scoped-search`: project scope is visible and filters results.
- `P1-command-palette-route`: command palette routes and closes.
- `P2-browser-local`: browser route renders chrome with blank or local content.

## Steps

1. Open global search.
2. Enter a fixture query with known matches.
3. Confirm matching results appear.
4. Select a result and confirm the matching chat opens.
5. Open project-scoped search through View all.
6. Confirm the scope is visible and results are limited to the project.
7. Search for a no-results fixture query and confirm an empty state appears.

Alternate passes:

1. Open an existing chat and use in-chat find for a repeated term.
2. Open the command palette and route to Search, Settings, and New chat.
3. Open a browser tab with a local or blank page and confirm browser chrome renders.
4. Navigate to at least two settings pages and confirm content changes.

## Expected Results

- Search input is focused when search opens.
- Results update for fixture queries.
- No-results state is explicit and not blank.
- Selecting a result routes to the expected chat.
- Scoped search displays scope and can clear or exit scope.
- Command palette closes after action.
- Browser chrome and settings pages render visible content.

## Failure Signals

- Search opens without focus.
- Results are stale from a previous query.
- Scoped search leaks results from another project.
- No-results state is blank or misleading.
- Command palette routes incorrectly or remains stuck.
- Browser route opens an external URL without confirmation.

## Evidence Checklist

| Check | Result |
| --- | --- |
| Global search results verified | pass/fail/no-run |
| Project-scoped search verified | pass/fail/no-run |
| No-results state verified | pass/fail/no-run |
| In-chat find checked or marked no-run | pass/fail/no-run |
| Browser route stayed local or blank | pass/fail/no-run |
| Required screenshots captured | pass/fail/no-run |

## Screenshot Checklist

- Global search with results.
- Project-scoped search with scope visible.
- No-results state.
- In-chat find with a hit.
- Command palette with route action highlighted.
- Browser route with local or blank content.
- Settings route after navigation.

## Notes for Future Automation

- Use deterministic fixture query strings.
- Do not assert private real chat content.
- Browser checks should distinguish chrome rendering from page network success.
