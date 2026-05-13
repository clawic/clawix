# Clawix

Monorepo for the Clawix project. Clawix is the native human interface and
embedded signed host for ClawJS/Claw. It is not the canonical framework store
and new work must not treat it as a direct Codex-only client.

For framework, host, storage, CLI, permissions, grants, approvals, audit,
naming style, public packages, ports, routes, protocol vocabulary, and domain
ownership decisions, read [`docs/host-ownership.md`](docs/host-ownership.md),
[`docs/data-storage-boundary.md`](docs/data-storage-boundary.md),
[`docs/decision-map.md`](docs/decision-map.md),
[`docs/naming-style-guide.md`](docs/naming-style-guide.md),
[`docs/adr/0001-claw-framework-host-boundary.md`](docs/adr/0001-claw-framework-host-boundary.md),
and [`docs/adr/0002-naming-and-stability-surfaces.md`](docs/adr/0002-naming-and-stability-surfaces.md)
before editing.

## Repository layout

```
macos/          # macOS client (SwiftUI).
ios/            # iOS client.
packages/       # Shared Swift packages.
cli/            # Legacy/transitional npm CLI surface, not new public Claw CLI.
docs/           # Architecture docs and ADRs.
```

Each app has its own build entrypoint and platform scripts. Public repository
files must contain only safe placeholders for bundle ids, signing identities,
Team IDs, launch labels, Mach services, and host branding. The shared
architecture boundary lives in `docs/host-ownership.md`; do not encode a second
ownership model in target-specific notes.

## Build (macOS app)

Requirements: macOS 14+, Swift 5.9+, Xcode Command Line Tools.

### Dev loop

```
bash macos/scripts/dev.sh
```

Compiles debug, kills the previous instance, relaunches. By default the build is ad-hoc-signed and bundled as `com.example.clawix.desktop` (a placeholder); macOS will re-prompt for permissions (Desktop folder, microphone, etc.) on every relaunch.

### Stable signing (recommended)

Create a `.signing.env` file at the repo root (or any parent directory) with your values:

```
SIGN_IDENTITY="<codesign identity>"
BUNDLE_ID="com.yourdomain.clawix"
```

`dev.sh` and `build_app.sh` source it automatically. Environment variables override the file. With a stable identity + bundle id, macOS persists TCC grants between rebuilds. List your codesign identities with `security find-identity -v -p codesigning`.

### Release

```
bash macos/scripts/build_app.sh
```

Produces `macos/build/Clawix.app`. Same `SIGN_IDENTITY` / `BUNDLE_ID` resolution as `dev.sh`.

## Hygiene gate (publication)

Before publishing anything, this must pass:

```
bash macos/scripts/public_hygiene_check.sh
```

It scans the entire repo publish surface (root docs, `macos/`, `ios/`, `packages/*/` and `cli/`) for: developer-machine paths, secret-looking literals, hex digests, hard-coded codesign material, Apple Team IDs and committed `.signing.env` files. The npm CLI under `cli/` is part of the same publish surface, so its source ships under the same blacklist.

## Commits

Conventional commits: `type(scope): description`. Types: `feat`, `fix`, `style`, `chore`, `refactor`, `docs`, `test`. Lowercase, no trailing period.

Use a platform prefix in the scope when the change is specific to one app:

- `feat(mac/composer): add model menu popup`
- `fix(ios/onboarding): prevent loop when token expires`
- `chore(repo): update hygiene globs`

Rules:

- One change per commit. Do not bundle unrelated changes.
- Only the changes from the current session; do not sweep unrelated edits in.

## Code style

- **Language: English.** Every identifier, every comment, every doc comment, every commit message, every script log line, every user-visible string in this repo is written in English. No Spanish (or any other language) in code, comments or commits, even if the contributor's working language is different. This is a public repo and the default reader is an English-speaking contributor.
- **Comments: minimal.** Default to writing none. Well-named identifiers explain WHAT the code does. Only add a comment when the WHY is non-obvious: a hidden constraint, a workaround for a specific bug, an invariant that would surprise a reader. One short line, not a paragraph. Never reference the current task or the PR ("added for X", "fixes Y") since that belongs in the commit message and rots over time.

## Hard privacy rules (important for any contributor and any AI agent)

This repository never contains the maintainer's real codesign identity, Apple Team ID, or bundle id. They live in a `.signing.env` file kept outside the public tree. When contributing code:

- **Do not hard-code** a `CFBundleIdentifier`, a `DEVELOPMENT_TEAM`, or a codesign identity literal anywhere in this repository. Those values are read at runtime from `.signing.env` or environment variables.
- **Do not commit** the file `.signing.env`. It is in `.gitignore` and `macos/scripts/public_hygiene_check.sh` fails the build if a copy is detected inside the public tree.
- **Do not introduce** an `Info.plist` with a literal bundle id. The plist is generated in `build_app.sh` interpolating `${BUNDLE_ID}`.
- **Do not add** an Xcode project with a concrete development team value. Leave the field empty; the script supplies it from the environment.

If you need to expose a new piece of local config (another identifier, another flag), add the variable to the scripts and document it in `.signing.env.example`. Never the other way around.

---

# macOS app · `macos/`

Native macOS Clawix app. It is the human UI and the Clawix-signed embedded host
for ClawJS/Claw. Clawix owns native UI, visual state, approvals, and host
identity; ClawJS/Claw owns canonical framework contracts, storage, domain APIs,
and the public `claw` CLI.

Current bridge compatibility still supports Codex-backed runtime flows, but
Codex data is an external read-only source by default. `~/.codex` may be read,
mirrored, or indexed; it must not be deleted, moved, overwritten, recursively
chmodded, or used as a write target. `AGENTS.md` writes into Codex-owned sources
require explicit reversible opt-in.

Do not reintroduce a second GUI-owned bridge/backend when background bridge mode
is enabled. Any iOS-visible runtime feature should be implemented on the daemon
or host contract surface first, then consumed by the Mac app and iOS clients.

## Layout

- `macos/Package.swift`: Swift Package, target `Clawix`, macOS 14+. One external dependency: [Sparkle 2](https://sparkle-project.org) for in-app updates.
- `macos/VERSION`: single source of truth for the marketing version. `dev.sh` and the release scripts read it via `_emit_version.sh` and inject it into the generated Info.plist.
- `macos/Sources/Clawix/`: SwiftUI source.
- `macos/Sources/Clawix/AppVersion.swift`: reads `CFBundleShortVersionString` / `CFBundleVersion` at runtime so the app reports the version it was actually compiled with.
- `macos/Sources/Clawix/Updater/UpdaterController.swift`: thin wrapper around `SPUStandardUpdaterController`. Drives the "Update" chip in the top bar.
- `macos/Sources/Clawix/DaemonBridgeClient.swift`: loopback client used by the Mac app when the background bridge daemon is active.
- `macos/Helpers/Bridged/`: Swift helper executable that runs as the background bridge daemon and owns the Codex runtime connection in background bridge mode.
- `packages/ClawixCore/`: shared bridge wire protocol.
- `packages/ClawixEngine/`: shared bridge server/session/pairing runtime.
- `macos/scripts/dev.sh`: dev launcher (build + relaunch). Copies Sparkle.framework into the bundle and signs deep.
- `macos/scripts/build_app.sh`: release-only `.app` builder (single identity, deep sign).
- `macos/scripts/build_release_app.sh`: notarization-ready builder. Reads `DEVELOPER_ID_IDENTITY` from env and applies per-component hardened-runtime signing in the order Sparkle requires.
- `macos/scripts/public_hygiene_check.sh`: hygiene gate scanned across the whole repo.

The full release orchestration (notarytool, DMG packaging, Sparkle EdDSA signing, appcast regeneration, GitHub Release upload) is intentionally NOT in this public tree. It lives in the maintainer's private workspace and consumes `build_release_app.sh` plus credentials from `.signing.env`.

## Background bridge daemon architecture

The bridge daemon is the canonical host for cross-device runtime work. It starts the Codex app-server over stdio, keeps the bridge listening on its configured port, and publishes the same wire protocol used by iOS. In daemon mode, the Mac app is just another authenticated desktop client over `127.0.0.1`.

Required invariants:

- One runtime owner. When background bridge mode is active, the Mac app must not also bootstrap its own Codex backend or publish another `BridgeServer`.
- Shared pairing. The QR payload, bearer token and port must point to the daemon, not to a GUI-local server.
- Shared state. Chat list, history hydration, new chat creation, prompt sending, streaming updates and archive state flow through the daemon so iOS and Mac observe the same source of truth.
- Daemon-first expansion. If a new bridge feature needs to work on iOS, add daemon support and E2E coverage for that frame before wiring UI clients to it.
- No real-cost validation by default. E2E tests should use isolated fake backends unless the user explicitly approves a real prompt. Real host validation may authenticate and list chats, but must not send real prompts without confirmation.

## Feature flags: experimental hidden in release builds

Two opt-in tiers gate in-development surfaces: **Beta** and **Experimental**. The toggles live in Settings → General. Both default to OFF. The toggles, the underlying persistence and the user-visible card are **dev-only** — release builds (`swift build -c release`, i.e. anything `dev.sh` did not produce) ship without them.

Hard rules:

- The "Feature previews" card in Settings → General is wrapped in `#if DEBUG`. In a notarized binary the card does not render and the toggles are not user-controllable.
- `FeatureFlags.beta` and `FeatureFlags.experimental` are `@Published var` only inside `#if DEBUG`. Under `#else`, they are `let beta = false` / `let experimental = false` with no UserDefaults backing. A stale value persisted by an earlier dev build cannot leak into a release build because the persistence code does not exist there.
- `isVisible(_:)` keeps the same signature in both configurations. Call sites (`SidebarView`, `App`, `QuickAskController`, `AppState`, etc.) need no `#if DEBUG` of their own — in release the function returns `false` for any beta or experimental tier.
- This must stay **compile-time** enforced, not runtime config. Do not introduce a `UserDefaults` override, an Info.plist key, an environment variable or a launch argument that re-enables either flag in a release build. The contract is: notarized = stable surface only, no escape hatch.
- When promoting a feature out of beta/experimental, change its `tier` in `AppFeature.tier` to `.stable`. Do not "ship it via the experimental toggle" by flipping a default — the toggle is gone in release.

Auto-enforced via the `#if DEBUG` guards in `FeatureFlags.swift` and `SettingsView.swift`. If a contributor introduces a new toggle that should also be dev-only, follow the same pattern (compile-time guard around both the storage and the UI).

## Corner radius: always squircle (`.continuous`)

App-wide standard. Every corner radius is rendered with `style: .continuous` (Apple's superellipse). Never `.circular`, never the default style. The difference vs. `.circular` is subtle but cumulative: a `.continuous` app feels "pro", a `.circular` one feels amateur.

**Auto-enforced**: `dev.sh` runs a lint that fails the build if any of the following appear. If the lint fires, the build does not compile and the app is not relaunched.

The lint covers four rules:

- `RoundedRectangle(cornerRadius: X)` → always `RoundedRectangle(cornerRadius: X, style: .continuous)`. Lint A.
- `UnevenRoundedRectangle(...)` → always with `style: .continuous`. Lint D scans for `.continuous` within the 6 lines following the opening, so multi-line declarations work as long as `.continuous` shows up.
- `Path(roundedRect: r, cornerSize: s)` and `Path(roundedRect: r, cornerRadius: x)` default to `.circular`; pass `style: .continuous` explicitly. Lint D.
- `.clipShape(RoundedRectangle(...))` → same `.continuous` standard (lint A covers it because the underlying pattern is the same).
- **Forbidden**: SwiftUI's `.cornerRadius(X)` modifier. It clips circular by default. Replace with `.clipShape(RoundedRectangle(cornerRadius: X, style: .continuous))`. Lint B.
- **Forbidden**: `style: .circular` and `RoundedCornerStyle.circular` literals. Lint C.
- `Capsule()` and `Circle()` are out of scope (fully rounded by construction, no configurable radius).

Edge cases the lint does not cover, watch by hand:

- `NSBezierPath(roundedRect: rect, xRadius:, yRadius:)` (AppKit) has no squircle variant; it always draws circular. Allowed only when the radius is ≥ ~40% of the shorter side (effectively a capsule/pill, the visual delta is nil — e.g. the custom scrollbar thumb). For anything else, draw the shape with `Path` (SwiftUI) or `CGPath` with squircle, or replace with SwiftUI `RoundedRectangle`.
- `Image` with rounded corners via `.clipShape(...)` → the `clipShape` carries `RoundedRectangle(cornerRadius:style: .continuous)`. Lint A catches it.

When a new component draws its own radius (canvas, hand-painting in a `GeometryReader`, etc.) route it through `RoundedRectangle` or `Path(roundedRect:cornerSize:style: .continuous)`. Do not invent circular Bézier curves by hand.

## Segmented selectors: always `SlidingSegmented`

App-wide standard for any 2-N mutually-exclusive choice picker (e.g. "Used / Remaining", "Queue / Drive", "Inline / Detached", "STDIO / HTTP streaming", merge methods, transport modes). The canonical component lives in `macos/Sources/Clawix/SettingsView.swift` as `SlidingSegmented<T>` and is the only correct way to render this pattern.

What `SlidingSegmented` looks like:

- Outer container: `RoundedRectangle(cornerRadius: 13, style: .continuous)` with `Color.black.opacity(0.30)` fill and a 0.5pt `Color.white.opacity(0.10)` stroke.
- Indicator: a single `RoundedRectangle(cornerRadius: 10, style: .continuous)` filled `Color.white.opacity(0.10)`. There is exactly ONE indicator in the tree, positioned by `.offset` based on the selected index. There is no per-chip background that fades in/out.
- Inner radius is concentric to the outer (outer 13 − padding 3 = 10), so the highlight squircle nests visually inside the track squircle.
- Selected text: `Palette.textPrimary` weight `.medium`. Unselected: `Palette.textSecondary` weight `.regular`. Same font size across both.

Animation:

- The indicator slides between options with `.snappy(duration: 0.32, extraBounce: 0)` applied as `.animation(animation, value: selection)` directly on the indicator's offset modifier. Quick, no bounce, no overshoot.
- **Forbidden**: `matchedGeometryEffect` for the indicator. It's unreliable when the binding writes through `@AppStorage` on macOS (the indicator stops sliding and snaps). The "single indicator with `.offset`" pattern is the only reliable approach.
- **Forbidden**: `withAnimation` inside the chip Button action. The animation lives on the indicator view, driven by `value: selection`, so the curve fires whether the change comes from a tap, a hotkey, or a `@AppStorage` round-trip.

Sizing:

- Height fixed (default 30, override via `height:`); width comes from the parent. In a row layout (label + Spacer + segmented) pin it with `.frame(width: 190)` (or any width that fits the longest label without truncating). When the selector should fill its container — full-width form fields like MCP transport — leave the width unset and the inner `GeometryReader` handles the math.
- All chips have equal width by construction. If labels differ in length, size the segmented to the longest one — never let one chip be visibly wider than another.

Persistence:

- Whenever a segmented choice should survive across app launches (display modes, view filters, preferred transports, anything the user has expressed a preference for), back the binding with `@AppStorage` and a stable key prefixed `clawix.<area>.<setting>` (e.g. `"clawix.settings.usage.displayMode"`). Use a `RawRepresentable<String>` enum so SwiftUI serializes it directly. **Default**: pick the option a first-time user is most likely to want — usually the more informative or less destructive one.

When migrating existing selectors:

- `SegmentedRow<T>` (settings row pattern with label + detail on the left, segmented on the right) already wraps `SlidingSegmented` internally. New rows of this shape should use `SegmentedRow`, not roll their own.
- Any custom segmented control that uses `Capsule()` for the indicator, multiple per-chip backgrounds with `if isOn { ... }`, or `matchedGeometryEffect` — replace it with `SlidingSegmented`. Don't keep the old shape "for now".
- Multi-option pickers that need decorative icons per option (e.g. theme switcher: sun/moon/laptop) are not yet first-class in `SlidingSegmented`. When you need that, extend `SlidingSegmented` with optional icon support rather than reintroducing the per-chip-capsule pattern.

`Picker(selection:)` with `.pickerStyle(.segmented)` is forbidden anywhere in the app — it ignores the squircle convention and the curve doesn't match. Always `SlidingSegmented`.

## Custom icons (project canon)

The app ships its own hand-drawn icons (Canvas / Path / Shape) for every glyph that has a strong identity in the UI: documents, folders, terminal, globe, mic, search, branch, pin, archive, copy, pencil, branch-arrows, sidebar toggle, etc. They live in `macos/Sources/Clawix/` next to the rest of the views and are exported as plain `View` types (e.g. `FileChipIcon`, `TerminalIcon`, `GlobeIcon`, `FolderOpenIcon`, `MicIcon`, `SearchIcon`, `CursorIcon`).

**Before adding any `Image(systemName:)`, check whether a custom equivalent already exists.** SF Symbols look generic next to the rest of the chrome and break visual consistency. The canonical map (extend it as new icons are added):

| Concept            | Custom view                          | File                          |
|--------------------|--------------------------------------|-------------------------------|
| Document / file    | `FileChipIcon`                       | `FileChipIcon.swift`          |
| Folder (open)      | `FolderOpenIcon`                     | `FolderOpenIcon.swift`        |
| Folder (closed)    | `FolderClosedIcon`                   | `FolderOpenIcon.swift`        |
| Folder add         | `FolderAddIcon`                      | `FolderOpenIcon.swift`        |
| Folder stack       | `FolderStackIcon`                    | `FolderStackIcon.swift`       |
| Branch (git)       | `BranchIcon`                         | `FolderOpenIcon.swift`        |
| Pin                | `PinIcon`                            | `FolderOpenIcon.swift`        |
| Archive / unarchive| `ArchiveIcon` / `UnarchiveIcon`      | `FolderOpenIcon.swift`        |
| Globe / web        | `GlobeIcon`                          | `GlobeIcon.swift`             |
| Search             | `SearchIcon`                         | `SearchIcon.swift`            |
| Mic                | `MicIcon`                            | `MicIcon.swift`               |
| Terminal           | `TerminalIcon`                       | `TerminalIcon.swift`          |
| Cursor (text)      | `CursorIcon`                         | `CursorIcon.swift`            |
| Copy               | `CopyIconView`, `CopyIconViewSquircle` | `ChatView.swift` (legacy spot, ideally `CopyIcon.swift`) |
| Pencil / edit      | `PencilIconView`                     | `ChatView.swift` (legacy spot, ideally `PencilIcon.swift`) |
| Branch arrows      | `BranchArrowsIconView`               | `ChatView.swift` (legacy spot) |
| Sidebar toggle     | `SidebarToggleIcon`                  | `ContentView.swift` (legacy spot) |
| Compose new chat   | `ComposeIcon` (`Shape`)              | `SidebarView.swift` (legacy spot) |
| Pinned (sidebar)   | `PinnedIcon` (`Shape`)               | `SidebarView.swift` (legacy spot) |
| Funnel (filter)    | `OrganizeFunnelIcon`                 | `SidebarView.swift` (legacy spot) |
| Expand (settings)  | `ExpandIconButton` (composite)       | `SettingsView.swift` (legacy spot) |
| Collapse / expand corners | `CornerBracketsIcon`           | `CornerBracketsIcon.swift`         |
| Brand logo (app icon)     | `ClawixLogoIcon`, `ClawixLogoTemplateImage` | `ClawixLogoIcon.swift`             |

### Brand logo

The Clawix mark itself is a custom shape too. Master vector lives at `brand/clawix-logo.svg` at the repo root: a single `evenodd`-filled `<path>` in a `100x100` viewBox. Geometry: outer iOS-style continuous-corner squircle (3 cubic beziers per corner with the Apple app-icon magic numbers, corner extent `38`), visor cut out (smaller squircle, corner extent `22`), two squircle eyes filled back in. `currentColor` so the consumer decides the tint.

In code, the same path is reproduced in `macos/Sources/Clawix/ClawixLogoIcon.swift`. Two entry points:

- `ClawixLogoIcon(size:)` — SwiftUI `View`, fills with `.primary`. Use anywhere inside the SwiftUI hierarchy (splash, about screen, empty states, settings).
- `ClawixLogoTemplateImage.make(size:)` — flattens the shape into an `NSImage` with `isTemplate = true`. Required for `MenuBarExtra` because its label slot does not render arbitrary SwiftUI `Shape`s reliably (renders as an empty hole). AppKit applies the menu bar's foreground tint automatically when the image is template.

Hard rules:

- The brand mark is `ClawixLogoIcon` / `ClawixLogoTemplateImage`. Never re-derive the path inline somewhere else, never use `Image(systemName:)` as a stand-in.
- When the SVG master changes (`brand/clawix-logo.svg`), update the path in `ClawixLogoIcon.swift` to match. The two are intentionally redundant: the SVG is the human-editable source, the Swift path is the runtime rendering. If the iOS app eventually ships, it imports `brand/clawix-logo.svg` (or replicates the same path natively); the master in `brand/` stays canonical.
- For places that need the `.icns` / iOS asset catalog renders, those are produced from the same master (currently the `.icns` lives in `macos/Sources/Clawix/Resources/Clawix.icns`). When updating the brand, regenerate both the in-code path and the rasterized asset; do not let them drift.

Hard rules:

- **One file per icon, named after it.** New icons go in their own `XxxIcon.swift` file. Do not paste a Canvas / Path icon body into a feature view file. Existing icons that live in feature files (the "legacy spot" rows above) are pending extraction; treat them as an exception, not a precedent.
- **Never duplicate a custom icon's body across files.** If you need the same glyph in a new place, import the existing struct. If two places need slightly different sizes / colors, parametrize the existing struct with `var size: CGFloat`, `var color: Color`, etc., do NOT copy/paste.
- **Before reaching for any system icon, check the table above and grep the project for `<concept>Icon`.** When the glyph genuinely has no project-custom equivalent, the canonical fallback is a **Lucide-sourced icon** (see "Lucide-sourced icons" below), NOT an SF Symbol.
- **The model behind this rule**: a custom icon is the project's design DNA. If you swap one for a generic icon the screen feels "off" even if you can't pinpoint why. The user notices.
- When in doubt about whether a glyph deserves a custom icon, **ask before drawing**. Hand-drawing an icon that already has a system equivalent and lives nowhere else in the app is wasted work.

## Lucide-sourced icons (project canon, fallback for non-custom glyphs)

When a glyph has no project-custom icon (the table above), the fallback is **Lucide** (https://lucide.dev), not SF Symbols. Lucide has a clean, restrained outline language that sits next to the custom Path-based icons without breaking visual consistency; SF Symbols feel generic next to the rest of the chrome.

Hard rules:

- **Use the SPM-managed Lucide package, never hand-port the SVG paths.** A previous attempt to hand-port silhouettes into SwiftUI `Path` shapes was a visual fracaso (chevrons came out fine, complex glyphs like trash, paperclip, link, drama looked broken). The canonical install is `lcandy2/LucideIcon` from `https://github.com/lcandy2/LucideIcon.git`, declared in `macos/Package.swift` and in `ios/project.yml` (`packages.LucideIcon`). The package converts every Lucide SVG into a custom SF Symbol via `swiftdraw` and ships them as an asset catalog, so existing SwiftUI Image modifiers (`.font(.system(size:))`, `.foregroundStyle`, `.symbolRenderingMode`, `.imageScale`) all continue to work like a normal `Image(systemName:)`.
- **Call sites use `Image(lucide: .name)`.** Hyphens become underscores: `chevron-down` → `.chevron_down`, `trash-2` → `.trash_2`, `arrow-up-right` → `.arrow_up_right`. The list of available cases lives in the package's `LucideIcon+All.swift`. Files that use Lucide need `import LucideIcon` at the top, alongside `import SwiftUI`.
- **Bridge for legacy SF Symbol strings.** A small `LucideBridge.swift` lives at `macos/Sources/Clawix/LucideBridge.swift` (and mirrored at `ios/Sources/Clawix/Theme/LucideBridge.swift`). It exposes `LucideIcon.sfMapped(_: String) -> LucideIcon?` and `Image(lucideOrSystem: String)`. Use the latter at sites where the icon name is a runtime String coming from data tables (settings categories, plugin metadata, permission-mode `iconName` properties, etc.). The bridge's mapping table is the single place where a new SF-Symbol-string-to-Lucide entry is added.
- **SF Symbols stay forbidden** as a generic fallback. The only legitimate `Image(systemName:)` left in the codebase is for genuinely OS-level chrome where the platform glyph is the right answer (e.g. `command` for the Cmd modifier in keyboard shortcut hints, `return` for the Return key, system menu/menubar conventions where AppKit owns the rendering). Anything that depicts a domain concept (folder, document, trash, search, chevron, plus, x, arrow, etc.) goes through Lucide.

The brand mark is still `ClawixLogoIcon` / `ClawixLogoTemplateImage`. Lucide is for everything that is a domain glyph without project identity.

## Dropdowns / popups / context menus (project canon)

The composer's model selector (`ModelMenuPopup` in `ComposerView.swift`) is the **visual reference** for any dropdown, popover-style menu, edit menu or context menu. Anything new and anything retroactive should match it.

Chrome:

- Background: `RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.135))`.
- Border: `.stroke(Palette.popupStroke, lineWidth: Palette.popupStrokeWidth)` (0.10 alpha, 0.5 px). Hairline, almost invisible.
- Shadow: `.shadow(color: .black.opacity(0.40), radius: 18, x: 0, y: 10)`.
- Container vertical padding: `6 pt`.
- Canonical helper: `.menuStandardBackground()` in `ContentView.swift`. **Use it always**, do not re-create the rectangle by hand.

Rows:

- Padding: `.padding(.horizontal, 14).padding(.vertical, 7)`. Compact, NOT 10/8 nor 10/10.
- Text: `font(.system(size: 13.5))`, color `Color(white: 0.94)`.
- Icons: `font(.system(size: 13))` (14 if the row is heavy), color `Color(white: 0.86)`, fixed width `frame(width: 18, alignment: .center)` so columns align.
- Subtitles, shortcuts, trailing chevrons: `Color(white: 0.55)`, sizes 11–12.
- Hover: NOT a full-bleed background. Use the `MenuRowHover(active: hovered)` helper. It is a `RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)).padding(.horizontal, 5)` that breathes towards the menu's edges. For rows highlighted because their submenu is open, raise to `0.08`.
- Selection check: `font(.system(size: 11, weight: .semibold))`, color `Color(white: 0.94)`.

Opening + animation:

- Anchoring: `anchorPreference` + `overlayPreferenceValue` (NOT SwiftUI `.popover`). `.popover` adds the system arrow chrome and breaks the look. Canonical pattern in `ComposerView.swift` for the model selector.
- Position: anchored from above just below the trigger. `alignmentGuide(.top) { d in d[.bottom] - buttonFrame.minY + 6 }` to hang 6 pt below; `alignmentGuide(.leading)` to align to the trigger (or to the right edge if the menu is wider).
- Entry transition: `.transition(.softNudge(y: 4))` (defined in `ComposerView.swift`). Side submenus: `.transition(.softNudge(x: -4))`. Do NOT use `.opacity.combined(with: .scale)`.
- Easing: `.animation(.easeOut(duration: 0.20), value: <openState>)` on the container.
- Outside click: `.background(MenuOutsideClickWatcher(isPresented: $isOpen))` inside the menu so it closes on outside click.

What to avoid:

- `.popover(isPresented:arrowEdge:)` with system chrome.
- Full-bleed hover backgrounds (highlights must inset from the menu edge).
- Heavy borders `lineWidth: 1` with `Color.white.opacity(0.08)` or similar; always `Palette.popupStroke` with `Palette.popupStrokeWidth`.
- `cornerRadius` 14/16; the standard is 12.
- Tall rows (vertical 10+); compact at 7.

Constants and helpers already available (in `ContentView.swift`):

- `enum MenuStyle` with all sizes, colors and animation.
- `extension View { func menuStandardBackground() }` for the container.
- `struct MenuRowHover` for the hover highlight.
- `extension AnyTransition { static func softNudge(x:y:) }` (in `ComposerView.swift`).

Before adding a new dropdown, look at `ModelMenuPopup` and replicate its structure. If the behavior differs (side submenu, sectioned with header, divider), copy the building blocks `ModelMenuHeader`, `ModelMenuDivider`, `ModelMenuCheckRow`, `ModelMenuChevronRow`, `ModelMenuDescriptionRow` or build a new one with the same paddings and `MenuRowHover`.

## Scrollbars: always `ThinScroller` (project canon)

App-wide standard for any scroll surface. The sidebar's scrollbar is the **visual reference**: a thin, low-opacity capsule that paints over the content, never the system's default fat gray bar with a track background. Anything new and anything retroactive must match it.

The canonical implementation lives in `macos/Sources/Clawix/ThinScrollbar.swift` and exposes two entry points; pick the one that matches the underlying scroll container, never roll a new scroller class.

Spec (numbers come from `ThinScroller`; do not invent values when reusing the look elsewhere):

- Scroller column width: `14 pt`.
- Thumb (knob): `9 pt` wide, inset `3 pt` from the scroller's right edge, with `8 pt` of vertical padding at top and bottom of the track. Minimum thumb height `40 pt`.
- Color: pure white (`NSColor(white: 1.0, alpha: …)`).
- Alpha: `0.10` idle, `0.18` while the cursor is over the scroller. No other states.
- Shape: capsule (`xRadius = yRadius = min(thumb.width, thumb.height) / 2`), rendered with `NSBezierPath(roundedRect:xRadius:yRadius:)`. The corner-radius lint exempts this site explicitly because at this radius the capsule is visually identical to a squircle (see the AppKit edge case noted under "Corner radius").
- Track background: none. `drawKnobSlot` is overridden to a no-op.
- Auto-hide on overflow: when content fits the viewport (`knobProportion >= 0.999`) `drawKnob` short-circuits, so an unscrollable list shows nothing. As soon as content overflows, the thumb is visible.
- No system fade-out: `alphaValue` is pinned to `1.0` while there's something to scroll. The thumb does not fade away after a few seconds of idle, the way the macOS overlay scroller does. The user always sees their position.

Two APIs, pick the right one:

- **`ThinScrollView { … }`** — full `NSViewRepresentable` wrapping a real `NSScrollView` with a `ThinScroller`. Used by surfaces that need a real AppKit scroll view (sidebar, slash-command menu, composer file viewer): the legacy scroller style + `autohidesScrollers = false` + a small `trailingGutter` keep the knob from being clipped by the SwiftUI hosting layer. Reach for this when (a) you already need the AppKit scroll view for other reasons (`EnclosingScrollViewLocator`, edge auto-scroll, manual contentInsets), or (b) the scroll surface is a popover/menu where the system overlay would behave wrong.
- **`.thinScrollers()`** — view modifier that walks up to the SwiftUI `ScrollView`'s underlying `NSScrollView` and swaps in a `ThinScroller` (overlay style, `autohidesScrollers = true`). Use this for any plain SwiftUI `ScrollView { … }`. It's the default for everything new.

Hard rules:

- **Every scroll surface uses `ThinScroller`.** A bare SwiftUI `ScrollView { … }` without `.thinScrollers()` is a bug. A bare `NSScrollView` without a `ThinScroller` as its `verticalScroller` is a bug. The only exceptions are `NSTextView` / scrolling text containers where AppKit owns the scroller for IME / cursor reasons; route those through `ThinScrollerInstaller` if practical.
- **Do not reintroduce the system scroller** (`scrollView.verticalScroller = NSScroller()`, `Picker` with default chrome, `List` defaults). The system overlay scroller fades out, has a visible track on hover, and uses platform-default sizes that don't match this app.
- **Do not change the alpha or thickness numbers per surface.** If a particular view feels too dim or too thin, fix it at the source in `ThinScroller` (and audit every screen) rather than forking the values for one place.
- **Do not show a SwiftUI scrollbar via `showsIndicators: true` and call it a day.** That ships the system scroller. Use `.thinScrollers()` regardless of the `showsIndicators` argument; the modifier replaces whatever scroller the SwiftUI ScrollView produced.
- **Horizontal scrollers** follow the same rule when present, but in practice most horizontal scroll surfaces in the app run with `showsIndicators: false` and rely on overflow gradients / chevrons. If a horizontal scroller ever needs a visible bar, extend `ThinScroller` rather than introducing a parallel custom class.

When migrating existing scroll views:

- A SwiftUI `ScrollView { … }`: append `.thinScrollers()` outside the closure (after any `.frame`, `.background`, etc., so the installer attaches once the hosting view is mounted).
- A nested SwiftUI `ScrollView` already inside a `ThinScrollView`: leave it alone, the outer scroller is what the user sees.
- A surface that wants `ScrollViewReader` / programmatic scroll: stick with SwiftUI `ScrollView` + `.thinScrollers()`. Do not migrate to `ThinScrollView` just for the look — the modifier already gives you the same look without losing `ScrollViewReader`.

# CLI · `cli/`

Top-level npm package, name `clawix`, distributed at https://www.npmjs.com/package/clawix. This is a legacy/transitional Clawix distribution surface. New public framework commands belong to the single `claw` CLI owned by ClawJS/Claw, not to a new `clawix` CLI surface.

Source lives in `cli/`, ships to npm with `bin/`, `lib/`, `README.md`, `LICENSE`. The package is **macOS-only** (`os: ["darwin"]`, `cpu: ["arm64", "x64"]`); the postinstall no-ops on other platforms with a helpful message.

The CLI is a thin Node.js wrapper around two pre-built, pre-signed Swift binaries:

- `clawix-bridge`: the same daemon `Clawix.app` ships under `Contents/Helpers/clawix-bridge`, sourced from `macos/Helpers/Bridge/`. Owns the `codex app-server` subprocess and the bridge's WebSocket listener.
- `clawix-menubar`: a tiny accessory app (NSStatusItem, no Dock, no main window) sourced from `macos/Helpers/Menubar/`. Polls the daemon, exposes the pairing QR, offers "Install Clawix.app…" as a one-click install hop.

`postinstall` downloads `clawix-cli-darwin-universal.tar.gz` from the GitHub release whose tag matches the npm package version, verifies SHA-256 against `cli/lib/checksums.json` (committed alongside the npm version bump), and unpacks both binaries into `~/.clawix/bin/` with `codesign --verify --strict` as the last gate. Nothing is built on the user's machine.

## Commands

```
clawix up           start daemon + menu bar, print pairing QR
clawix start        start daemon as LaunchAgent (set & forget)
clawix stop         bootout daemon + menu bar
clawix restart      kickstart the daemon
clawix status       daemon state, port, peers, app presence  (--json)
clawix pair         re-print pairing QR  (--json)
clawix logs [-f]    tail daemon stdout/stderr
clawix install-app  download + install /Applications/Clawix.app
clawix uninstall    remove ~/.clawix/bin/, bootout LaunchAgents  (--purge to drop pairing too)
```

## Files the CLI manages

```
~/.clawix/bin/clawix-bridge                    universal binary, signed
~/.clawix/bin/clawix-menubar                   universal binary, signed
~/.clawix/bin/manifest.json                    install metadata
~/Library/LaunchAgents/clawix.bridge.plist     daemon registration
~/Library/LaunchAgents/clawix.menubar.plist    menu bar registration
~/Library/Preferences/clawix.bridge.plist      pairing bearer (shared with GUI)
/tmp/clawix-bridge.{out,err}                   daemon logs
```

## Coexistence with `Clawix.app`

Both surfaces register the same LaunchAgent **label** (`clawix.bridge`) and read/write the same UserDefaults **suite** (`clawix.bridge`). The pairing bearer (`ClawixBridge.Bearer.v1`) lives in that public suite, so:

- A user with only the CLI pairs an iPhone, then runs `clawix install-app`. The GUI takes over the daemon slot on next launch; the iPhone keeps working with no re-pair.
- A user with only the GUI later runs `npm install -g clawix` (e.g. to script automation). The CLI's `daemon.start()` detects the existing label loaded from `/Applications/Clawix.app/...`, defers, and just reports status.
- `clawix-bridge` resolution prefers `/Applications/Clawix.app/Contents/Helpers/clawix-bridge` over the npm-shipped copy whenever the GUI is installed, so both surfaces drive a single binary.

There is exactly one daemon process at any time.

## Hard rules for contributors and AI agents

- **No private literals in `cli/`**: no Team ID, no maintainer bundle id, no codesign identity, no SKU. The hygiene gate scans `cli/` along with the public platform and package trees.
- **No competitor brand names in `cli/`**: the CLI is positioned standalone, not as a port or clone of any existing tool. Code, comments, copy and error messages must stay neutral.
- **No hand-rolled JS-side crypto, signing or notarization**: the binaries arrive from GitHub releases pre-signed and pre-notarized with Developer ID. The CLI verifies, never re-signs.
- **No third-party npm dependencies in v1**: the package is intentionally zero-dep. If you need an npm dep, justify it; smaller surface = less supply-chain risk for users who run `npm install -g clawix`.
- **No `sudo` from postinstall or the CLI**: every path it writes (`~/.clawix/bin/`, `~/Library/LaunchAgents/`, `~/Library/Caches/clawix/`) is in the user's home. `clawix install-app` copies into `/Applications` via `ditto` (which works without sudo when the user has write access; if they don't, the copy fails cleanly without a privilege escalation prompt).

# iOS app · `ios/`

## Design language: iOS 26 Liquid Glass

Default visual identity for every screen, view, modifier and reusable widget on iOS is **iOS 26 Liquid Glass**. Floating chrome (top-bar pills, composer, action buttons, sheets, badges, scroll-to-bottom dots, etc.) is built on `glassEffect(_:in:)` and grouped with `GlassEffectContainer` so adjacent shapes morph together when they animate.

Hard rules:

- **Always** prefer the native iOS 26 APIs over manual translucency. `.ultraThinMaterial`, custom blur views, opaque dark fills with low alpha, hand-rolled "fake glass" gradient stacks: NO. `.glassEffect(.regular, in: Capsule(style: .continuous))`, `.glassEffect(.regular, in: Circle())`, `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))`, `GlassEffectContainer`: YES.
- **Always** keep deployment target at iOS 26 so the call sites can use `.glassEffect()` directly without `if #available` ladders. If a view ever has to ship to an older iOS, gate it with availability and fall back, but the code path used by default is the iOS 26 one.
- **Pure black canvas** (`Color.black`) is the substrate beneath glass capsules: refraction reads cleanest against full black, not stacked dark grays.
- **Pill heights ≈ 50pt** for top-bar chrome, **composer ≈ 64pt**: glass needs vertical room for the highlight + refraction to read, thinner pills look like flat capsules.
- **No solid stroke borders on glass shapes**. The system glass effect already supplies the rim highlight; layering `.strokeBorder(Color.white.opacity(0.10))` on top kills the refraction.
- **Squircle rule still applies**: any RoundedRectangle passed as the shape to `.glassEffect(in:)` must use `style: .continuous`. Capsule and Circle are fine as-is.

Canonical helpers live in `Theme/GlassPill.swift` (`glassCapsule()`, `glassCircle()`, `glassRounded(radius:)`, `GlassIconButton`). Reuse them; do not re-derive the modifier chain by hand. Color and size tokens live in `Theme/DesignTokens.swift` (`Palette`, `AppLayout`, `Typography`); add to those files instead of inlining magic numbers.

Reference for layout, hierarchy and motion: ChatGPT iOS. The chat detail surface (light bubble for user messages, bare text for assistant, floating glass composer, two glass clusters in the top bar) is the visual baseline; copy paddings, radii and weights from there before inventing.

## Icons (iOS)

Same hierarchy as macOS:

1. **Project-custom icons first.** Glyphs that have identity in the product (the brand mark, the mic, the wrench, the family of folder/file/branch icons, etc.) are hand-drawn SwiftUI `Path`/`Shape` views. The macOS app already ships the canonical set (`ClawixLogoIcon`, `MicIcon`, `WrenchIcon`, `FileChipIcon`, `FolderOpenIcon`, ...). Where iOS needs the same concept, port the existing Mac struct into `ios/Sources/Clawix/Theme/` (or move it to `packages/` if it stabilises) rather than redrawing.
2. **Lucide-sourced icons as fallback.** Same rules as the macOS section "Lucide-sourced icons":
   - The SPM dep is `lcandy2/LucideIcon`, declared in `ios/project.yml` under `packages` and added to the `Clawix` target's `dependencies`. Re-run `xcodegen generate` after editing `project.yml`.
   - Call sites use `Image(lucide: .name)` (kebab-to-underscore naming: `chevron-down` → `.chevron_down`).
   - The bridge is `ios/Sources/Clawix/Theme/LucideBridge.swift`, mirroring the macOS file. Dynamic name strings flow through `Image(lucideOrSystem: name)`.
   - Files that use Lucide need `import LucideIcon` next to `import SwiftUI`.
3. **SF Symbols stay forbidden** as a generic fallback. The only legitimate `Image(systemName:)` left is for genuinely OS-level chrome (keyboard shortcut indicators, Liquid Glass system buttons that ship a fixed SF Symbol per Apple's HIG). Anything depicting a domain concept goes through Lucide.

This applies on top of the Liquid Glass design language: a `Image(lucide: .name)` placed inside a `glassCircle()` or `glassCapsule()` button is the canonical iOS chrome icon button, not `Image(systemName:)`.
