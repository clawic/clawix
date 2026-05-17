# Style

Companion to `CONSTITUTION.md`. The constitution declares that the project
has a canonical visual language and that all UI conforms to it. This document
is that language.

The style guide evolves. The constitutional requirement that all UI conforms
to it does not. When this document and code disagree, code that is recent and
curated takes precedence over old code; old code is technical debt to be
brought in line. When this document is silent, derive from the principles in
the curated zones (see section 0).

## 0. Source of truth

The curated zones today, in order of authority:

1. **Sidebar** (`macos/Sources/Clawix/SidebarView.swift`). Hovers, sections,
   custom icons, hover colors, curves, sizes, type. This is the closest
   expression of the target style.
2. **Dropdowns** (`ComposerView.swift` `ModelMenuPopup`, slash menu,
   sidebar context menus, settings dropdowns via `ContentView.swift`
   `MenuStyle`). The most thoroughly tuned surface in the app.
3. **Composer** (`ComposerView.swift`).
4. **Chat surface** (`ChatView.swift`), with the caveat that bubble and
   markdown rendering are not yet at canon level.
5. **ThinScroller** (`ThinScrollbar.swift`). The only acceptable scroller in
   the app.
6. **SlidingSegmented** (`SettingsView.swift`). The only acceptable 2-N
   selector. Inside Settings, this component is canon; the rest of Settings
   is not.

Anything outside these zones either inherits from them or is open work
(section 13).

Machine-readable interface governance lives in `docs/ui/`. When a surface maps
to a pattern, debt item, protected surface, or exception, the registry and
manifests there are the auditable contract for states, geometry, copy,
validation, and visual mutation permissions. This document remains the prose
visual canon; `docs/ui/` is the enforceable registry layer agents and checks
must consult.

## 1. Foundations

- **Squircle is universal.** Every rounded corner uses
  `RoundedRectangle(cornerRadius:_, style: .continuous)` or
  `Capsule()` (which is `.continuous` by construction). `.cornerRadius()` is
  banned. `style: .circular` is banned. Custom paths with rounded corners
  must use `.continuous`. The squircle lint enforces this on every build
  (`macos/scripts/dev.sh`, `ios/scripts/squircle_lint.sh`).
- **Dark today, light is parity work.** All current canonical values are the
  dark-mode values. Light mode is a debt the design system carries: when a
  rule below names a value (e.g. `white(0.14)` for card fill), the parallel
  light value must be derived to produce the same perceptual function (a
  subtle elevation, a soft hover lift). Tokens are declared semantic
  (`Palette.cardFill`), never raw, so that a light branch can plug in.
- **Cross-platform: semantic parity, native execution.** macOS and iOS share
  semantic tokens (`background`, `surface`, `cardFill`, `textPrimary`,
  `brand`) and the same brand and the same iconography. They diverge in
  concrete materials (Liquid Glass on iOS, `NSVisualEffectView` on macOS)
  and in fonts where each OS reads better. Android, when it lands, follows
  the same semantic mapping.

## 2. Color

### 2.1 macOS palette (dark, canonical)

Defined in `macos/Sources/Clawix/ContentView.swift` `Palette` (~lines
1919–1944).

| Token | Value | Use |
|---|---|---|
| `background` | `Color(white: 0.04)` | App canvas. |
| `sidebar` | `Color(white: 0.245)` | Sidebar column. |
| `cardFill` | `Color(white: 0.14)` | Cards, popovers, composer body. |
| `cardHover` | `Color(white: 0.17)` | Card hover state. |
| `border` | `Color(white: 0.20)` | Card and dialog borders. |
| `borderSubtle` | `Color(white: 0.15)` | Inner dividers. |
| `popupStroke` | `Color.white.opacity(0.10)` | Popup hairline. |
| `textPrimary` | `Color.white` | Body text on dark. |
| `textSecondary` | `Color(white: 0.55)` | Meta, captions. |
| `pastelBlue` | `Color(red: 0.45, green: 0.65, blue: 1.0)` | Brand accent. |

### 2.2 iOS palette (dark, canonical)

Defined in `ios/Sources/Clawix/Theme/DesignTokens.swift`.

| Token | Value | Use |
|---|---|---|
| `background` | `Color.black` | App canvas. |
| `surface` | `Color(white: 0.10)` | Sheets and surfaces. |
| `cardFill` | `Color.white.opacity(0.06)` | Cards on dark. |
| `cardHover` | `Color.white.opacity(0.10)` | Card hover state. |
| `textPrimary` | `Color.white` | Body text. |
| `textSecondary` | `Color(white: 0.65)` | Meta. |
| `textTertiary` | `Color(white: 0.45)` | Disabled / hint. |
| `pastelBlue` | `Color(red: 0.45, green: 0.65, blue: 1.0)` | Brand accent (shared). |

### 2.3 Brand color (`pastelBlue`)

The brand color is reserved for **points of focus and identity**, never for
filling large action surfaces.

Allowed today: unread dots, focus rings, links, the active state of an
indicator, agent-authored content markers (when content is identifiably
produced by an agent), brand glyphs in onboarding. The total brand-coverage
on any given screen approximates the "1 percent" rule: a few small accents
per view, not a filled button or a filled hero.

Banned today: primary CTA button fill, sidebar selection background, large
hero blocks. Primary buttons use neutral fills (see section 6.6).

### 2.4 Light mode derivation (open work)

When a light mode is implemented, derive values from the dark palette to
preserve perceptual function:

- `background` (light) is a near-white (≈`white: 0.985`), not pure white.
- `cardFill` (light) is a small subtraction from `background` (≈`white:
  0.95`), giving a subtle elevation; `cardHover` is a slightly stronger
  subtraction.
- `textPrimary` (light) is near-black, never pure black (≈`white: 0.12`).
- `textSecondary` (light) follows the same alpha logic against light.
- `popupStroke` uses near-black at the same alpha (`black.opacity(0.10)`).
- `pastelBlue` stays the same value on both modes (brand consistency).
- Materials translate: `NSVisualEffectView` switches to light variants;
  Liquid Glass adapts via `.regular`.

The semantic map is identical; only the raw values differ.

## 3. Typography

### 3.1 Families

- **Manrope** is the primary family on macOS and iOS for body and most UI
  text. It ships in the bundle as a variable font.
- **PlusJakartaSans** is used on iOS for some headlines today. This is
  legacy; if forced to choose, prefer Manrope across both platforms for
  unified rhythm. New surfaces use Manrope.
- **Monospace** is reserved for code, terminal output, and pairing codes.
  System default (`.system(.body, design: .monospaced)`). Never used for
  microcopy, labels, or section headings.

### 3.2 Hierarchy (iOS canonical, macOS follows semantic)

From `ios/Sources/Clawix/Theme/DesignTokens.swift`:

| Role | Size | Weight | Use |
|---|---|---|---|
| `titleFont` | 22 | semibold | Top of page, sheet titles. |
| `chatBodyFont` | 16.5 | regular | Chat message body. |
| `bodyFont` | 16 | regular | Default body. |
| `bodyEmphasized` | 16 | medium | Body emphasis. |
| `secondaryFont` | 14 | regular | Captions, meta. |
| `captionFont` | 12 | regular | Smallest reading text. |
| `monoFont` | 14 | regular monospaced | Code inline. |

macOS uses denser sizes for desktop reading. Dropdown rows: 11.5 pt regular,
color `white(0.94)` (`ComposerView.swift`). Sidebar section headers: 13.5 pt,
weight 500 (`SidebarView.swift`). Sidebar rows: ~13.5 pt regular.

### 3.3 Microcopy and labels

- **No all-caps.** Sub-labels, section dividers, chip categories, taglines,
  meta strings: sentence or title case, never `text-transform: uppercase`,
  never wide tracking. Differentiate microcopy from primary labels with
  lighter weight and smaller size, not with a different case or family.
- **No editorial / magazine framing.** No numbered editions, no
  broadsheet overlines, no column layouts.
- **Tracking** is system default. No custom letter-spacing on any surface
  unless a specific component needs it; document it where introduced.

## 4. Iconography

### 4.1 Custom canon (preferred)

The hand-drawn icon table lives in `clawix/CLAUDE.md` (≈lines 1019–1058) and
each icon ships as a Swift `Path`/`Shape` view under
`macos/Sources/Clawix/`. iOS mirrors under `ios/Sources/Clawix/Icons/`.

Use a custom icon when the glyph is part of the product's identity (any
icon the user sees in the sidebar top bar, composer, chat, primary
surfaces) or when no fallback expresses the concept cleanly. The custom
table is the first lookup.

### 4.2 Lucide fallback

When no custom icon exists, use Lucide via the `lcandy2/LucideIcon` SPM
package: `Image(lucide: .name)`. Lowercase, kebab-to-underscore
(`chevron-down` → `.chevron_down`). Bridge file:
`macos/Sources/Clawix/LucideBridge.swift`.

Lucide is appropriate for secondary surfaces: dropdown rows, settings
controls, context menus, dialogs. The user should rarely meet a Lucide
glyph in primary chrome.

### 4.3 SF Symbols and platform glyphs

SF Symbols are banned **except** for OS-native chrome: keyboard glyphs
(`command`, `return`, `option`), system menu items, and platform-mandated
glyphs (App Store, share sheet). Anywhere else, even when an SF Symbol is
"close enough," reach for the custom table or Lucide.

### 4.4 Icon production

When the custom table needs a new entry, hand-draw the glyph (see
`brand/clawix-logo.svg` for the reference style: even-odd fills, single
weight, slight squircle softness). Update the table in `CLAUDE.md`.

### 4.5 Brand master

`brand/clawix-logo.svg` is the canonical source. `ClawixLogoIcon.swift`
mirrors it as Swift `Path`. The two stay in sync; neither is regenerated
inline. Brand mark is a registered trademark (see `TRADEMARKS.md`); usage
in derivative work follows that file.

## 5. Materials and blur

### 5.1 macOS

`NSVisualEffectView` only. Wrapper: `VisualEffectBlur.swift`. Canonical
configurations:

- Floating menus and popups: `material: .hudWindow`, `blendingMode:
  .withinWindow`, `state: .followsWindowActiveState`. Combined with
  `cardFill` overlay for tint (see section 6.3).
- Sidebar column: `material: .sidebar`, `blendingMode: .behindWindow`,
  `state: .followsWindowActiveState`.

Banned: manual blur via `Color.opacity` + saturation tricks, third-party
blur libraries, custom `CIFilter` stacks.

### 5.2 iOS

iOS 26 Liquid Glass only. Use the project wrapper at
`ios/Sources/Clawix/Theme/GlassPill.swift`. Canonical helpers:
`.glassCapsule()`, `.glassCircle()`, `.glassRounded(radius:)`,
`GlassIconButton`. Underlying call: `.glassEffect(.regular, in: shape)`.

Banned on iOS: `.ultraThinMaterial`, `.regularMaterial`, manual
`BackdropFilter`-style stacks, and any custom blur not flowing through the
wrapper.

Glass needs space to refract: pills are at least 50 pt tall, the composer
is at least 64 pt, otherwise the effect reads as a flat tint.

### 5.3 Cross-platform principle

The semantic intent is the same on both OSes: a floating element reads as
slightly translucent against what is behind it, with a fine hairline and a
soft drop shadow. The exact technique differs.

## 6. Components canon

### 6.1 `ThinScroller` (the only scroller)

`macos/Sources/Clawix/ThinScrollbar.swift`. Reemplaces every system
scroller in the project.

- Column width: 14 pt.
- Thumb: 9 pt wide, inset 3 pt from the right edge.
- Vertical padding: 8 pt above/below the track.
- Minimum thumb height: 40 pt.
- Thumb color: white, alpha 0.10 idle, 0.18 hover.
- Shape: capsule (radius = `min(w, h) / 2`).
- Auto-hide when `knobProportion ≥ 0.999` (content fits).
- Alpha pinned to 1.0 at the layer level; do not let the system fade-out
  apply.

Entry points: `ThinScrollView { ... }` for AppKit-backed scrolls
(sidebar, menus); `.thinScrollers()` modifier for SwiftUI `ScrollView`
(chat messages, settings pages).

### 6.2 `SlidingSegmented` (the only 2-N selector)

`macos/Sources/Clawix/SettingsView.swift` (~line 2647). The only correct
way to render 2-N segmented selectors.

- Outer: `RoundedRectangle(cornerRadius: 13, style: .continuous)`, fill
  `Color.black.opacity(0.30)`, stroke `Color.white.opacity(0.10)` 0.5 pt.
- Indicator: single `RoundedRectangle(cornerRadius: 10, style:
  .continuous)`, fill `Color.white.opacity(0.10)`, positioned via
  `.offset` (not `matchedGeometryEffect`).
- Default height: 30 pt. Default font size: 11.5 pt.
- Animation: `.snappy(duration: 0.32, extraBounce: 0)` on the indicator
  offset.

### 6.3 Dropdowns / popovers

Defined by `MenuStyle` (`ContentView.swift` ≈1938) and exemplified by
`ModelMenuPopup` (`ComposerView.swift` ≈1248). There is no generic
`DropdownMenu` view; each feature composes the same primitives. The
primitives:

- Container shape: `RoundedRectangle(cornerRadius: 12, style: .continuous)`.
- Fill: `Color(white: 0.135).opacity(0.82)` over `material: .hudWindow`.
- Border: `Palette.popupStroke` (white, alpha 0.10), 0.5 pt.
- Shadow: `radius: 18, x: 0, y: 10, color: black.opacity(0.40)`.
- Container vertical padding: 4 pt.
- Row padding: horizontal 9 pt, vertical 6 pt.
- Row font: 11.5 pt regular, color `white(0.94)`.
- Row hover: inset rounded rectangle, `cornerRadius: 8 .continuous`, fill
  `white(0.06)` idle / `white(0.08)` when a submenu is open from this row,
  horizontal inset 4 pt from the row edges.
- Submenu horizontal gap from parent: 6 pt.
- Icons in rows: fixed width 18 pt.
- Open transition: `.softNudge(y: 4)` (offset + fade). Submenu transition:
  `.softNudge(x: ±4)` depending on placement.
- Open animation: `.easeOut(duration: 0.20)`. Submenu: `.easeOut(duration:
  0.18)`. Hover micro-interactions: `.easeOut(duration: 0.12–0.14)`.
- Positioning: `anchorPreference` + `overlayPreferenceValue`. Banned:
  `.popover`, `.menu` on chrome surfaces.

This recipe defines every dropdown, context menu, slash menu, model picker,
secrets selector, and settings dropdown. New menu surfaces inherit it
verbatim.

### 6.4 Sidebar

`macos/Sources/Clawix/SidebarView.swift`.

- Section headers (Chats, Tools, etc.): 13.5 pt, weight 500. Horizontal
  padding 34 pt (includes leading icon margin). Vertical padding 4 pt.
  Color `Palette.textPrimary`.
- Section expand/collapse: `.easeOut(duration: 0.18)`. Caret uses the
  Lucide chevron (or custom equivalent if it lands).
- Row height: 35 pt. Row spacing: 0.
- Row shape: `RoundedRectangle(cornerRadius: 9, style: .continuous)`.
- Row hover fill: `white(0.035)` idle on hover row, `white(0.06)` for the
  full hover state.
- Row layout: `HStack { icon + title + Spacer + trailing status }`. Leading
  padding 8 pt plus indent for nested rows. Trailing 3 pt.
- Trailing status renders compact: a small spinner during streaming, an
  unread dot in `pastelBlue` for unread, a textual age (relative time) in
  `textSecondary` otherwise.
- Section bottom spacer: 9.75 pt.

### 6.5 Composer

`macos/Sources/Clawix/ComposerView.swift`.

- Container: `RoundedRectangle(cornerRadius: 22, style: .continuous)`.
- Fill: `Color(white: 0.135)` (same value as menu fill, no blur).
- Content height: min 52 pt, max 412 pt. Resizes smoothly with content;
  attachments use `.animation(.easeInOut(duration: 0.20))`.
- Vertical padding inside the container: 5 pt.
- Input: `ComposerNSTextView` (AppKit-owned for IME, paste, undo).
- Action row inside the composer holds: send, attach, model selector,
  permissions. Each control uses the icon-chip pattern (section 6.6).

### 6.6 Buttons (derived, prescriptive)

The app does not have a canonical primary/secondary/destructive set today.
The pattern below is derived from the curated chrome and is the canon
going forward.

- **Icon chip** (primary in composer and chat chrome). Capsule 28 pt tall,
  internal padding 9 pt icon-only / 11 pt with label. Idle fill:
  `Color.clear`; hover fill: `white(0.06)`; pressed: `white(0.10)`. Border:
  none. Icon color: `textPrimary` at idle.
- **Icon circle** (composer action mini-buttons). 24 pt square, radius 6
  pt. Idle opacity on layer: 0.05. Hover: 0.10. Press: 0.14.
- **Primary text button** (used for confirm actions, "Save", "Send" labels
  if shown). Capsule, height 30 pt, horizontal padding 14 pt. Idle fill:
  `white(0.94)` for solid-light variant; pressed: `white(0.85)`. Text
  color: near-black on light fill, `textPrimary` on dark fill. Brand
  pastelBlue is not the fill (see section 2.3).
- **Secondary text button**. Same shape, fill `white(0.10)`, text
  `textPrimary`, hover `white(0.14)`.
- **Destructive**. Same shape as primary, fill `Color.red.opacity(0.85)`
  in dark mode, white text. Use sparingly; pair with the trash metaphor of
  the constitution (deletion is reversible by default).

The `pastelBlue` accent appears as a focus ring (1 pt, alpha 0.6) when a
control has keyboard focus, never as a fill.

### 6.7 Cards for domain entities (derived, prescriptive)

The constitution requires that every canonical type has a canonical card.
The system below applies to all of them and to custom-database renderers:

- Shape: `RoundedRectangle(cornerRadius: 16, style: .continuous)` on macOS
  desktop chat (room to breathe), 12 on dense surfaces (sidebar previews,
  inbox lists), 20 on hero contexts (a contact card opened to full).
- Fill: `Palette.cardFill`. Hover: `Palette.cardHover`.
- Border: hairline `popupStroke`, 0.5 pt. Optional; many cards use shadow
  instead of border, see below.
- Shadow: same recipe as dropdowns (`radius: 18, y: 10,
  black.opacity(0.40)`) for free-floating cards (chat inline cards);
  cards inside a sub-app list use border instead of shadow.
- Padding: 12 pt vertical, 14 pt horizontal for compact rows; 18/20 for
  hero detail.
- Field layout: vertical stack. Primary identifier (name, title) at the
  top, weight medium, size from the type table (typically `bodyFont` or
  `bodyEmphasized`). Meta fields in `textSecondary`, `secondaryFont`.
- Field visibility: each card supports the user toggling visibility of
  fields. Sensible defaults per type; toggles live in the type's settings,
  not on the card itself.
- Both ends: cards render correctly with much data (long names, many
  fields) and with little (just a name). Truncate single-line fields with
  ellipsis at the right boundary, never wrap inline labels.
- Action affordances: cards expose 0 to 3 inline actions in their footer
  (e.g., "Open", "Message", "Edit"). Each action is an icon chip.
- Avatar / leading visual when relevant: 28 pt circle in compact, 56 pt
  circle in hero. Squircle is `Circle()` here; `Capsule` for non-circular
  avatars (rare).

### 6.8 Inputs (text, search, settings rows)

- Single-line text input (search bar, settings field): `Capsule()` shape,
  height 28 pt, horizontal padding 12 pt. Fill `white(0.06)` idle,
  `white(0.08)` focused. Placeholder color `textSecondary`. Focus ring 1
  pt `pastelBlue` alpha 0.6.
- Multi-line text input (instructions, descriptions): same as composer
  primitives, fill `white(0.06)`, radius 12 pt.

## 7. Motion

### 7.1 Curves

- **Default curve: `.easeOut`.** Springs and bounces are not used in
  chrome. The only exception is the `SlidingSegmented` indicator, which
  uses `.snappy(duration: 0.32, extraBounce: 0)` to feel mechanical
  without overshoot.
- For state changes that need a sense of weight (sheet present/dismiss,
  modal in/out), `.easeInOut` is acceptable; everywhere else `.easeOut`.

### 7.2 Durations

| Where | Duration |
|---|---|
| Hover enter / exit on chrome | 0.12 – 0.14 s |
| Hover hints (tooltips) | 0.18 s in, 0.16 s out |
| Dropdown / popup open | 0.20 s |
| Submenu open | 0.18 s |
| Sidebar expand / collapse | 0.18 s |
| Attachments adding to composer | 0.20 s |
| Segmented indicator (snappy) | 0.32 s |

These cover ≥ 95% of chrome motion. Longer durations are a smell.

### 7.3 Transitions

- **`softNudge(x:y:)`** is the canonical entry/exit transition: a small
  offset combined with a fade. Banned: `.scale` (creates Material-like
  bounce), `.opacity` alone (feels weightless), `.move` raw (snaps).
- Dropdowns enter with `softNudge(y: 4)`; submenus with `softNudge(x:
  ±4)` depending on side.

### 7.4 Streaming animation

When an agent is producing output, the visible cursor is a 1.5 pt × 14 pt
rounded vertical bar in `textPrimary`, blinking at 600 ms cycle. Token
arrival should not cause layout jumps; allocate the worst-case width
before streaming starts.

## 8. Spacing and radii

### 8.1 Radii scale

The corner radius scale, all `.continuous`:

| Use | Radius |
|---|---|
| Tight inset hovers, segmented indicator | 8 |
| Sidebar rows | 9 |
| Inset cards (settings cards) | 10 |
| Popups, chips, compact cards, menus | 12 |
| Segmented outer | 13 |
| Cards in dense lists | 12 |
| Cards on chat | 16 |
| Buttons | 16 |
| Cards in hero | 20 |
| Composer | 22 |

These are the values in use; do not invent intermediate radii.

### 8.2 Spacing

No formal 4 / 8 grid is enforced today. Values in use cluster around
multiples of 4 in iOS tokens. New surfaces follow these values:

- 4 / 6 / 8 / 12 / 14 / 16 / 20 are the preferred spacings.
- Padding decisions live next to the component; do not extract into
  shared constants unless a value repeats in three independent places.

### 8.3 Hairlines and borders

- Hairline thickness: 0.5 pt. (Apparent 1 pt on non-retina, 1 px on
  retina.)
- Hairline color: `popupStroke` (white, alpha 0.10) on dark; near-black at
  alpha 0.10 on light.
- Divider in lists: white at alpha 0.06.

### 8.4 Shadows

- Floating elements (popups, free cards): `radius: 18, x: 0, y: 10,
  color: black.opacity(0.40)`.
- Pressed-down elements (no shadow). Layered elements that should not
  float (rows in a list) get a hairline instead.
- Never use multiple stacked shadows. Never use harsh shadows (`radius <
  10`).

## 9. Sub-apps and surfaces

(Constitution principles VII.2 and VII.8 govern these technically; the
style rules below cover the visual layer.)

- A sub-app inside Clawix is hosted in a container that follows the same
  `cardFill` / `border` recipe. Its content can override paddings and
  internal layouts.
- External surfaces (messaging apps where the agent appears) inherit the
  surface's chrome and emit only content. Brand voice in the agent's
  language, not in the visual chrome.

## 10. Lint and enforcement

- **Squircle lint.** `macos/scripts/dev.sh` includes 4 checks (lines
  ~88–133). `ios/scripts/squircle_lint.sh` mirrors them. These run on
  every dev build and on CI.
- **Interface governance guard.** `scripts/ui_governance_guard.mjs` validates
  the cross-platform pattern registry, debt baseline, protected-surface
  manifest, exception shape, and unauthorized visual/copy source diffs. The
  fast test lane runs it.
- **Visual mutation boundary.** UI work is classified as `functional-ui`,
  `visual-ui`, `copy-ui`, or `mechanical-equivalent-refactor`. Only explicitly
  authorized visual lanes may make `visual-ui` or `copy-ui` decisions.
  Non-authorized agents report visual drift instead of repairing it.
- **Open lint work**:
  - SF Symbols guard: a build check that flags any `Image(systemName:)`
    outside the allowlisted OS-chrome usages.
  - Material guard on iOS: flag `.ultraThinMaterial`, `.regularMaterial`,
    `BackdropFilter`-equivalents anywhere outside the `GlassPill` wrapper.
  - System `.popover` / `.menu` guard on macOS: flag any usage outside
    explicitly allowlisted locations.
  - SlidingSegmented enforcement: flag any 2-N segmented control built
    with system `Picker(...)` style segmented.
  - Scroller enforcement: flag any AppKit `NSScrollView` / SwiftUI
    `ScrollView` outside the `ThinScrollView` / `.thinScrollers()` paths.

These lints do not exist yet; the rules above apply by convention until
they do.

## 11. Performance and instrumentation

(Connected to constitution principles V.4 and V.5.)

`PerfSignpost` taxonomy at `macos/Sources/Clawix/Diagnostics/Signposts.swift`.
Categories: `ui.chat`, `ui.sidebar`, `state.appstate`, `ipc.client`,
`render.markdown`, `render.streaming`, `image.load`, `secrets.crypto`,
`hang`, `resource`.

Style rule: any new UI surface that animates or streams adds a signpost
category. Optimization is preceded by an `xctrace` capture, not by
guesswork.

## 12. Microcopy

- **Voice**: direct, calm, present-tense. Speaks to the user as a peer.
- **Length**: a label is at most 4 words; a row caption at most 8; a
  tooltip at most 12. Past the limit, move the content into a card or a
  detail surface.
- **Numbers**: `1 chat`, `2 chats`. Spelled-out plurals only for 0; "no
  chats" not "0 chats".
- **Time**: relative (`2m`, `3h`, `yesterday`) on dense rows; absolute
  (`Tue, Mar 4 14:32`) on detail surfaces.
- **Agent attribution**: when content is agent-authored, label it with a
  small `pastelBlue` accent or a leading agent glyph; do not append
  "(generated)" or "(AI)" as text.

## 13. Open work (debts the design system carries)

These exist in code but are not yet at canon level. STYLE.md describes
the target; the existing implementation is debt.

- **Light mode**: not implemented yet. Section 2.4 defines the derivation
  rules so the work has a target.
- **Settings polish**: only `SlidingSegmented` and `SettingsCard` are at
  canon. Toggles, list rows, page headers in Settings need to inherit the
  dropdown / sidebar tuning level.
- **Chat bubbles and inline cards**: bubbles have inconsistent padding,
  no user/agent visual distinction, no inline cards for typed entities.
  Section 6.7 (cards) is the destination; the chat surface needs to
  surface those cards when an agent shares a contact, an event, a recipe,
  etc.
- **Canonical button set**: the recipe in section 6.6 is prescriptive;
  existing button styles in the code are ad hoc per feature. The recipe
  applies from now on; existing buttons migrate when touched.
- **`Theme.swift` / `DesignTokens.swift` on macOS**: today tokens are
  inline in `ContentView.swift Palette`. Extract to a `Theme.swift` in
  `macos/Sources/Clawix/Theme/` mirroring the iOS shape, so light-mode
  branching has one place to land.
- **Sidebar refactor**: visually canon; the 5000+ line `SidebarView.swift`
  needs structural cleanup. STYLE.md preserves the visual rules so the
  refactor cannot regress the look.
- **External messaging surfaces**: each adapter (messaging platform) emits
  agent content. The visual chrome of those surfaces is the host's; only
  the content style (concise, multi-modal, card-friendly when the host
  supports it) is governed here.

## 14. Glossary delta

Terms specific to STYLE.md, complementary to the constitution glossary.

- **Curated zone**: a part of the app whose values are taken as canon by
  this document. Today: sidebar, dropdowns, composer, chat, ThinScroller,
  SlidingSegmented.
- **Hairline**: 0.5 pt border.
- **Squircle**: a `RoundedRectangle` or `Capsule` rendered with
  `.continuous` corners.
- **Chrome**: the UI shell (sidebar, toolbar, composer, dropdowns, status
  bar). Distinct from content (chat messages, document body, sub-app
  internals).
