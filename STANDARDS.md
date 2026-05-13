# Standards

Companion to `CONSTITUTION.md` and `STYLE.md`. The constitution declares
what the project is. `STYLE.md` declares how it looks. This document
declares what must be **true** about the product for a release to be
considered correct.

It is the end-to-end audit, expressed in words. Every rule is checkable
in isolation. An agent or a contributor can use this document as a
release-readiness sweep: pick a section, verify each check on the build,
file the deltas as bugs.

The standards evolve. The constitutional requirement that the product is
correct does not. When this document and code disagree, code is debt.
Exceptions are named with their reason; silent deviations are bugs.

## 0. How to use this document

- Every section follows the pattern **The rule. (one declarative
  sentence)** followed by **checks** as bullets.
- `[macOS]`, `[iOS]`, `[Web]`, `[CLI]` tag platform-specific checks.
  Unmarked rules apply to every surface that ships.
- Numbers (sizes, durations, fields) live in `STYLE.md`. This document
  refers to them by name. When `STANDARDS.md` mentions "the dropdown
  recipe", that recipe is in `STYLE.md §6.3`.
- A check is **auditable** if a contributor can produce a yes/no answer
  by running the app or grepping the source. Anything subjective ("feels
  good") belongs to `STYLE.md`, not here.
- **Exceptions** must be named at the call site (`// STANDARDS-exempt:
  <reason>`) and survive review.

## 1. Functionality: every control acts

**The rule.** Every visible interactive control performs a real action
or is in a deliberate, visible disabled state. No dead controls. No
"soon" placeholders shipped to release.

- Every `Button`, `Link`, `Toggle`, `Picker`, segmented control, slider,
  context menu item, menu bar item, sheet primary button, sheet cancel
  button and chat inline action triggers a code path that mutates state,
  navigates, or invokes a side effect.
- A control that cannot act in the current state is rendered with the
  disabled state from `STYLE.md` (opacity 0.40, no hover response) and
  has an `accessibilityLabel` explaining why (see §5).
- A control whose target is "not implemented yet" is **not visible** in
  release builds. Build it behind a feature flag (see §16) or do not
  ship it.
- A control that opens a sheet, modal, popover or new view returns the
  user to a usable state on close. No close path leaves the app on a
  blank screen.
- A control that streams (send prompt, run command, sync) shows progress
  via the streaming patterns in `STYLE.md §7.4`. Silence during a
  multi-second operation is a bug.

## 2. Localization

**The rule.** Every user-facing string is keyed in the catalog and
rendered through the localization helpers. No hardcoded English ships.

- `[macOS]` Strings flow through `L10n.t(_:)` or a `LocalizedStringKey`
  literal into `Text(...)`. Source: `Localizable.xcstrings`.
- `[iOS]` Same: catalog-backed, no inline string literals in views.
- Supported locales today: `en, de, es, fr, it, ja, ko, pt-BR, ru,
  zh-Hans`. A release tag with `(needs review)` entries in the catalog
  is a release bug; resolve before tagging.
- Plurals route through `.stringsdict`. `if count == 1 { "1 chat" } else
  { "\(count) chats" }` in view code is a bug.
- Dates, numbers and durations format through `Formatter` instances
  bound to `AppLocale.current`. Hand-built `"\(count) min"`-style
  strings break for locales with different unit placement.
- `accessibilityLabel(...)` strings are localized too (see §5).
- Strings inside `#if DEBUG` panels are exempt and carry `// L10n-exempt:
  dev-only` at the declaration site.
- A new locale joins by adding its directory under `Resources/<locale>.lproj/`
  and translating every key; partial locales (some keys missing) are not
  shipped.

## 3. Accessibility

**The rule.** Every interactive control is reachable and identifiable by
assistive tech. The app is operable from the keyboard alone.

- Every `Button`, `Toggle`, `Picker`, slider, segmented control, sheet
  trigger, sidebar row and chat inline action declares
  `accessibilityLabel(L10n.t(...))`.
- Decorative shapes, icons and dividers are tagged
  `.accessibilityHidden(true)` so VoiceOver does not narrate visual
  filler.
- Composite controls (icon + label, label + badge) collapse into a
  single accessibility element with `.accessibilityElement(children:
  .combine)` so VoiceOver reads one coherent string per control.
- VoiceOver traversal order matches the visual reading order
  top-to-bottom, leading-to-trailing on every screen.
- Color is never the only signal: error, success, unread and selected
  states pair color with a glyph, weight, position, or text difference.
- Contrast: body text on background and label-on-button surfaces meet
  WCAG AA (4.5:1 for body, 3:1 for large text). When `STYLE.md` values
  approach the line, the higher-contrast token is the one in use.
- `[iOS]` Touch targets ≥ 44 pt × 44 pt.
- `[macOS]` Click targets ≥ 24 pt × 24 pt; ≥ 28 pt in floating chrome.

## 4. Keyboard and focus

**The rule.** Every primary action is reachable from the keyboard. The
focused element is always visible.

- Every primary, recurring action has a documented keyboard shortcut.
  The list is browsable from the command palette (`CMD-K` `[macOS]`).
- `[macOS]` System shortcuts (`⌘N`, `⌘W`, `⌘,`, `⌘F`, `⌘K`, `⌘\`) behave
  per Apple HIG: New, Close, Settings, Find, Command palette, Toggle
  sidebar.
- User-configurable shortcuts go through the `KeyboardShortcuts`
  framework + `KeyboardShortcutsRow`; conflicts are surfaced to the user
  on the same screen, not silently ignored.
- Focused element shows a clear focus state per `STYLE.md §6.6` (ring or
  border, never the bright system ring on dark surfaces).
- `Tab` cycles forward through interactive controls in visual order;
  `Shift-Tab` reverses. No control is skipped without a documented
  reason (`STANDARDS-exempt`).
- `Esc` closes the topmost modal / sheet / overlay; the document under
  it is unchanged. If no overlay is open, `Esc` clears the focused text
  field or active selection.
- `Return` submits the focused form when there is a primary button;
  `⌘Return` triggers the primary chat action (send). The composer keeps
  newline on plain `Return` (it is a multi-line editor); `⌘Return` is
  the send affordance.
- A control that gains focus on a text input gets caret + keyboard
  attached within 100 ms.

## 5. Empty, loading, error states

**The rule.** Every screen that can hold zero items, take time, or fail
covers all three states explicitly. The user never sees a blank
container.

- A screen that can be empty renders an empty state with copy + icon +
  optional primary action (e.g. "Create the first chat"). The empty
  state is keyed in the catalog.
- A screen that can be loading renders a state machine view, not a
  global spinner. Long-running phases past 300 ms get the skeleton /
  shimmer treatment per `STYLE.md`.
- A screen that can fail renders an error state with: a human one-line
  cause, a recoverable action (retry, cancel, open settings), and, if
  the error is structured, a "show details" disclosure. Errors are
  localized.
- No state is allowed to be invisible. A request that fails and silently
  resets the screen to empty is a bug.
- "Connection lost" surfaces are part of this contract: the app
  communicates loss of the daemon bridge, of network, of an external
  adapter (see §10), and how to recover.

## 6. Navigation and flow

**The rule.** Forward and back work everywhere. No screen is a dead end.

- Every sheet, modal, full-screen takeover has a close affordance
  reachable by mouse (tap-outside or close button), keyboard (`Esc`),
  and `[iOS]` swipe-down on a non-scrollable region.
- Deep links / URL schemes open the target view directly; if the user
  is not authenticated, the app routes through sign-in and then back to
  the target, preserving the deep link.
- Multi-step flows expose progress (1 of 3, 2 of 3, 3 of 3) and a back
  step that does not lose entered data.
- A modal that opens another modal stacks predictably and unwinds in
  reverse order on `Esc`.
- Closing the last chat or the last project in a workspace navigates to
  the workspace's empty state (§5), not to a crash, not to nothing.

## 7. State persistence

**The rule.** Choices the user made survive a relaunch.

- Window size, position and sidebar width persist across relaunches
  `[macOS]`. Window is restored on the same display when possible.
- The last selected chat, project, sub-app surface and tab are restored
  on relaunch. The user does not land in an unfamiliar default view.
- Scroll position in long surfaces (chat history, sidebar) restores when
  the user returns to that surface in the same session.
- Settings (every toggle, every dropdown, every segmented choice)
  persist via `@AppStorage` with keys prefixed
  `clawix.<area>.<setting>`. A "Reset to defaults" surface exists for
  every settings page.
- Feature flag values do not persist across release builds (compile-time
  guards make them unreachable, see §16).
- Sensitive data (auth tokens, pairing bearers) persists where the
  platform mandates (Keychain `[macOS]/[iOS]`, `~/Library/Preferences`
  for non-secret bearers documented in `CLAUDE.md`).

## 8. Forms and inputs

**The rule.** Every form tells the user what it expects, validates as
they type, and submits only when valid.

- Each input has a visible label (or a placeholder that disappears on
  focus and a floating label when content is present).
- Validation is inline. Required fields show their required state; bad
  formats highlight on blur, not only on submit.
- The submit button is disabled while the form is invalid and renders
  the disabled state (§1). A user who tries to submit an invalid form
  receives the first error inline, not a modal alert.
- Errors from the backend that reach the form (server validation,
  duplicate name) render in the same inline location as client-side
  errors, in the same style.
- A successful submit leaves the user on a usable state (the next step
  of the flow, or the same form with a "Saved" inline confirmation).
- Destructive forms (delete project, sign out, reset) require an
  explicit confirmation via `ConfirmationDialog` (`STYLE.md §6`) with a
  named recovery affordance ("Undo" within N seconds, archived not
  deleted, etc.).
- Pasting respects the field: pasting multi-line text into a single-line
  field collapses to one line (no scroll explosion); pasting a URL into
  a URL field validates immediately.

## 9. Selection, hover, focus, pressed, disabled

**The rule.** The user can always tell which control they are about to
act on and what state it is in.

- Five states render distinctly on every interactive surface: **idle**,
  **hover** `[macOS]/[Web]` or **highlighted** `[iOS]`, **focused**,
  **pressed**, **disabled**. Values come from `STYLE.md §6.6`.
- Selection is a separate state from hover and renders accordingly
  (sidebar row selected, segmented option active, list item picked).
  Selection survives loss of hover.
- Drop targets render an additional **hover-during-drag** state during
  a drag operation that could land here (§11).
- A control whose action is in progress (sending, saving) is briefly
  busy: input disabled, a small inline progress glyph in the same row.
  Busy state has a timeout; if the action takes > 5 s, escalate to a
  loading screen state (§5).

## 10. Network, bridge, adapters

**The rule.** Connectivity loss is rendered, not hidden. Reconnection
works without a relaunch.

- Loss of the local bridge daemon (`clawix-bridge`) is rendered
  prominently: the user sees that the daemon is down and a one-click
  restart action.
- Loss of network on a surface that needs it (sign-in, model
  inference, sync) renders an offline notice with the actions still
  available offline (read history, edit drafts) preserved.
- Reconnection: a successful reconnect transparently resumes the
  surface; the offline notice clears, an in-progress send retries.
- An external adapter (web view, simulator session, paired iOS device)
  that drops re-attempts on a backoff schedule. The UI shows the
  current connection state and the next retry time.
- A long-running operation that completes while the user is on a
  different surface surfaces a non-modal notice (badge, toast,
  notification) so the user can return when ready.
- The pairing flow (QR code, bearer token) is robust against
  re-pairings: re-installing the app does not strand the paired iOS
  device.

## 11. Drag and drop

**The rule.** Every drop target visibly accepts what it can and
visibly rejects what it cannot.

- A surface that accepts file drops, text drops or image drops renders
  the drop affordance (the `BodyDropOverlay` pattern from `STYLE.md`)
  as soon as a compatible drag enters the window.
- A drop with an incompatible payload shows a "not allowed" cursor or
  an inline "not supported here" hint; it never silently fails.
- Drag-to-reorder lists (sidebar chats, project items, attachments)
  use a drag handle that is visible on hover and reachable from the
  keyboard via a "Move up / Move down" menu or shortcut. A reorder is
  undoable with `⌘Z` `[macOS]`.
- Drag operations outside the canonical list reorder, sheet dismiss,
  attachment add and image preview drag are not invented for
  decoration. A drag interaction with no functional value is a bug.
- A drop on a chat composer that the user did not intend (an accidental
  miss) is undoable by clearing the attachment immediately, not by
  restarting the composer.

## 12. Long content

**The rule.** The app degrades gracefully on long values and large
collections.

- Single-line fields (chat titles, project names, contact names)
  truncate with ellipsis at the trailing edge. Truncated values reveal
  on hover via `HoverHint` (`STYLE.md`) showing the full value.
- Multi-line content (chat messages, descriptions, instructions) wraps;
  it never extends past the container.
- Lists with > 30 items use `LazyVStack` / `LazyVGrid` and lazy chat
  history loading. A user can scroll a 1 000-message chat without frame
  drops.
- Tables / grids with very wide content allow horizontal scroll inside
  the cell or expose a detail view; the surrounding chrome does not
  scroll horizontally.
- Empty very-long fields render a placeholder, not collapse to height
  zero (see §5).

## 13. Concurrency and multi-window

**The rule.** Multiple windows of the same app see consistent state.

- `[macOS]` Two windows on the same Mac (a second window, a popped-out
  chat) share the same chat list, project list, settings and
  pairing state.
- Edits in one window appear in others without a manual refresh
  (typically via the in-app event bus that drives the local bridge).
- A modal that mutates global state (renaming a chat, deleting a
  project) updates all windows in the same tick; no window is left on
  stale data.
- `[iOS]` Split View / multi-instance support is not required today; if
  introduced, it follows this rule.
- Two devices paired to the same daemon (Mac + iPhone) observe the
  same source of truth (see §10).

## 14. Standard system actions

**The rule.** Every place a user can type, the platform's standard
editing actions work.

- `⌘C` / `⌘V` / `⌘X` / `⌘A` / `⌘Z` / `⌘⇧Z` / `⌘F` work in every text
  context `[macOS]`. Equivalents work `[iOS]` (long-press, swipe-back
  for undo where the user has enabled it).
- Right-click / two-finger tap on text yields the system menu with Cut,
  Copy, Paste, Look Up, Translate where the platform provides it.
- Spell check, grammar check and the dictation surfaces are not
  suppressed unless the field is a code / key / token input.
- Find within a chat (`⌘F`) finds across the visible thread; the find
  bar is the canonical `FindBarView`, not a custom per-screen one.
- Drag-to-select text in chat messages works and copies the selected
  range to the clipboard on `⌘C`. Selection across messages joins with
  a newline.

## 15. Microcopy of errors and confirmations

**The rule.** Every error and every confirmation reads as a human
sentence the user can act on.

- An error is one sentence in plain language. It names what failed and
  what the user can do. "Couldn't send the message. Check your
  connection and try again." Not "Error: RPC failed (-32601)".
- A technical detail (status code, exception type) is hidden behind a
  "Show details" disclosure for the rare user who needs it.
- Confirmations of destructive actions name the entity being acted on.
  "Delete project «Q4 launch»? Items in this project will be archived
  for 30 days." Not "Are you sure?".
- Success states are quiet by default (an inline "Saved", a subtle
  state change). A modal "Success!" alert is a bug.
- Past-tense verbs for completed actions ("Sent", "Archived"),
  present-tense for in-progress ("Sending…", "Archiving…"). Verb
  consistency across the app.

## 16. Release readiness (debug, feature flags, defaults)

**The rule.** A release build ships only stable surfaces. Dev-only
surfaces are unreachable.

- `[macOS]` `swift build -c release` and the notarization path produce a
  binary where every `#if DEBUG` panel is absent. The "Feature previews"
  card in Settings → General is not rendered.
- `FeatureFlags.beta` and `FeatureFlags.experimental` evaluate to
  `false` at runtime in release. There is no environment variable,
  defaults key, plist value or launch argument that turns them on.
- Settings reset to ship defaults in a freshly installed release build.
  A stale value persisted from an earlier dev build of the same flag
  does not leak.
- Logs in a release build do not print developer paths, prompts, agent
  outputs at info level, or other content the user did not ask to see.
- The bundled help / about / settings surfaces show the marketing
  version read from `AppVersion`, not a hardcoded string.

## 17. Public hygiene at runtime

**The rule.** Nothing the maintainer keeps private appears in the
running app's UI, logs or shipped resources.

- No codesign identity, Apple Team ID, real bundle id or SKU is
  visible in any settings page, about screen, log line, error message
  or shipped string.
- The hygiene check (`macos/scripts/public_hygiene_check.sh`) passes on
  every release tag.
- Debug-only logs that print internal markers, rename markers, or
  scaffolding language are stripped from the release binary.
- Brand mentions in UI follow `TRADEMARKS.md`; competitive product
  names are not present in the shipping copy.

## 18. Crash safety and silent failure

**The rule.** A user action never causes a crash. A failure never
disappears without trace.

- Force-unwraps (`!`) are absent from any user-driven code path. A
  contract failure surfaces as an error state (§5), not a fatal.
- A thrown error or a rejected promise that reaches the UI is rendered
  per §15 and logged at warn or error level.
- Background tasks that fail (sync, indexing, prefetch) surface their
  failure on the surface that depends on them; they do not retry
  silently forever.
- A panic in the local bridge daemon is reported to the user with a
  one-click restart action; the daemon is not left dead and silent
  (see §10).

## 19. Performance budget

**The rule.** Common interactions feel instant. Long ones report
progress.

- A keystroke in the composer renders within one frame budget (16 ms
  at 60 Hz; 8 ms at 120 Hz `[iOS]`).
- Opening a chat with up to 1 000 messages renders to first content
  inside 500 ms on the reference dev machine; subsequent scrolls
  maintain 60 fps.
- Sidebar with up to 200 chats scrolls at 60 fps and updates a single
  row's metadata (unread dot, time, title) without a full list
  rebuild.
- Settings pages and dropdowns open in under 200 ms.
- Any operation that breaks these budgets is investigated with a
  `PerfSignpost` capture (see `STYLE.md §11`) before being mitigated.

## 20. Coverage of canonical types and adapters

**The rule.** Every canonical data type has a canonical rendering on
every surface that ships it.

- Each canonical type defined by `ClawJS` (`Chat`, `Project`, etc.)
  has: a card form, a list row form, an inline chat-message form, a
  detail-view form. Each follows `STYLE.md §6.7`.
- Each adapter that the app integrates (web view, simulator, paired
  device, external messaging surface) has a known connected /
  disconnected / failed rendering and is covered by §10.
- A new canonical type does not ship until at least the card, the
  inline form and the empty / loading / error states are covered.
- A new adapter does not ship until §10 covers it.

## 21. Updates and install paths

**The rule.** Updates install cleanly. Reinstalls do not strand state.

- `[macOS]` Sparkle in-app updates download the signed DMG, verify the
  EdDSA signature against the appcast public key, and replace the app
  on next relaunch. A failed update does not corrupt the installed
  app.
- `[CLI]` `npm install -g clawix` postinstall verifies SHA-256 against
  `lib/checksums.json` and codesign-verifies the unpacked binaries.
  A user with the GUI installed coexists with the CLI per
  `CLAUDE.md`.
- `clawix uninstall` and `clawix uninstall --purge` leave a clean
  state on disk; nothing in `~/.clawix/bin/` survives.
- After an update, sign-in, pairing and the user's chats survive
  without re-pairing.

## 22. The release sweep

**The rule.** Before tagging a release, an agent or contributor runs
this document section by section against the build and reports the
results. The release proceeds when each section is either green or has
a named, accepted exception.

- A "release sweep" report exists for every shipped version. The
  shape of the report:
  - One line per section: `§N <Topic>: pass | fail (link to issue)`.
  - Failures link to a tracked issue with the file and line, plus a
    proposed fix or an explicit "ship with this known regression"
    decision.
- The sweep is platform-aware: `[macOS]`, `[iOS]`, `[CLI]`, `[Web]`
  each get their own line per section when the section applies.
- A failure does not block in itself; it must be either fixed or
  accepted explicitly by the maintainer. Silent failures are bugs.

## 23. Open standards (not yet enforced)

These belong to the document but the implementation is partial today.
They live here so contributors know the destination.

- **Light mode**: not implemented. `STYLE.md §2.4` defines the
  derivation. When light mode lands, every section that names a state
  is verified in both modes.
- **RTL layout**: not implemented. When a right-to-left locale joins
  the catalog (Arabic, Hebrew), every `HStack`, chevron, and trailing
  edge gets audited against `Locale.current.layoutDirection`.
- **Automated lints for §1 (dead controls), §3 (a11y labels), §5
  (state coverage)**: today these are reviewed by hand. Lints are
  open work; the rules apply by convention until the lints ship.
- **Concurrency model for two paired devices on the same daemon**
  (§13): the bridge protocol is the host of truth; UI synchronization
  refinements are open work.
