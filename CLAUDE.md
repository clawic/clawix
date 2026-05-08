# Clawix

Monorepo for the Clawix project. Native clients for the [`codex`](https://github.com/openai/codex) CLI. The repo is designed to host several apps (macOS, iOS, …), each in its own subdirectory under `apps/`.

## Repository layout

```
apps/
  macos/        # macOS client (SwiftUI), exists.
  ios/          # iOS client (placeholder, not implemented yet).
```

Each app is autonomous: its own `Package.swift` (or Xcode project), its own scripts, its own bundle id. The only repo-wide assets are the brand, this `CLAUDE.md`, and the hygiene gate run before publishing.

## Build (macOS app)

Requirements: macOS 14+, Swift 5.9+, Xcode Command Line Tools.

### Dev loop

```
bash apps/macos/scripts/dev.sh
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
bash apps/macos/scripts/build_app.sh
```

Produces `apps/macos/build/Clawix.app`. Same `SIGN_IDENTITY` / `BUNDLE_ID` resolution as `dev.sh`.

## Hygiene gate (publication)

Before publishing anything, this must pass:

```
bash apps/macos/scripts/public_hygiene_check.sh
```

It scans the entire repo (root + `apps/*/Sources` + `apps/*/scripts` + `apps/*/Resources`) for: developer-machine paths, secret-looking literals, hex digests, hard-coded codesign material, Apple Team IDs and committed `.signing.env` files. When new apps are added under `apps/`, their tree is picked up automatically because the gate iterates `apps/*/`.

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
- **Do not commit** the file `.signing.env`. It is in `.gitignore` and `apps/macos/scripts/public_hygiene_check.sh` fails the build if a copy is detected inside the public tree.
- **Do not introduce** an `Info.plist` with a literal bundle id. The plist is generated in `build_app.sh` interpolating `${BUNDLE_ID}`.
- **Do not add** an Xcode project with a concrete development team value. Leave the field empty; the script supplies it from the environment.

If you need to expose a new piece of local config (another identifier, another flag), add the variable to the scripts and document it in `.signing.env.example`. Never the other way around.

---

# macOS app · `apps/macos/`

Native macOS client (SwiftUI) for the `codex` CLI. The visible app is a frontend. Runtime ownership is split by mode:

- Normal in-process mode: the app reads `~/.codex/auth.json`, runs the `codex` binary for login/logout, and connects to the JSON-RPC app-server the CLI exposes for threads, messages and events.
- Background bridge mode: a bundled `clawix-bridged` helper owns the Codex app-server connection and the local bridge. The Mac app connects back to that daemon over loopback instead of starting its own backend/bridge. iOS scans the daemon QR/token and talks to the same daemon, so Mac and iOS share one runtime owner.

Do not reintroduce a second GUI-owned bridge/backend when background bridge mode is enabled. Any iOS-visible runtime feature should be implemented on the daemon bridge surface first, then consumed by the Mac app and iOS clients.

## Layout

- `apps/macos/Package.swift`: Swift Package, target `Clawix`, macOS 14+. One external dependency: [Sparkle 2](https://sparkle-project.org) for in-app updates.
- `apps/macos/VERSION`: single source of truth for the marketing version. `dev.sh` and the release scripts read it via `_emit_version.sh` and inject it into the generated Info.plist.
- `apps/macos/Sources/Clawix/`: SwiftUI source.
- `apps/macos/Sources/Clawix/AppVersion.swift`: reads `CFBundleShortVersionString` / `CFBundleVersion` at runtime so the app reports the version it was actually compiled with.
- `apps/macos/Sources/Clawix/Updater/UpdaterController.swift`: thin wrapper around `SPUStandardUpdaterController`. Drives the "Update" chip in the top bar.
- `apps/macos/Sources/Clawix/DaemonBridgeClient.swift`: loopback client used by the Mac app when the background bridge daemon is active.
- `apps/macos/Helpers/Bridged/`: Swift helper executable that runs as the background bridge daemon and owns the Codex runtime connection in background bridge mode.
- `apps/shared/ClawixCore/`: shared bridge wire protocol.
- `apps/shared/ClawixEngine/`: shared bridge server/session/pairing runtime.
- `apps/macos/scripts/dev.sh`: dev launcher (build + relaunch). Copies Sparkle.framework into the bundle and signs deep.
- `apps/macos/scripts/build_app.sh`: release-only `.app` builder (single identity, deep sign).
- `apps/macos/scripts/build_release_app.sh`: notarization-ready builder. Reads `DEVELOPER_ID_IDENTITY` from env and applies per-component hardened-runtime signing in the order Sparkle requires.
- `apps/macos/scripts/public_hygiene_check.sh`: hygiene gate scanned across the whole repo.

The full release orchestration (notarytool, DMG packaging, Sparkle EdDSA signing, appcast regeneration, GitHub Release upload) is intentionally NOT in this public tree. It lives in the maintainer's private workspace and consumes `build_release_app.sh` plus credentials from `.signing.env`.

## Background bridge daemon architecture

The bridge daemon is the canonical host for cross-device runtime work. It starts the Codex app-server over stdio, keeps the bridge listening on its configured port, and publishes the same wire protocol used by iOS. In daemon mode, the Mac app is just another authenticated desktop client over `127.0.0.1`.

Required invariants:

- One runtime owner. When background bridge mode is active, the Mac app must not also bootstrap its own Codex backend or publish another `BridgeServer`.
- Shared pairing. The QR payload, bearer token and port must point to the daemon, not to a GUI-local server.
- Shared state. Chat list, history hydration, new chat creation, prompt sending, streaming updates and archive state flow through the daemon so iOS and Mac observe the same source of truth.
- Daemon-first expansion. If a new bridge feature needs to work on iOS, add daemon support and E2E coverage for that frame before wiring UI clients to it.
- No real-cost validation by default. E2E tests should use isolated fake backends unless the user explicitly approves a real prompt. Real host validation may authenticate and list chats, but must not send real prompts without confirmation.

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

App-wide standard for any 2-N mutually-exclusive choice picker (e.g. "Used / Remaining", "Queue / Drive", "Inline / Detached", "STDIO / HTTP streaming", merge methods, transport modes). The canonical component lives in `apps/macos/Sources/Clawix/SettingsView.swift` as `SlidingSegmented<T>` and is the only correct way to render this pattern.

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

The app ships its own hand-drawn icons (Canvas / Path / Shape) for every glyph that has a strong identity in the UI: documents, folders, terminal, globe, mic, search, branch, pin, archive, copy, pencil, branch-arrows, sidebar toggle, etc. They live in `apps/macos/Sources/Clawix/` next to the rest of the views and are exported as plain `View` types (e.g. `FileChipIcon`, `TerminalIcon`, `GlobeIcon`, `FolderOpenIcon`, `MicIcon`, `SearchIcon`, `CursorIcon`).

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

In code, the same path is reproduced in `apps/macos/Sources/Clawix/ClawixLogoIcon.swift`. Two entry points:

- `ClawixLogoIcon(size:)` — SwiftUI `View`, fills with `.primary`. Use anywhere inside the SwiftUI hierarchy (splash, about screen, empty states, settings).
- `ClawixLogoTemplateImage.make(size:)` — flattens the shape into an `NSImage` with `isTemplate = true`. Required for `MenuBarExtra` because its label slot does not render arbitrary SwiftUI `Shape`s reliably (renders as an empty hole). AppKit applies the menu bar's foreground tint automatically when the image is template.

Hard rules:

- The brand mark is `ClawixLogoIcon` / `ClawixLogoTemplateImage`. Never re-derive the path inline somewhere else, never use `Image(systemName:)` as a stand-in.
- When the SVG master changes (`brand/clawix-logo.svg`), update the path in `ClawixLogoIcon.swift` to match. The two are intentionally redundant: the SVG is the human-editable source, the Swift path is the runtime rendering. If the iOS app eventually ships, it imports `brand/clawix-logo.svg` (or replicates the same path natively); the master in `brand/` stays canonical.
- For places that need the `.icns` / iOS asset catalog renders, those are produced from the same master (currently the `.icns` lives in `apps/macos/Sources/Clawix/Resources/Clawix.icns`). When updating the brand, regenerate both the in-code path and the rasterized asset; do not let them drift.

Hard rules:

- **One file per icon, named after it.** New icons go in their own `XxxIcon.swift` file. Do not paste a Canvas / Path icon body into a feature view file. Existing icons that live in feature files (the "legacy spot" rows above) are pending extraction; treat them as an exception, not a precedent.
- **Never duplicate a custom icon's body across files.** If you need the same glyph in a new place, import the existing struct. If two places need slightly different sizes / colors, parametrize the existing struct with `var size: CGFloat`, `var color: Color`, etc., do NOT copy/paste.
- **Before reaching for `Image(systemName: "…")`, check the table above and grep the project for `<concept>Icon`.** When the glyph genuinely has no project-custom equivalent, the canonical fallback is a **Lucide-sourced icon**, NOT an SF Symbol. See "Lucide-sourced icons" below.
- **The model behind this rule**: a custom icon is the project's design DNA. If you swap one for an SF Symbol the screen feels "off" even if you can't pinpoint why. The user notices.
- When in doubt about whether a glyph deserves a custom icon, **ask before drawing**. Hand-drawing an icon that already has a system equivalent and lives nowhere else in the app is wasted work.

## Lucide-sourced icons (project canon, fallback for non-custom glyphs)

When a glyph has no project-custom icon (the table above), the fallback is **Lucide** (https://lucide.dev), not SF Symbols. Lucide has a clean, restrained outline language that sits next to our custom Path-based icons without breaking visual consistency; SF Symbols feel generic next to the rest of the chrome.

Hard rules:

- **Hand-port the Lucide SVG path into a SwiftUI `Shape`/`Path`.** Do not import an icon library, do not bundle the Lucide font (`.ttf`), do not ship Lucide SVGs as resources. Each glyph we use becomes a struct that draws the path directly. This keeps the binary lean (only what we use) and keeps Lucide-sourced glyphs distinguishable from our custom hand-drawn ones.
- **Cite the source in the file.** The doc comment at the top of every Lucide-sourced struct says, literally, that it is ported from `lucide-icons/lucide` and names the SVG file (e.g. `// Source: lucide-icons/lucide · chevron-down.svg`). This is the only signal a future contributor has that the icon is library-derived rather than project-original. Custom icons MUST NOT carry that comment, Lucide-sourced ones MUST.
- **Registry file, not one-file-per-icon.** Lucide-sourced icons live in a single `LucideIcon.swift` registry (`apps/macos/Sources/Clawix/LucideIcon.swift`, mirrored at `apps/ios/Sources/Clawix/Theme/LucideIcon.swift` for iOS). The "one file per icon" convention applies to project-custom icons (which carry identity); Lucide ones are fallback glyphs and a single file is more pragmatic.
- **Lucide native spec stays.** Drawn on a 24-pt grid, 2-pt stroke (scaled with `lineWidth: 1.6 * (size / 24)` or similar), `lineCap: .round`, `lineJoin: .round`. Do not "improve" the silhouette; the value of using Lucide is consistency with a known design language.
- **SF Symbols stay forbidden** as a generic fallback. The only legitimate `Image(systemName:)` left in the codebase is for genuinely OS-level chrome where the platform glyph is the right answer (e.g. `command` for the Cmd modifier in keyboard shortcut hints, system menu/menubar conventions where AppKit owns the rendering). Anything that depicts a domain concept (folder, document, trash, search, chevron, plus, x, arrow, etc.) goes through Lucide.

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

# iOS app · `apps/ios/`

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

1. **Project-custom icons first.** Glyphs that have identity in the product (the brand mark, the mic, the wrench, the family of folder/file/branch icons, etc.) are hand-drawn SwiftUI `Path`/`Shape` views. The macOS app already ships the canonical set (`ClawixLogoIcon`, `MicIcon`, `WrenchIcon`, `FileChipIcon`, `FolderOpenIcon`, …). Where iOS needs the same concept, port the existing Mac struct into `apps/ios/Sources/Clawix/Theme/` (or move it to `apps/shared/` if it stabilises) rather than redrawing.
2. **Lucide-sourced icons as fallback.** When a glyph has no project-custom equivalent, port a **Lucide** SVG path by hand into a SwiftUI `Shape`. Same rules as the macOS section "Lucide-sourced icons":
   - Hand-port the path directly. Do not import a library, do not bundle the Lucide font, do not ship the SVGs as resources.
   - Cite the source in the file (`// Source: lucide-icons/lucide · <name>.svg`). Custom icons MUST NOT carry that comment; Lucide-sourced ones MUST.
   - Single registry file: `apps/ios/Sources/Clawix/Theme/LucideIcon.swift`. Mirrors the macOS registry in shape so the API at call sites is identical (`LucideIcon(.chevronDown, size: 16)`).
   - Lucide native spec stays: 24-pt grid, 2-pt stroke (scaled with the size), `lineCap: .round`, `lineJoin: .round`. Do not "improve" the silhouette.
3. **SF Symbols stay forbidden** as a generic fallback. The only legitimate `Image(systemName:)` left is for genuinely OS-level chrome (Liquid Glass system buttons that ship a fixed SF Symbol per Apple's HIG, keyboard shortcut indicators, etc.). Anything depicting a domain concept goes through Lucide.

This applies on top of the Liquid Glass design language: a `LucideIcon` placed inside a `glassCircle()` or `glassCapsule()` button is the canonical iOS chrome icon button, not `Image(systemName:)`.
